local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local RoleUtil = require("Util.RoleUtil")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Rand = require("Util.Rand")
local Log = require("Util.Log")

local State = {
    Idle = "idle",
    WaitPlayer = "wait_player",
    Ready = "ready",
    Tossing = "tossing",    -- 脚本把两颗骰子从当前握持位置垂直升到抛物顶点（只控位移，无水平偏移）。
    Settling = "settling",  -- 到达顶点后交还物理：骰子在真实重力下自由下落，可被顶/被撞，轮询静止再结算。
    GivingUp = "giving_up", -- 玩家超时未响应：宝宝抱着骰子随意走动一会儿，再放下骰子按满足收尾。
}

local LOCK = "rps"
local ZERO = math.Vector3(0.0, 0.0, 0.0)

-- 骰子“本地轴 → 手势”标定：零旋转下 +Y(上)=布、+Z(屏幕外)=剪刀、+X(右)=石头。
-- 每条轴的两个面（正/背）是同一手势，所以只按轴映射、忽略正负号（读到的是绝对朝上轴）。
local AXIS_GESTURE = {
    { n = math.Vector3(1.0, 0.0, 0.0), gesture = "rock" },     -- 石头（右）
    { n = math.Vector3(0.0, 1.0, 0.0), gesture = "paper" },    -- 布（上）
    { n = math.Vector3(0.0, 0.0, 1.0), gesture = "scissors" }, -- 剪刀（屏幕外）
}
-- a 克制谁：石头>剪刀>布>石头。
local BEATS = { rock = "scissors", scissors = "paper", paper = "rock" }

local RpsService = Class("RpsService")

-- 部分 ai_command_* 在 AI 被 stop_ai() 关闭后不会生效（ActionLock/MovementSystem 的
-- Stop 模式都会调用 stop_ai，且解锁并不会自动 start_ai）。发指令前先确保 AI 是开着的。
---@param unit Unit|LifeEntity
local function ensure_ai(unit)
    if unit.start_ai then
        pcall(function() unit.start_ai() end)
    end
end

---@param config BabyStormConfig
---@param triggers TriggerRegistry
function RpsService:Ctor(config, triggers)
    self.cfg = config.rps
    self.triggers = triggers
    self.agents = nil
    self.dice = {}
    self.state = State.Idle
    self.agent = nil
    self.baby_die = nil
    self.baby_die_index = nil
    self.player_die = nil
    self.player_die_index = nil
    self.player_unit = nil
    self.player_candidate = nil
    self.role = nil
    self.holders = {}
    self.hold_elapsed = 0.0
    self.release_elapsed = 0.0
    self.baby_retry_elapsed = 0.0
    self.baby_missing_elapsed = 0.0
    self.wait_elapsed = 0.0
    self.face_target = nil
    -- 配对期间小步挪动（减少 AI 生硬感）的运行时字段。
    self.pairing_mobile = false
    self.fidget_anchor = nil
    self.fidget_timer = 0.0
    self.elapsed = 0.0
    self.flight = {}
    self.floor_y = nil
    -- 落地结算（轮询静止）+ 宝宝自动顶撞用的运行时字段。
    self.settle_elapsed = 0.0
    self.rest_frames = 0
    self.bonk_count = 0
    self.bonk_timer = 0.0
    self.pending_jump = nil
    -- 玩家超时未响应，宝宝抱着骰子闲逛用的运行时字段。
    self.giveup_elapsed = 0.0
    self.giveup_duration = 0.0
    self.giveup_move_timer = 0.0
end

---@param agents BabyAgent[]
---@return boolean
function RpsService:start(agents)
    if not (self.cfg and self.cfg.enabled) then
        return false
    end
    self.agents = agents
    for index = 1, #self.cfg.dice_names do
        local die = LuaAPI.query_unit(self.cfg.dice_names[index])
        if not die then
            Log.warn("rps missing die", self.cfg.dice_names[index])
            self.dice = {}
            return false
        end
        self.dice[index] = die
        pcall(function()
            if die.set_lifted_enabled then die.set_lifted_enabled(true) end
            -- 归零原生投掷力：原生抛掷是“沿朝向向前抛”，会把骰子甩向前方。
            -- 猜拳要的是“垂直于头顶抛起”，因此抛掷全程由脚本控位移（见 _drive_toss），
            -- 松手瞬间不产生任何向前的冲力。
            if die.set_custom_thrown_force then die.set_custom_thrown_force(0.0) end
            if die.set_custom_thrown_force_enabled then die.set_custom_thrown_force_enabled(true) end
        end)
        self:_register_die_events(die, index)
    end
    Log.info("rps ready", self.cfg.dice_names[1], self.cfg.dice_names[2])
    return true
end

---@param die Obstacle|Unit
---@param index integer
function RpsService:_register_die_events(die, index)
    -- 方法参数属于独立调用帧，避免循环变量被两个骰子的回调共同捕获。
    self.triggers:unit(die, { EVENT.SPEC_OBSTACLE_LIFTED_BEGIN }, function(_, _, data)
        self:_on_lift_begin(die, index, data)
    end)
    self.triggers:unit(die, { EVENT.SPEC_OBSTACLE_LIFTED_END }, function(_, _, data)
        self:_on_lift_end(die, index, data)
    end)
end

---@param dt Fixed
function RpsService:update(dt)
    if #self.dice ~= 2 then
        return
    end
    if self.state == State.Idle then
        self:_scan()
    elseif self.state == State.WaitPlayer then
        self:_update_wait_player(dt)
    elseif self.state == State.Ready then
        self:_update_ready(dt)
    elseif self.state == State.Tossing then
        self.elapsed = self.elapsed + dt
        self:_drive_toss()
    elseif self.state == State.Settling then
        self:_update_settle(dt)
    elseif self.state == State.GivingUp then
        self:_update_give_up(dt)
    end
end

function RpsService:_scan()
    if not self.agents then
        return
    end

    local radius_sq = self.cfg.trigger_radius * self.cfg.trigger_radius
    for index = 1, #self.agents do
        local agent = self.agents[index]
        local pos = agent and agent.unit and agent.unit.get_position and agent.unit.get_position() or nil
        if agent and not agent.destroyed
            and agent:is_in_state(agent.enum.BabyState.Idle)
            and agent.services.resolver:is_rps_need(agent.current_need)
            and pos
        then
            local nearest_index = nil
            local nearest_sq = nil
            for die_index = 1, #self.dice do
                local die = self.dice[die_index]
                local die_pos = die.get_position and die.get_position() or nil
                if die_pos and not self.holders[die_index] then
                    local dist_sq = UnitUtil.distance_xz_sq(pos, die_pos)
                    if dist_sq <= radius_sq and (not nearest_sq or dist_sq < nearest_sq) then
                        nearest_index = die_index
                        nearest_sq = dist_sq
                    end
                end
            end
            if nearest_index then
                self:_begin_session(agent, nearest_index)
                return
            end
        end
    end
end

---@param agent BabyAgent
---@param baby_die_index integer
function RpsService:_begin_session(agent, baby_die_index)
    self.agent = agent
    self.baby_die_index = baby_die_index
    self.player_die_index = baby_die_index == 1 and 2 or 1
    self.baby_die = self.dice[baby_die_index]
    self.player_die = self.dice[self.player_die_index]
    self.player_unit = nil
    self.player_candidate = nil
    self.role = nil
    self.hold_elapsed = 0.0
    self.release_elapsed = 0.0
    self.baby_retry_elapsed = 0.0
    self.baby_missing_elapsed = 0.0
    self.wait_elapsed = 0.0

    agent:cancel_need_countdown()
    agent:set_busy(true)
    agent:set_lift_enabled(false)
    agent.action_lock:acquire(LOCK)
    agent:invalidate_systems()
    agent:set_status("我举一个，你举另一个！")

    if agent.unit.lift_unit then
        pcall(function() agent.unit.lift_unit(self.baby_die) end)
    end
    self.state = State.WaitPlayer
    self.player_candidate = self.holders[self.player_die_index]
    Log.info("rps baby holding", agent.index)
end

---@param die Obstacle|Unit
---@param index integer
---@param data table|nil
function RpsService:_on_lift_begin(die, index, data)
    local lift_unit = data and data.lift_unit or nil
    self.holders[index] = lift_unit
    if self.state ~= State.WaitPlayer or die ~= self.player_die then
        return
    end
    if lift_unit and not UnitUtil.same_unit(lift_unit, self.agent and self.agent.unit) then
        self.player_candidate = lift_unit
        self.hold_elapsed = 0.0
    end
end

---@param dt Fixed
function RpsService:_update_wait_player(dt)
    local agent = self.agent
    local candidate = self.player_candidate or self.holders[self.player_die_index]
    if not agent then
        self:_abort()
        return
    end

    -- 基础交互（宝宝举起自己的骰子）已经满足需求；猜拳配对是额外加分项，不强制玩家参与。
    -- 玩家超时没有响应（一直没能一起举稳配对骰子），抱着骰子闲逛一会儿再按满足收尾。
    self.wait_elapsed = self.wait_elapsed + dt
    if self.wait_elapsed >= self.cfg.wait_player_timeout then
        self:_begin_give_up()
        return
    end

    -- “玩家进入配对范围”= 靠近宝宝 且 正举着配对骰子。只有这时才转视角看玩家 +
    -- 在其周围小步挪动（减少 AI 生硬感）。玩家还没走近、或已把骰子丢下 → 不锁视角、不刻意挪，
    -- 免得“玩家一举起/一丢下骰子，宝宝就隔着老远把头转过去还傻站着倒计时”的违和表现。
    local player_present = candidate
        and self:_unit_near_baby(candidate)
        and self:_unit_holds(candidate, self.player_die)
    if player_present then
        self:_set_face_target(candidate)
        self:_set_pairing_mobile(true)
        self:_drive_pairing_fidget(dt)
    else
        self:_set_face_target(nil)
        self:_set_pairing_mobile(false)
    end

    if not self:_unit_holds(agent.unit, self.baby_die) then
        self.hold_elapsed = 0.0
        self.baby_retry_elapsed = self.baby_retry_elapsed + dt
        if self.baby_retry_elapsed >= 0.5 and agent.unit.lift_unit then
            self.baby_retry_elapsed = 0.0
            pcall(function() agent.unit.lift_unit(self.baby_die) end)
        end
        return
    end
    self.baby_retry_elapsed = 0.0
    -- 两边必须都被引擎确认为“正在举着指定骰子且贴近”，连续稳定两拍才进入就绪。
    if not player_present then
        self.hold_elapsed = 0.0
        return
    end
    self.hold_elapsed = self.hold_elapsed + dt
    if self.hold_elapsed >= 0.2 then
        -- 配对达成：冻回原地（重新锁住，供就绪/抛骰阶段稳定判定），保持面向玩家。
        self:_set_pairing_mobile(false)
        self.player_unit = candidate
        self.role = RoleUtil.get_role_by_unit(candidate)
        self.release_elapsed = 0.0
        self.state = State.Ready
        agent:set_status("一起往头顶抛！")
        Log.info("rps both holding", agent.index)
    end
end

-- 进入/退出“配对小步挪动”模式（仅在玩家进入配对范围时开启，配对达成或玩家离开即关闭）。
-- 开启：释放移动锁（同 give_up/settle 做法，锁定期 AI 停、移速为 0 无法走位）、保持 busy、
--       move_mode=Stop 由本服务自行下发小步走位；以当前位置为锚点，只在小半径内游走。
-- 关闭：停下走位并重新锁住，冻回原地。
---@param mobile boolean
function RpsService:_set_pairing_mobile(mobile)
    if self.pairing_mobile == mobile then
        return
    end
    self.pairing_mobile = mobile
    local agent = self.agent
    if not (agent and not agent.destroyed) then
        return
    end
    if mobile then
        agent.action_lock:release(LOCK)
        agent.move_mode = Intent.MoveMode.Stop
        agent:invalidate_systems()
        local pos = agent.unit and agent.unit.get_position and agent.unit.get_position() or nil
        self.fidget_anchor = pos
        self.fidget_timer = 0.0 -- 立刻走第一步
    else
        if agent.unit and agent.unit.ai_command_stop_move then
            pcall(function() agent.unit.ai_command_stop_move(0.1) end)
        end
        agent.action_lock:acquire(LOCK)
        agent:invalidate_systems()
        self.fidget_anchor = nil
    end
end

-- 配对小步挪动：每隔 pairing_fidget_interval，以锚点为中心在 pairing_fidget_radius 半径内
-- 随机取一点走过去。半径很小，保证宝宝始终在玩家配对范围内、不会走开导致配对失败。
---@param dt Fixed
function RpsService:_drive_pairing_fidget(dt)
    if not (self.pairing_mobile and self.fidget_anchor) then
        return
    end
    local unit = self.agent and self.agent.unit or nil
    if not unit then
        return
    end
    self.fidget_timer = self.fidget_timer - dt
    if self.fidget_timer > 0.0 then
        return
    end
    self.fidget_timer = self.cfg.pairing_fidget_interval
    local radius = self.cfg.pairing_fidget_radius
    local target = math.Vector3(
        self.fidget_anchor.x + Rand.signed() * radius,
        self.fidget_anchor.y,
        self.fidget_anchor.z + Rand.signed() * radius
    )
    if unit.start_move_to_pos_with_threshold then
        ensure_ai(unit)
        pcall(function()
            unit.start_move_to_pos_with_threshold(target, 0.3, 0.5)
        end)
    end
end

---@param die Obstacle|Unit
---@param index integer
---@param data table|nil
function RpsService:_on_lift_end(die, index, data)
    self.holders[index] = nil
    if die == self.player_die then
        local lift_unit = data and data.lift_unit or nil
        if lift_unit and not self.player_candidate then
            self.player_candidate = lift_unit
        end
    end
end

---@param dt Fixed
function RpsService:_update_ready(dt)
    local agent = self.agent
    local player = self.player_unit
    if not (agent and player) then
        self:_abort()
        return
    end
    self:_set_face_target(player)
    if self:_unit_holds(agent.unit, self.baby_die) then
        self.baby_missing_elapsed = 0.0
    else
        self.baby_missing_elapsed = self.baby_missing_elapsed + dt
        if self.baby_missing_elapsed >= 0.5 then
            self:_reset_player_wait("我重新举好，你再来一次！")
        end
        return
    end
    if self:_unit_holds(player, self.player_die) then
        self.release_elapsed = 0.0
        return
    end
    -- 玩家必须先被确认举稳，再连续确认已经放手；不会再把“举起过程事件”误判成抛出。
    self.release_elapsed = self.release_elapsed + dt
    if self.release_elapsed < 0.2 then
        return
    end
    if not self:_unit_near_baby(player) then
        self:_reset_player_wait("靠近我再一起抛！")
        return
    end
    self:_begin_toss()
end

---@param text string
function RpsService:_reset_player_wait(text)
    self.state = State.WaitPlayer
    self.player_unit = nil
    self.player_candidate = nil
    self.role = nil
    self.hold_elapsed = 0.0
    self.release_elapsed = 0.0
    self.baby_retry_elapsed = 0.0
    self.baby_missing_elapsed = 0.0
    self.wait_elapsed = 0.0
    self.agent:set_status(text)
end

-- 玩家已经把自己那颗骰子松手（release 检测通过）。此处让宝宝也松手，随后脚本接管两颗骰子，
-- 各自“垂直于头顶”上抛（原生抛掷是向前抛，做不出垂直，所以整段位移由脚本控制）。
function RpsService:_begin_toss()
    local agent = self.agent
    if not (agent and agent.unit and self.player_unit) then
        self:_abort()
        return
    end
    -- 抛掷开始，宝宝要能自由转身/走位/跳跃，解除配对阶段的面向锁定。
    self:_set_face_target(nil)
    -- 宝宝松手（播放抛出动作）；力已归零，不会向前甩。ai_command_lift 和 jump/start_move
    -- 一样受 AI 开关影响——这里仍处于 action_lock 锁定期（AI 还没被重新打开），不先
    -- ensure_ai 的话这次松手会静默失效：骰子会一直挂在手上被引擎的举起吸附强制跟随，
    -- 视觉上看起来像是"抱着骰子跑"而不是被抛出去。
    if agent.unit.is_lift_status and agent.unit.is_lift_status() and agent.unit.ai_command_lift then
        ensure_ai(agent.unit)
        pcall(function() agent.unit.ai_command_lift() end)
    end
    -- 记录地面参考高度（宝宝当前站立处），用于落地判定：骰子必须真正落回地面附近，
    -- 而不是卡在角色头顶就被误判为“已落定”。
    local baby_pos = agent.unit.get_position and agent.unit.get_position() or nil
    self.floor_y = baby_pos and baby_pos.y or nil
    self.flight = {}
    self.elapsed = 0.0
    self:_prepare_die(self.baby_die_index)
    self:_prepare_die(self.player_die_index)
    self.state = State.Tossing
    agent:set_status("石头、剪刀、布！")
    Log.info("rps toss started", agent.index)
end

-- 准备一颗骰子的垂直上抛：从骰子被举着的当前位置，纯垂直升高 throw_height（x/z 完全不变，
-- 不依赖任何缓存的地面高度——骰子可能已经被抱着走动过，缓存的地面高度会对不上当前位置）。
-- 抛掷期间关闭物理，位移完全由 _drive_toss 控制；到达顶点后才交还物理，让它真正自由下落，
-- 这样才有一段可以被顶/被撞的空中时间，而不是刚交还物理就已经贴地。
---@param die_index integer
function RpsService:_prepare_die(die_index)
    local die = self.dice[die_index]
    local start_pos = die.get_position and die.get_position() or nil
    if not start_pos then
        return
    end
    self.flight[die_index] = {
        start_x = start_pos.x,
        start_y = start_pos.y,
        start_z = start_pos.z,
        peak_y = start_pos.y + self.cfg.throw_height,
    }
    pcall(function()
        if die.set_linear_velocity then die.set_linear_velocity(ZERO) end
        if die.set_angular_velocity then die.set_angular_velocity(ZERO) end
        if die.disable_gravity then die.disable_gravity() end
        if die.set_physics_active then die.set_physics_active(false) end
    end)
end

function RpsService:_drive_toss()
    local t = self.elapsed / self.cfg.throw_duration
    if t > 1.0 then t = 1.0 end
    -- 缓出（越接近顶点越慢），模拟真实上抛减速；x/z 全程等于起点，保证纯垂直。
    local ease = 1.0 - (1.0 - t) * (1.0 - t)
    for index = 1, #self.dice do
        local die = self.dice[index]
        local flight = self.flight[index]
        if flight then
            local pos = math.Vector3(
                flight.start_x,
                flight.start_y + (flight.peak_y - flight.start_y) * ease,
                flight.start_z
            )
            pcall(function()
                if die.set_position_smooth then die.set_position_smooth(pos) else die.set_position(pos) end
            end)
        end
    end
    if t >= 1.0 then
        self:_release_to_physics()
    end
end

-- 到达顶点后把两颗骰子交还物理引擎：恢复重力与碰撞，让其从高处真正自由下落——
-- 这段真实物理下落期间才能被顶/被撞，翻面也由真实碰撞产生，脚本不吸附朝向。
-- 随后进入 Settling：宝宝顶撞 + 轮询静止再结算。
function RpsService:_release_to_physics()
    for index = 1, #self.dice do
        local die = self.dice[index]
        local flight = self.flight[index]
        if flight then
            pcall(function()
                if die.set_linear_velocity then die.set_linear_velocity(ZERO) end
                if die.set_angular_velocity then die.set_angular_velocity(ZERO) end
                if die.set_physics_active then die.set_physics_active(true) end
                if die.enable_gravity then die.enable_gravity() end
            end)
        end
    end
    self:_begin_settle()
end

-- 进入结算阶段：放开宝宝的移动锁，让它能自己走两步 + 起跳顶骰子（模仿玩家跳起顶骰子的
-- 同一动作）；玩家侧不脚本化，玩家自己跳。两颗骰子都静止后才结算。
function RpsService:_begin_settle()
    local agent = self.agent
    if agent and not agent.destroyed then
        -- 干净地解锁（移除 BUFF_FORBID_MOVE、恢复 move_speed），让宝宝能位移和起跳。
        agent.action_lock:release(LOCK)
        -- 仍保持 busy（IdleState:update 会因 busy 早退，不会抢 move_mode），
        -- 仅把意图设为 Stop，避免 Wander 把移速压回 0 挡住顶撞用的走位。
        agent.move_mode = Intent.MoveMode.Stop
        agent:invalidate_systems()
    end
    self.settle_elapsed = 0.0
    self.rest_frames = 0
    self.bonk_count = 0
    self.bonk_timer = self.cfg.baby_bonk_first_delay
    self.pending_jump = nil
    self.state = State.Settling
    Log.info("rps settling begin")
end

---@param dt Fixed
function RpsService:_update_settle(dt)
    self.settle_elapsed = self.settle_elapsed + dt

    -- 宝宝自动顶撞：随玩家抛出一起跳顶，重复若干次后停手让骰子落地。
    self:_drive_baby_bonk(dt)

    -- 顶撞序列没跑完之前不进入静止判定：骰子两次顶撞之间可能短暂停住（速度/高度都达标），
    -- 若这时就开始计静止帧数，会在宝宝跳到一半时就被判定"已落定"提前结算，顶撞次数被腰斩。
    -- 必须等 bonk_count 打满且没有还在走位/待跳的动作，才允许轮询静止。
    local bonking_done = self.bonk_count >= self.cfg.baby_bonk_max and not self.pending_jump
    if bonking_done and self.settle_elapsed >= self.cfg.settle_min_time and self:_dice_at_rest() then
        self.rest_frames = self.rest_frames + 1
    else
        self.rest_frames = 0
    end

    if (bonking_done and self.rest_frames >= self.cfg.settle_rest_frames)
        or self.settle_elapsed >= self.cfg.settle_timeout
    then
        self:_finish_settle()
    end
end

-- 宝宝顶撞循环：随玩家抛出，第一下原地起跳直顶（骰子基本在头顶正上方）；
-- 之后每次都带随机横向偏移贴边斜顶，让骰子在空中翻滚，最多顶 baby_bonk_max 次。
---@param dt Fixed
function RpsService:_drive_baby_bonk(dt)
    local unit = self.agent and self.agent.unit or nil
    if not unit then
        return
    end
    -- 走位后延迟一拍再起跳，做出“先挪一点再顶”的手感。
    if self.pending_jump then
        self.pending_jump = self.pending_jump - dt
        if self.pending_jump <= 0.0 then
            self.pending_jump = nil
            if unit.ai_command_jump then
                ensure_ai(unit)
                pcall(function() unit.ai_command_jump() end)
            end
        end
    end

    if self.bonk_count >= self.cfg.baby_bonk_max then
        return
    end
    self.bonk_timer = self.bonk_timer - dt
    if self.bonk_timer > 0.0 then
        return
    end
    self.bonk_timer = self.cfg.baby_bonk_interval
    self.bonk_count = self.bonk_count + 1

    local dir = self:_baby_bonk_dir(unit, self.bonk_count >= 2)
    if dir and unit.ai_command_start_move then
        ensure_ai(unit)
        pcall(function() unit.ai_command_start_move(dir, self.cfg.baby_bonk_move_time) end)
        self.pending_jump = self.cfg.baby_bonk_move_time
    else
        -- 无需走位（骰子在正上方）：直接起跳直顶。
        self.pending_jump = nil
        if unit.ai_command_jump then
            ensure_ai(unit)
            pcall(function() unit.ai_command_jump() end)
        end
    end
end

-- 宝宝走位方向。非 randomize（第一次）：骰子基本在头顶正上方就返回 nil（原地直顶），
-- 否则朝骰子水平方向走。randomize（之后）：一定带随机横向偏移，贴边斜顶 → 空中翻滚。
---@param unit Unit
---@param randomize boolean
---@return Vector3|nil
function RpsService:_baby_bonk_dir(unit, randomize)
    local baby_pos = unit.get_position and unit.get_position() or nil
    if not baby_pos then
        return nil
    end
    local die_pos = self.baby_die and self.baby_die.get_position and self.baby_die.get_position() or nil
    local dx, dz, length = 0.0, 0.0, 0.0
    if die_pos then
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
function RpsService:_dice_at_rest()
    local eps = self.cfg.settle_rest_speed
    local tol = self.cfg.settle_ground_tolerance
    local arena = self.agent and self.agent.services and self.agent.services.arena or nil
    for index = 1, #self.dice do
        local die = self.dice[index]
        local v = die.get_linear_velocity and die.get_linear_velocity() or nil
        if not v then
            return false
        end
        local speed_sq = v.x * v.x + v.y * v.y + v.z * v.z
        if speed_sq > eps * eps then
            return false
        end
        local pos = die.get_position and die.get_position() or nil
        if not pos then
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
function RpsService:_ground_y_under(arena, pos)
    if arena and arena.ground_point then
        local ok, gp = pcall(function() return arena:ground_point(pos) end)
        if ok and gp and gp.y and gp.y ~= pos.y then
            return gp.y
        end
    end
    return self.floor_y or pos.y
end

-- 读某颗骰子静止后“朝上的完整面”对应的手势：把三条本地轴用骰子当前朝向(四元数)旋到世界坐标，
-- 取竖直分量绝对值最大的那条轴（背/正面同手势，符号无所谓）。该绝对值即“此面与竖直方向的余弦”，
-- 越接近 1 越平；低于 settle_face_up_tolerance 说明是棱/角立起（平地极罕见），判为没干净落面、返回 nil。
---@param die Obstacle|Unit|nil
---@return string|nil
function RpsService:_read_die_gesture(die)
    if not (die and die.get_orientation) then
        return nil
    end
    local ok, rot = pcall(function() return die.get_orientation() end)
    if not (ok and rot) then
        return nil
    end
    local best_abs, best_gesture = -1.0, nil
    for index = 1, #AXIS_GESTURE do
        local axis = AXIS_GESTURE[index]
        local wok, world_n = pcall(function() return rot:apply(axis.n) end)
        if wok and world_n then
            local up = world_n.y
            if up < 0.0 then up = -up end
            if up > best_abs then
                best_abs = up
                best_gesture = axis.gesture
            end
        end
    end
    if best_abs < self.cfg.settle_face_up_tolerance then
        return nil -- 棱/角着地，没有一个完整面朝上
    end
    return best_gesture
end

-- 落地判胜负（玩家视角）：两颗骰子都读到干净的朝上手势才判，否则返回 nil（本次不判胜负）。
---@return "win"|"draw"|"lose"|nil
function RpsService:_judge_outcome()
    local baby_gesture = self:_read_die_gesture(self.baby_die)
    local player_gesture = self:_read_die_gesture(self.player_die)
    if not (baby_gesture and player_gesture) then
        Log.info("rps outcome unresolved", tostring(baby_gesture), tostring(player_gesture))
        return nil
    end
    local result
    if player_gesture == baby_gesture then
        result = "draw"
    elseif BEATS[player_gesture] == baby_gesture then
        result = "win"
    else
        result = "lose"
    end
    Log.info("rps outcome", "player", player_gesture, "baby", baby_gesture, "=>", result)
    return result
end

-- 完整跑完了配对 + 抛骰 + 顶撞，两颗骰子落地静止：读朝上面判石头剪刀布胜负（玩家视角），
-- 基础满足分之外按 win/draw/lose 分档追加加分（没干净落面则 outcome=nil，只给基础满足分）。
function RpsService:_finish_settle()
    local agent = self.agent
    local role = self.role
    -- 必须在 _clear_session 清空 baby_die/player_die 引用之前读取朝向。
    local outcome = self:_judge_outcome()
    self:_release_agent()
    self:_clear_session()
    if agent and not agent.destroyed then
        agent:finish_rps(role, outcome)
    end
    Log.info("rps settle finished", tostring(outcome))
end

-- 玩家超时未响应：宝宝先抱着骰子闲逛 GivingUp 一会儿（_begin_give_up 里已经解了移动锁），
-- 逛够了才真正放下骰子、按满足收尾（本函数）。
-- 基础交互（宝宝举起自己的骰子）已足够满足需求；猜拳配对本身不强制玩家参与，只是额外加分项
-- （与顶球玩法同一设计：漏接/不参与也照常满足，只是拿不到额外加分）。
function RpsService:_finish_solo_satisfy()
    local agent = self.agent
    if agent and not agent.destroyed and agent.unit
        and agent.unit.is_lift_status and agent.unit.is_lift_status()
        and agent.unit.ai_command_lift
    then
        -- 保险起见仍 ensure_ai：万一 GivingUp 阶段被跳过直接调用到这里，
        -- action_lock 可能还锁着、AI 还是关的，不然这次松手会静默失效。
        ensure_ai(agent.unit)
        pcall(function() agent.unit.ai_command_lift() end)
    end
    self:_release_agent()
    self:_clear_session()
    if agent and not agent.destroyed then
        agent:finish_rps(nil, nil)
    end
    Log.info("rps solo satisfy (no player response)")
end

-- 玩家超时未响应：宝宝抱着骰子随意走动一会儿（模拟"找人玩"的感觉），逛够了再放下骰子收尾。
-- 解开移动锁（同 _begin_settle 的做法）但仍保持 busy + move_mode=Stop，走位由本服务直接
-- 下发 start_move_to_pos_with_threshold（同 MovementSystem 的走法），不经过 Wander
-- （Wander 按既有设计会把速度压成 0，宝宝几乎不动，这里明确要看到它真的在走）。
function RpsService:_begin_give_up()
    local agent = self.agent
    -- 配对小步挪动可能已释放过锁，这里直接清标记（不能走 _set_pairing_mobile(false)，
    -- 否则会重新锁住，与 give_up 需要的自由走动冲突）；随后 give_up 自行接管移动。
    self.pairing_mobile = false
    self.fidget_anchor = nil
    if agent and not agent.destroyed then
        self:_set_face_target(nil)
        agent.action_lock:release(LOCK)
        agent.move_mode = Intent.MoveMode.Stop
        agent:invalidate_systems()
        agent:set_status("没人理我，我自己溜达溜达…")
    end
    self.giveup_elapsed = 0.0
    self.giveup_duration = Rand.fixed(self.cfg.giveup_wander_min, self.cfg.giveup_wander_max)
    self.giveup_move_timer = 0.0 -- 立刻走第一步，不用等第一个 interval。
    self.state = State.GivingUp
    Log.info("rps giving up, wandering seconds", self.giveup_duration)
end

---@param dt Fixed
function RpsService:_update_give_up(dt)
    local agent = self.agent
    if not (agent and not agent.destroyed) then
        self:_abort()
        return
    end
    self.giveup_elapsed = self.giveup_elapsed + dt
    self:_drive_give_up_wander(dt)
    if self.giveup_elapsed >= self.giveup_duration then
        self:_finish_solo_satisfy()
    end
end

-- 每隔 giveup_move_interval 就近挑一个场地内的随机点走过去，做出闲逛的感觉。
---@param dt Fixed
function RpsService:_drive_give_up_wander(dt)
    local agent = self.agent
    local unit = agent and agent.unit or nil
    if not unit then
        return
    end
    self.giveup_move_timer = self.giveup_move_timer - dt
    if self.giveup_move_timer > 0.0 then
        return
    end
    self.giveup_move_timer = self.cfg.giveup_move_interval

    local target = agent.services.arena and agent.services.arena:random_point() or nil
    local current = unit.get_position and unit.get_position() or nil
    if target and current and unit.start_move_to_pos_with_threshold then
        local ground_target = math.Vector3(target.x, current.y, target.z)
        ensure_ai(unit)
        pcall(function()
            unit.start_move_to_pos_with_threshold(ground_target, agent.config.baby.patrol_threshold, 0.5)
        end)
    end
end

-- 配对等待期间让宝宝转头看向玩家（候选人变化才重新调用引擎接口，避免每帧重复）。
-- target 为 nil 时解除锁定。
---@param unit Unit|nil
function RpsService:_set_face_target(unit)
    local agent = self.agent
    if not (agent and agent.unit) then
        return
    end
    if self.face_target == unit then
        return
    end
    self.face_target = unit
    pcall(function()
        if unit then
            if agent.unit.start_face_lock_target then
                agent.unit.start_face_lock_target(unit)
            end
        elseif agent.unit.stop_face_lock_target then
            agent.unit.stop_face_lock_target()
        end
    end)
end

---@param unit Unit|nil
---@return boolean
function RpsService:_unit_near_baby(unit)
    local baby = self.agent and self.agent.unit or nil
    local baby_pos = baby and baby.get_position and baby.get_position() or nil
    local unit_pos = unit and unit.get_position and unit.get_position() or nil
    if not (baby_pos and unit_pos) then return false end
    local radius = self.cfg.trigger_radius
    return UnitUtil.distance_xz_sq(baby_pos, unit_pos) <= radius * radius
end

---@param unit LifeEntity|Unit|nil
---@param die Obstacle|Unit|nil
---@return boolean
function RpsService:_unit_holds(unit, die)
    if not (unit and die and unit.get_lifted_obstacle) then return false end
    local ok, held = pcall(function() return unit.get_lifted_obstacle() end)
    return ok and UnitUtil.same_unit(held, die) or false
end

function RpsService:_release_agent()
    local agent = self.agent
    if not (agent and not agent.destroyed) then return end
    self:_set_face_target(nil)
    agent.action_lock:release(LOCK)
    agent:set_busy(false)
    agent:set_lift_enabled(true)
    agent:invalidate_systems()
end

function RpsService:_clear_session()
    self.state = State.Idle
    self.agent = nil
    self.baby_die = nil
    self.baby_die_index = nil
    self.player_die = nil
    self.player_die_index = nil
    self.player_unit = nil
    self.player_candidate = nil
    self.role = nil
    self.holders = {}
    self.hold_elapsed = 0.0
    self.release_elapsed = 0.0
    self.baby_retry_elapsed = 0.0
    self.baby_missing_elapsed = 0.0
    self.wait_elapsed = 0.0
    self.face_target = nil
    self.pairing_mobile = false
    self.fidget_anchor = nil
    self.fidget_timer = 0.0
    self.elapsed = 0.0
    self.flight = {}
    self.floor_y = nil
    self.settle_elapsed = 0.0
    self.rest_frames = 0
    self.bonk_count = 0
    self.bonk_timer = 0.0
    self.pending_jump = nil
    self.giveup_elapsed = 0.0
    self.giveup_duration = 0.0
    self.giveup_move_timer = 0.0
end

function RpsService:_abort()
    self:_release_agent()
    self:_clear_session()
end

function RpsService:destroy()
    -- 抛掷期间可能关过物理，销毁时兜底恢复，避免骰子永久停在半空/不可交互。
    for index = 1, #self.dice do
        local die = self.dice[index]
        pcall(function()
            if die.set_physics_active then die.set_physics_active(true) end
            if die.enable_gravity then die.enable_gravity() end
        end)
    end
    self:_release_agent()
    self:_clear_session()
    self.dice = {}
    self.holders = {}
    self.agents = nil
    Log.info("rps destroyed")
end

return RpsService
