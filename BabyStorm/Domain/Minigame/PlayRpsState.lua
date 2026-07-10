local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")
local FlightDriver = require("BabyStorm.Core.Drivers.FlightDriver")
local UnitUtil = require("Util.UnitUtil")
local RoleUtil = require("Util.RoleUtil")
local Rand = require("Util.Rand")
local Log = require("Util.Log")

-- 猜拳小游戏行为状态：配对 → 抛骰 → 顶撞 → 判分，全流程一个状态内用 phase 推进。
-- 基础交互（宝宝举起自己的骰子）已经满足需求；后续配对/抛骰/顶撞/判胜负都是额外加分项，
-- 不强制玩家参与——玩家一直不响应就走 giving_up 分支按满足收尾（同顶球玩法设计）。
--
-- phase: wait_player -> ready -> tossing -> settling -> finishing
--                     \-> giving_up -> finishing（玩家超时未响应）
---@class PlayRpsState: StateBase
---@field _prop DiceProp|nil
---@field _baby_die_index integer|nil
---@field _player_die_index integer|nil
local PlayRpsState = Class("BabyPlayRpsState", StateBase)

---@param agent BabyAgent
function PlayRpsState:Ctor(agent)
    PlayRpsState.super.Ctor(self, agent)
    -- 两颗骰子的垂直上抛各用一个飞行驱动实例，互不干扰。
    self._flight_baby = FlightDriver.New()
    self._flight_player = FlightDriver.New()
end

---@param context BabyStateContext|{ dice: DiceProp, baby_die_index: integer }|nil
function PlayRpsState:enter(context)
    PlayRpsState.super.enter(self, context)
    local agent = self.agent
    self.cfg = agent.config.rps

    local prop = context and context.dice or nil
    local baby_die_index = context and context.baby_die_index or nil
    self._prop = prop
    self._baby_die_index = baby_die_index
    self._player_die_index = baby_die_index == 1 and 2 or 1

    self._player_unit = nil
    self._player_candidate = prop:holder(self._player_die_index)
    self._role = nil
    self._face_target = nil
    self._pairing_mobile = false
    self._hold_elapsed = 0.0
    self._release_elapsed = 0.0
    self._baby_retry_elapsed = 0.0
    self._baby_missing_elapsed = 0.0
    self._floor_y = nil
    self._flight_done_count = 0
    self._settle_elapsed = 0.0
    self._rest_frames = 0
    self._bonk_count = 0
    self._pending_jump = nil

    agent:cancel_need_countdown()
    agent:set_lift_enabled(false)
    agent:set_status("我举一个，你举另一个！")
    agent.unit.lift_unit(prop:get(baby_die_index))
    self:set_intent({ move_mode = Intent.MoveMode.Stop, anim_base = Intent.AnimBase.Idle, action_lock = true })

    self.phase = "wait_player"
    self._wait_timer = Timer.once(self, self.cfg.wait_player_timeout, function()
        self:_begin_give_up()
    end)
    Log.info("rps baby holding", agent.index)
end

---@param event table
function PlayRpsState:handle_event(event)
    if not event then
        return
    end
    if event.type == "dice_lift_begin" then
        if self.phase == "wait_player" and event.index == self._player_die_index
            and event.lift_unit and not UnitUtil.same_unit(event.lift_unit, self.agent.unit)
        then
            self._player_candidate = event.lift_unit
            self._hold_elapsed = 0.0
        end
    elseif event.type == "dice_lift_end" then
        if event.index == self._player_die_index and event.lift_unit and not self._player_candidate then
            self._player_candidate = event.lift_unit
        end
    end
end

---@param dt Fixed
function PlayRpsState:update(dt)
    if self.phase == "wait_player" then
        self:_update_wait_player(dt)
    elseif self.phase == "ready" then
        self:_update_ready(dt)
    end
end

-- ============================================================
-- wait_player：等两边都举稳配对骰子。
-- ============================================================

---@param dt Fixed
function PlayRpsState:_update_wait_player(dt)
    local agent = self.agent
    local prop = self._prop
    local candidate = self._player_candidate or prop:holder(self._player_die_index)

    -- “玩家进入配对范围”= 靠近宝宝 且 正举着配对骰子。只有这时才转视角看玩家 +
    -- 在其周围小步挪动（减少 AI 生硬感）。玩家还没走近、或已把骰子丢下 → 不锁视角、不刻意挪，
    -- 免得“玩家一举起/一丢下骰子，宝宝就隔着老远把头转过去还傻站着倒计时”的违和表现。
    local player_present = candidate
        and self:_unit_near_baby(candidate)
        and prop:is_held_by(candidate, self._player_die_index)
    if player_present then
        self:_set_face_target(candidate)
        self:_set_pairing_mobile(true)
    else
        self:_set_face_target(nil)
        self:_set_pairing_mobile(false)
    end

    if not prop:is_held_by(agent.unit, self._baby_die_index) then
        self._hold_elapsed = 0.0
        self._baby_retry_elapsed = self._baby_retry_elapsed + dt
        if self._baby_retry_elapsed >= 0.5 then
            self._baby_retry_elapsed = 0.0
            agent.unit.lift_unit(prop:get(self._baby_die_index))
        end
        return
    end
    self._baby_retry_elapsed = 0.0
    -- 两边必须都被引擎确认为“正在举着指定骰子且贴近”，连续稳定两拍才进入就绪。
    if not player_present then
        self._hold_elapsed = 0.0
        return
    end
    self._hold_elapsed = self._hold_elapsed + dt
    if self._hold_elapsed >= 0.2 then
        -- 配对达成：冻回原地（重新锁住，供就绪/抛骰阶段稳定判定），保持面向玩家。
        self:_set_pairing_mobile(false)
        self._player_unit = candidate
        self._role = RoleUtil.get_role_by_unit(candidate)
        self._release_elapsed = 0.0
        Timer.cancel(self._wait_timer)
        self._wait_timer = nil
        self.phase = "ready"
        agent:set_status("一起往头顶抛！")
        Log.info("rps both holding", agent.index)
    end
end

-- 进入/退出“配对小步挪动”模式（仅在玩家进入配对范围时开启，配对达成或玩家离开即关闭）。
-- 开启：写参数化 Wander 意图（解锁移动），以当前位置为锚点、只在小半径内游走——半径很小，
--       保证宝宝始终在玩家配对范围内、不会走开导致配对失败。
-- 关闭：立即停步（perform 保证即时生效）并重新冻回 Stop + 锁定。
---@param mobile boolean
function PlayRpsState:_set_pairing_mobile(mobile)
    if self._pairing_mobile == mobile then
        return
    end
    self._pairing_mobile = mobile
    local agent = self.agent
    if mobile then
        local pos = agent.unit.get_position()
        self:set_intent({
            move_mode = Intent.MoveMode.Wander,
            anim_base = Intent.AnimBase.Locomotion,
            wander = {
                anchor = pos,
                radius = self.cfg.pairing_fidget_radius,
                speed_ratio = 1.0,
                interval = self.cfg.pairing_fidget_interval,
                threshold = 0.3,
            },
            action_lock = false,
        })
    else
        agent.movement:perform("stop_move")
        self:set_intent({
            move_mode = Intent.MoveMode.Stop,
            anim_base = Intent.AnimBase.Idle,
            action_lock = true,
        })
    end
end

-- 配对等待/就绪期间让宝宝转头看向玩家（候选人变化才重新调用引擎接口，避免每帧重复）。
-- unit 为 nil 时解除锁定。
---@param unit Unit|nil
function PlayRpsState:_set_face_target(unit)
    if self._face_target == unit then
        return
    end
    self._face_target = unit
    if unit then
        self.agent.movement:perform("face_target", { unit = unit })
    else
        self.agent.movement:perform("clear_face_target")
    end
end

---@param text string
function PlayRpsState:_reset_player_wait(text)
    self._player_unit = nil
    self._player_candidate = nil
    self._role = nil
    self._hold_elapsed = 0.0
    self._release_elapsed = 0.0
    self._baby_retry_elapsed = 0.0
    self._baby_missing_elapsed = 0.0
    Timer.cancel(self._wait_timer)
    self._wait_timer = Timer.once(self, self.cfg.wait_player_timeout, function()
        self:_begin_give_up()
    end)
    self.phase = "wait_player"
    self.agent:set_status(text)
end

-- ============================================================
-- ready：双方举稳，等玩家松手一起抛。
-- ============================================================

---@param dt Fixed
function PlayRpsState:_update_ready(dt)
    local agent = self.agent
    local prop = self._prop
    local player = self._player_unit
    self:_set_face_target(player)
    if prop:is_held_by(agent.unit, self._baby_die_index) then
        self._baby_missing_elapsed = 0.0
    else
        self._baby_missing_elapsed = self._baby_missing_elapsed + dt
        if self._baby_missing_elapsed >= 0.5 then
            self:_reset_player_wait("我重新举好，你再来一次！")
        end
        return
    end
    if prop:is_held_by(player, self._player_die_index) then
        self._release_elapsed = 0.0
        return
    end
    -- 玩家必须先被确认举稳，再连续确认已经放手；不会再把“举起过程事件”误判成抛出。
    self._release_elapsed = self._release_elapsed + dt
    if self._release_elapsed < 0.2 then
        return
    end
    if not self:_unit_near_baby(player) then
        self:_reset_player_wait("靠近我再一起抛！")
        return
    end
    self:_begin_toss()
end

-- ============================================================
-- tossing：脚本把两颗骰子从当前握持位置垂直升到抛物顶点（只控位移，无水平偏移）。
-- ============================================================

-- 玩家已经把自己那颗骰子松手（release 检测通过）。此处让宝宝也松手，随后脚本接管两颗骰子，
-- 各自“垂直于头顶”上抛（原生抛掷是向前抛，做不出垂直，所以整段位移由脚本控制）。
function PlayRpsState:_begin_toss()
    local agent = self.agent
    -- 抛掷开始，宝宝要能自由转身/走位/跳跃，解除配对阶段的面向锁定。
    self:_set_face_target(nil)
    -- 宝宝松手（播放抛出动作）；力已归零，不会向前甩。ai_command_lift 和 jump/start_move
    -- 一样受 AI 开关影响——这里仍处于 action_lock 锁定期（AI 还没被重新打开），不先开 AI
    -- 的话这次松手会静默失效：骰子会一直挂在手上被引擎的举起吸附强制跟随，
    -- 视觉上看起来像是"抱着骰子跑"而不是被抛出去。perform 内部先 start_ai 再松手。
    if agent.unit.is_lift_status() then
        agent.movement:perform("release_lift")
    end
    -- 记录地面参考高度（宝宝当前站立处），用于落地判定：骰子必须真正落回地面附近，
    -- 而不是卡在角色头顶就被误判为“已落定”。
    local baby_pos = agent.unit.get_position()
    self._floor_y = baby_pos and baby_pos.y or nil

    self._flight_done_count = 0
    self:_toss_die(self._baby_die_index, self._flight_baby)
    self:_toss_die(self._player_die_index, self._flight_player)

    self.phase = "tossing"
    agent:set_status("石头、剪刀、布！")
    Log.info("rps toss started", agent.index)
end

-- 准备一颗骰子的垂直上抛：从骰子被举着的当前位置，纯垂直升高 throw_height（x/z 完全不变，
-- 不依赖任何缓存的地面高度——骰子可能已经被抱着走动过，缓存的地面高度会对不上当前位置）。
-- 抛掷期间关闭物理，位移完全由 FlightDriver 控制；到达顶点后才交还物理，让它真正自由下落，
-- 这样才有一段可以被顶/被撞的空中时间，而不是刚交还物理就已经贴地。
---@param index integer
---@param flight FlightDriver
function PlayRpsState:_toss_die(index, flight)
    local prop = self._prop
    local die = prop:get(index)
    local start_pos = die.get_position()
    prop:freeze_for_toss(index)
    flight:start({
        unit = die,
        from = start_pos,
        to = math.Vector3(start_pos.x, start_pos.y + self.cfg.throw_height, start_pos.z),
        duration = self.cfg.throw_duration,
        ease = "out", -- 纯减速（骰子垂直上抛，非弧线）
        on_complete = function() self:_on_toss_complete() end,
    })
end

-- 到达顶点后把两颗骰子交还物理引擎；两颗都到顶才进入 Settling。
function PlayRpsState:_on_toss_complete()
    self._flight_done_count = self._flight_done_count + 1
    if self._flight_done_count < 2 then
        return
    end
    self._prop:restore_physics(self._baby_die_index)
    self._prop:restore_physics(self._player_die_index)
    self:_begin_settle()
end

-- ============================================================
-- settling：落地结算（轮询静止）+ 宝宝自动顶撞。
-- ============================================================

-- 进入结算阶段：解锁让宝宝能自己走两步 + 起跳顶骰子（模仿玩家跳起顶骰子的同一动作）；
-- 玩家侧不脚本化，玩家自己跳。两颗骰子都静止后才结算。
function PlayRpsState:_begin_settle()
    self:set_intent({ move_mode = Intent.MoveMode.Stop, anim_base = Intent.AnimBase.Idle, action_lock = false })
    self.phase = "settling"
    self._settle_elapsed = 0.0
    self._rest_frames = 0
    self._bonk_count = 0
    self._pending_jump = nil
    -- 低频传感：轮询是否已落定。
    Timer.every(self, 0.1, function() self:_settle_tick() end)
    -- 顶撞链：随玩家抛出一起跳顶，第一下延迟后触发，后续由 _do_bonk 自己续挂。
    Timer.once(self, self.cfg.baby_bonk_first_delay, function() self:_do_bonk() end)
    Log.info("rps settling begin")
end

function PlayRpsState:_settle_tick()
    self._settle_elapsed = self._settle_elapsed + 0.1

    -- 顶撞序列没跑完之前不进入静止判定：骰子两次顶撞之间可能短暂停住（速度/高度都达标），
    -- 若这时就开始计静止帧数，会在宝宝跳到一半时就被判定"已落定"提前结算，顶撞次数被腰斩。
    -- 必须等 bonk_count 打满且没有还在走位/待跳的动作，才允许轮询静止。
    local bonking_done = self._bonk_count >= self.cfg.baby_bonk_max and not self._pending_jump
    if bonking_done and self._settle_elapsed >= self.cfg.settle_min_time and self:_dice_at_rest() then
        self._rest_frames = self._rest_frames + 1
    else
        self._rest_frames = 0
    end

    if (bonking_done and self._rest_frames >= self.cfg.settle_rest_frames)
        or self._settle_elapsed >= self.cfg.settle_timeout
    then
        self:_finish_settle()
    end
end

-- 宝宝顶撞循环：随玩家抛出，第一下原地起跳直顶（骰子基本在头顶正上方）；
-- 之后每次都带随机横向偏移贴边斜顶，让骰子在空中翻滚，最多顶 baby_bonk_max 次。
function PlayRpsState:_do_bonk()
    local agent = self.agent
    self._bonk_count = self._bonk_count + 1

    local dir = self:_baby_bonk_dir(agent.unit, self._bonk_count >= 2)
    if dir then
        agent.movement:perform("directional_move", { dir = dir, duration = self.cfg.baby_bonk_move_time })
        -- 走位后延迟一拍再起跳，做出“先挪一点再顶”的手感。
        self._pending_jump = Timer.once(self, self.cfg.baby_bonk_move_time, function()
            self._pending_jump = nil
            agent.movement:perform("jump")
        end)
    else
        -- 无需走位（骰子在正上方）：直接起跳直顶。
        self._pending_jump = nil
        agent.movement:perform("jump")
    end

    if self._bonk_count < self.cfg.baby_bonk_max then
        Timer.once(self, self.cfg.baby_bonk_interval, function() self:_do_bonk() end)
    end
end

-- 宝宝走位方向。非 randomize（第一次）：骰子基本在头顶正上方就返回 nil（原地直顶），
-- 否则朝骰子水平方向走。randomize（之后）：一定带随机横向偏移，贴边斜顶 → 空中翻滚。
---@param unit Unit
---@param randomize boolean
---@return Vector3|nil
function PlayRpsState:_baby_bonk_dir(unit, randomize)
    local baby_pos = unit.get_position()
    if not baby_pos then
        return nil
    end
    -- 骰子可能已被打飞出界销毁：读不到位置按“就在头顶”处理（length=0，随机方向斜顶）。
    local dok, die_pos = pcall(function() return self._prop:get(self._baby_die_index).get_position() end)
    local dx, dz, length = 0.0, 0.0, 0.0
    if dok and die_pos then
        dx = die_pos.x - baby_pos.x
        dz = die_pos.z - baby_pos.z
        length = math.sqrt(dx * dx + dz * dz)
    end

    if not randomize then
        if length < 0.3 then
            return nil
        end
        return math.Vector3(dx / length, 0.0, dz / length)
    end

    local bx, bz
    if length < 0.3 then
        bx, bz = Rand.signed(), Rand.signed()
        if bx * bx + bz * bz < 0.01 then
            bx, bz = 1.0, 0.0
        end
    else
        bx, bz = dx / length, dz / length
        local perp_x, perp_z = -bz, bx
        local offset = Rand.signed() * self.cfg.baby_bonk_offset
        bx = bx + perp_x * offset
        bz = bz + perp_z * offset
    end
    local norm = math.sqrt(bx * bx + bz * bz)
    if norm > 0.0001 then
        bx, bz = bx / norm, bz / norm
    end
    return math.Vector3(bx, 0.0, bz)
end

-- 两颗骰子都接近静止（线速度足够小）且真正落回地面附近（而不是卡在角色头顶/身上）才算落定。
-- 高度判定用“每颗骰子各自脚下的真实地面”做参考（向下射线取地面高度），而不是共用宝宝抛出时的
-- 站立高度——否则玩家站在别处/骰子落在高台或卡在头顶时，会用错参考面把没落地的骰子误判成已落定
-- （用户反馈“玩家的骰子没落地就判了”）。
---@return boolean
function PlayRpsState:_dice_at_rest()
    local eps = self.cfg.settle_rest_speed
    local tol = self.cfg.settle_ground_tolerance
    local arena = self.agent.services.arena
    local prop = self._prop
    for index = 1, prop:count() do
        local die = prop:get(index)
        -- 骰子可能在下落/顶撞中被打飞出界销毁：读不到速度/位置就永远判“未落定”，
        -- 最终由 settle_timeout 兜底强制结算（原实现同语义）。
        local ok, v = pcall(function() return die.get_linear_velocity() end)
        if not (ok and v) then
            return false
        end
        local speed_sq = v.x * v.x + v.y * v.y + v.z * v.z
        if speed_sq > eps * eps then
            return false
        end
        local pok, pos = pcall(function() return die.get_position() end)
        if not (pok and pos) then
            return false
        end
        local ground_y = self:_ground_y_under(arena, pos)
        if pos.y - ground_y > tol then
            return false -- 骰子中心明显高出脚下地面：还悬在半空/卡在头顶，不算落定
        end
    end
    return true
end

-- 取某点正下方的真实地面高度：优先用 arena 的向下射线（打已摆放的地面组件）；
-- 射线没命中（返回原点、y 不变）时回退到抛出时记录的 floor_y。
---@param arena ArenaService|nil
---@param pos Vector3
---@return Fixed
function PlayRpsState:_ground_y_under(arena, pos)
    if arena and arena.ground_point then
        local ok, gp = pcall(function() return arena:ground_point(pos) end)
        if ok and gp and gp.y and gp.y ~= pos.y then
            return gp.y
        end
    end
    return self._floor_y or pos.y
end

-- 完整跑完了配对 + 抛骰 + 顶撞，两颗骰子落地静止：读朝上面判石头剪刀布胜负（玩家视角），
-- 基础满足分之外按 win/draw/lose 分档追加加分（没干净落面则 outcome=nil，只给基础满足分）。
function PlayRpsState:_finish_settle()
    local prop = self._prop
    -- 必须在 finish_rps 切状态（本状态 exit 会兜底恢复物理）之前读取朝向。
    local baby_gesture = prop:read_gesture(self._baby_die_index)
    local player_gesture = prop:read_gesture(self._player_die_index)
    local outcome = prop:judge_outcome(baby_gesture, player_gesture)
    self.agent:finish_rps(self._role, outcome)
    Log.info("rps settle finished", tostring(outcome))
end

-- ============================================================
-- giving_up：玩家超时未响应，宝宝抱着骰子闲逛一会儿再按满足收尾。
-- ============================================================

-- 玩家超时未响应：宝宝抱着骰子随意走动一会儿（模拟"找人玩"的感觉），逛够了再放下骰子收尾。
-- Wander 意图缺省 anchor：MovementSystem 落回场地随机点，即原闲逛逻辑。
function PlayRpsState:_begin_give_up()
    self:_set_face_target(nil)
    self:set_intent({
        move_mode = Intent.MoveMode.Wander,
        anim_base = Intent.AnimBase.Locomotion,
        wander = {
            speed_ratio = 1.0,
            interval = self.cfg.giveup_move_interval,
        },
        action_lock = false,
    })
    self.agent:set_status("没人理我，我自己溜达溜达…")
    self.phase = "giving_up"
    local duration = Rand.fixed(self.cfg.giveup_wander_min, self.cfg.giveup_wander_max)
    Timer.once(self, duration, function() self:_finish_solo_satisfy() end)
    Log.info("rps giving up, wandering seconds", duration)
end

-- 基础交互（宝宝举起自己的骰子）已足够满足需求；猜拳配对本身不强制玩家参与，只是额外加分项
-- （与顶球玩法同一设计：漏接/不参与也照常满足，只是拿不到额外加分）。
function PlayRpsState:_finish_solo_satisfy()
    local agent = self.agent
    if agent.unit.is_lift_status() then
        -- 保险起见走 perform（内部先 start_ai）：万一锁还没解开，直接松手会静默失效。
        agent.movement:perform("release_lift")
        -- 引擎坑位：invalidate 是「立即对齐」，若同帧就切状态触发 exit → Stop，
        -- stop_ai 会把刚发出的松手指令一并作废，骰子仍挂在手上——松手后隔一拍再收尾。
        self.phase = "finishing"
        Timer.once(self, 0.1, function()
            agent:finish_rps(nil, nil)
            Log.info("rps solo satisfy (no player response)")
        end)
        return
    end
    agent:finish_rps(nil, nil)
    Log.info("rps solo satisfy (no player response)")
end

---@param unit Unit|nil
---@return boolean
function PlayRpsState:_unit_near_baby(unit)
    -- 玩家可能中途断线/单位被回收，位置读不到一律按“不在范围内”处理。
    local baby_pos = self.agent.unit.get_position()
    local ok, unit_pos = pcall(function() return unit.get_position() end)
    if not (baby_pos and ok and unit_pos) then
        return false
    end
    local radius = self.cfg.trigger_radius
    return UnitUtil.distance_xz_sq(baby_pos, unit_pos) <= radius * radius
end

---@param context BabyStateContext|nil
function PlayRpsState:exit(context)
    local agent = self.agent
    self._flight_baby:stop()
    self._flight_player:stop()
    agent.movement:perform("clear_face_target")
    -- 抛掷/顶撞中途被打断（抱走/销毁）的兜底：确保骰子不会永久卡在无重力状态，幂等。
    if self._prop and self._baby_die_index then
        self._prop:restore_physics(self._baby_die_index)
        self._prop:restore_physics(self._player_die_index)
    end
    agent:set_lift_enabled(true)
    -- 下一个状态的 set_intent 会全量覆盖 move_mode/wander，这里不用手写清理。
    PlayRpsState.super.exit(self, context)
end

return PlayRpsState
