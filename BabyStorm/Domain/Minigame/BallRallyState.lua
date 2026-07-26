local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")
local FlightDriver = require("BabyStorm.Core.Drivers.FlightDriver")
local MathX = require("Util.MathX")
local Rand = require("Util.Rand")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

-- 顶球小游戏行为状态：发球 → 玩家顶回 → 回合循环 → 满回合庆祝，全流程一个状态内用 phase 推进。
-- 基础交互不强制玩家参与——漏接/超时同样按满足收尾，只是拿不到追加的顶球次数加分
-- （与猜拳玩法同一设计）。
--
-- phase: prepare -> holding -> wait_release -> to_player -> to_baby -> celebrate -> finishing
--                                    \-> to_player（回合循环，_resolve_baby_contact 里 holding 复用发球序列）
---@class BallRallyState: StateBase
---@field _prop BallProp|nil
---@field _ball Obstacle|Unit|nil
---@field _role Role|nil
---@field _player LifeEntity|Character|nil
local BallRallyState = Class("BabyBallRallyState", StateBase)

---@param agent BabyAgent
function BallRallyState:Ctor(agent)
    BallRallyState.super.Ctor(self, agent)
    -- 球的运动学飞行独立一个驱动实例（发球/回球共用，同一时刻只会有一段飞行在跑）。
    self._flight = FlightDriver.New()
end

---@param context BabyStateContext|{ ball_prop: BallProp, ball: any, role: Role, player: any }|nil
function BallRallyState:enter(context)
    BallRallyState.super.enter(self, context)
    local agent = self.agent
    self.cfg = agent.config.ball_rally

    local prop = context and context.ball_prop or nil
    self._prop = prop
    self._ball = context and context.ball or nil
    self._role = context and context.role or nil
    self._player = context and context.player or nil

    self._target = nil
    self._flight_duration = 0.0
    self._jump_window = 0.0
    self._prompt_shown = false
    self._indicator_sfx_id = nil
    self._player_hits = 0
    self._rally_max = Rand.int(self.cfg.rally_max_min, self.cfg.rally_max_max)

    agent:cancel_need_countdown()
    agent:set_lift_enabled(false)
    agent:set_status("和我顶球吧！")
    self:set_intent({ move_mode = Intent.MoveMode.Stop, anim_base = Intent.AnimBase.Idle, action_lock = true })

    prop:set_collision_with(self._ball, self._player, false)
    prop:set_collision_with(self._ball, agent.unit, false)
    prop:reconfigure(self._ball)

    self.phase = "prepare"
    Timer.once(self, self.cfg.initial_delay, function() self:_begin_hold() end)
    self:_show_tip("宝宝想玩顶球，接住它的球！", 2.0)
    Log.info("ball rally session started", "baby", agent.index)
end

---@param event table
function BallRallyState:handle_event(event)
    if not event then
        return
    end
    if event.type == "ball_lift_end" then
        if self.phase == "wait_release" and UnitUtil.same_unit(event.ball, self._ball) then
            self:_launch_to_player()
        end
    elseif event.type == "player_jump" then
        -- 玩家起跳只负责“开窗”；是否顶到由 FlightDriver 的逐帧轨迹回调判定。
        if self.phase == "to_player" and UnitUtil.same_unit(event.unit, self._player) then
            self._jump_window = self.cfg.jump_hit_window
            Log.info("ball rally player jump armed")
        end
    end
end

-- ============================================================
-- prepare -> holding：把球吸到宝宝头顶举起，短暂持球后再发出。
-- ============================================================

function BallRallyState:_begin_hold()
    local agent = self.agent
    local baby = agent.unit
    local baby_pos = baby.get_position()
    if not baby_pos then
        self:_settle("准备失败")
        return
    end

    self._prop:set_collision_with(self._ball, self._player, false)
    self._prop:set_collision_with(self._ball, baby, false)
    self._jump_window = 0.0
    self._prompt_shown = false
    self._target = nil
    self:_destroy_landing_indicator()

    self._prop:hold_at(self._ball, baby_pos + math.Vector3(0.0, self.cfg.serve_ball_height, 0.0))
    -- 宝宝把球举到头顶（可见的“举起接球/持球”姿势）；初次发球和每次回合都走这里，
    -- 因此玩家能稳定看到宝宝举球，而不是瞬间无动作回弹。球可能已被打飞出界销毁，保留 pcall。
    pcall(function() baby.lift_unit(self._ball) end)

    agent:set_status("接住宝宝顶过来的球！")
    self.phase = "holding"
    Timer.once(self, self.cfg.hold_seconds, function() self:_request_throw() end)
    Log.info("ball rally baby holding")
end

-- ============================================================
-- wait_release：宝宝松手发球，等待引擎确认放下（事件 + 两段兜底）。
-- ============================================================

function BallRallyState:_request_throw()
    local ball_pos = self._prop:position(self._ball)
    if not ball_pos then
        self:_settle("球丢失了")
        return
    end

    self._target = self:_choose_player_target()
    self._flight_duration = self:_choose_flight_time(
        ball_pos, self._target, self.cfg.flight_time_min, self.cfg.flight_time_max
    )
    self:_face_server_to(self._target)
    self:_show_landing_marker(true)
    self:_show_tip("去落点接住宝宝的球！", 1.8)

    self.phase = "wait_release"
    -- 宝宝松手（播放抛出动作）；perform 内部先 start_ai 再发指令，
    -- 不然处于 action_lock 锁定期（AI 还没被重新打开）时这条指令会静默失效。
    self.agent.movement:perform("release_lift")
    Timer.once(self, self.cfg.release_timeout, function() self:_release_retry() end)
    Log.info("ball rally throw requested", self._target.x, self._target.y, self._target.z)
end

-- 松手确认的两段兜底：第一次超时若球仍被举着，再举一次触发放下，并再等一个同样时长；
-- 第二次超时（举起系统未回调时的兜底）直接接管球的位置和速度发射。
function BallRallyState:_release_retry()
    if self.phase ~= "wait_release" then
        return -- 已经被 ball_lift_end 事件推进，幂等跳过
    end
    if not self._prop:is_free(self._ball) then
        -- 球可能已被打飞出界销毁，保留 pcall。
        pcall(function() self.agent.unit.lift_unit(self._ball) end)
        Timer.once(self, self.cfg.release_timeout, function() self:_launch_to_player() end)
    else
        self:_launch_to_player()
    end
end

-- ============================================================
-- to_player：球飞向落点，等玩家起跳顶回 / 漏接结算。
-- ============================================================

function BallRallyState:_launch_to_player()
    if self.phase ~= "wait_release" then
        return -- 事件与定时器兜底可能重复触发，幂等跳过
    end
    local start = self._prop:position(self._ball)
    if not (start and self._target) then
        self:_settle("发球失败")
        return
    end

    self._prop:set_collision_with(self._ball, self._player, false)
    self:_begin_flight(start)

    self.phase = "to_player"
    self._jump_window = 0.0
    self._prompt_shown = false
    Log.info(
        "ball rally launched to player",
        "time", self._flight_duration,
        "target", self._target.x, self._target.y, self._target.z
    )
end

---@param ball_pos Vector3
---@param flight_elapsed Fixed
---@param step_dt Fixed
function BallRallyState:_update_to_player_frame(ball_pos, flight_elapsed, step_dt)
    if self._jump_window > 0.0 then
        self._jump_window = self._jump_window - step_dt
        if self._jump_window < 0.0 then
            self._jump_window = 0.0
        end
    end

    local remaining = self._flight_duration - flight_elapsed
    if not self._prompt_shown and remaining <= self.cfg.jump_prompt_lead then
        self._prompt_shown = true
        self:_show_tip("跳！顶球！", 1.0)
        Log.info("ball rally jump prompt")
    end

    if self:_ball_out_of_bounds(ball_pos) then
        self:_settle("球出界，本轮结束")
        return
    end

    -- 球落入落点盒 + 玩家处于起跳窗口 → 顶回宝宝（容错优先于物理精确）。
    self:_try_player_volley(ball_pos)
end

---@param ball_pos Vector3|nil
---@return boolean true 表示已顶回，调用方应立即 return
function BallRallyState:_try_player_volley(ball_pos)
    if self._jump_window <= 0.0 or not self._target then
        return false
    end
    ball_pos = ball_pos or self._prop:position(self._ball)
    if not ball_pos then
        return false
    end
    local cfg = self.cfg
    -- 必须等球下落进入盒子高度，避免发球/上升途中误判。
    if ball_pos.y > cfg.floor_y + cfg.player_catch_height then
        return false
    end
    local box = cfg.player_catch_radius
    if not self:_xz_within(ball_pos, self._target, box) then
        return false
    end
    -- 玩家要站在落点盒附近（带余量），保留“跑到落点接球”的玩法。玩家可能断线读不到位置，
    -- 读不到时不阻塞（沿用原语义）。
    local pok, player_pos = pcall(function() return self._player.get_position() end)
    if pok and player_pos and not self:_xz_within(player_pos, self._target, box + cfg.player_box_margin) then
        return false
    end
    Log.info("ball rally player volley", self._player_hits)
    self:_launch_to_baby()
    return true
end

---@param a Vector3
---@param b Vector3
---@param radius Fixed
---@return boolean
function BallRallyState:_xz_within(a, b, radius)
    local dx = a.x - b.x
    local dz = a.z - b.z
    return dx * dx + dz * dz <= radius * radius
end

---@param pos Vector3|nil
---@return boolean
function BallRallyState:_ball_out_of_bounds(pos)
    pos = pos or self._prop:position(self._ball)
    if not pos then
        return true
    end
    local cfg = self.cfg
    local tolerance = cfg.boundary_tolerance or 0.0
    return pos.x < cfg.min_x - tolerance
        or pos.x > cfg.max_x + tolerance
        or pos.z < cfg.min_z - tolerance
        or pos.z > cfg.max_z + tolerance
        or pos.y < cfg.floor_y - 2.0
end

-- ============================================================
-- to_baby：球飞回宝宝，接住后回合上限判定。
-- ============================================================

function BallRallyState:_launch_to_baby()
    local start = self._prop:position(self._ball)
    local baby_pos = self.agent.unit.get_position()
    if not (start and baby_pos) then
        self:_settle("回球失败")
        return
    end

    local cfg = self.cfg
    local target = math.Vector3(
        MathX.clamp(baby_pos.x, cfg.min_x, cfg.max_x),
        baby_pos.y + cfg.catch_height,
        MathX.clamp(baby_pos.z, cfg.min_z, cfg.max_z)
    )
    self._target = target
    self._player_hits = self._player_hits + 1
    self._flight_duration = self:_choose_flight_time(start, target, cfg.return_time_min, cfg.return_time_max)
    self:_destroy_landing_indicator()
    self._prop:set_collision_with(self._ball, self._player, false)
    self:_begin_flight(start)

    self.phase = "to_baby"
    self._jump_window = 0.0
    self.agent:set_status("第 " .. tostring(self._player_hits) .. " 次，球来啦！")
    self:_show_tip("顶到了！x" .. tostring(self._player_hits), 1.0)
    Log.info(
        "ball rally returned to baby",
        self._player_hits,
        "time", self._flight_duration,
        "target", target.x, target.y, target.z
    )
end

---@param ball_pos Vector3
function BallRallyState:_update_to_baby_frame(ball_pos)
    if self:_ball_out_of_bounds(ball_pos) then
        self:_settle("回球出界，本轮结束")
        return
    end

    local baby_pos = self.agent.unit.get_position()
    if not (ball_pos and baby_pos) then
        self:_settle("接球失败，本轮结束")
    end
end

-- FlightDriver 是沙滩球飞行期间的唯一时钟。轨迹位置与玩法传感在同一个 frame 回调中推进，
-- 不再让 0.1s 的行为 tick 用另一份 elapsed 抢先结束飞行。
---@param ball_pos Vector3
---@param flight_elapsed Fixed
---@param progress Fixed
---@param step_dt Fixed
function BallRallyState:_on_flight_step(ball_pos, flight_elapsed, progress, step_dt)
    if self.phase == "to_player" then
        self:_update_to_player_frame(ball_pos, flight_elapsed, step_dt)
    elseif self.phase == "to_baby" then
        self:_update_to_baby_frame(ball_pos)
    end
end

-- 只有 FlightDriver 的 frame 进度真正到达 1.0，才允许结束本段轨迹。
function BallRallyState:_on_flight_complete()
    if self.phase == "to_player" then
        self:_settle("没顶到，本轮结束！")
    elseif self.phase == "to_baby" then
        self:_resolve_baby_contact()
    end
end

-- 球回到宝宝：达到本局回合上限 → 宝宝举球庆祝收尾；否则把球接到头顶（可见举起）再发回玩家。
function BallRallyState:_resolve_baby_contact()
    if self._player_hits >= self._rally_max then
        self:_begin_celebrate()
        return
    end
    -- 复用发球序列：_begin_hold 把球吸到宝宝头顶 lift_unit（可见的“举起接球”）→ 短暂持球 →
    -- _request_throw 再发出。不再瞬间运动学回弹，从而玩家能稳定看到宝宝举球接球的动作。
    self:_begin_hold()
end

-- ============================================================
-- celebrate：顶满收尾，宝宝举球庆祝若干秒后落球结算。
-- ============================================================

function BallRallyState:_begin_celebrate()
    local agent = self.agent
    local baby = agent.unit
    local baby_pos = baby.get_position()
    if not baby_pos then
        self:_settle("完成！顶了 " .. tostring(self._player_hits) .. " 次")
        return
    end

    self:_destroy_landing_indicator()
    self._prop:hold_at(self._ball, baby_pos + math.Vector3(0.0, self.cfg.serve_ball_height, 0.0))
    -- 球可能已被打飞出界销毁，保留 pcall。
    pcall(function() baby.lift_unit(self._ball) end)

    agent:set_status("顶满啦！举高高～")
    self:_show_tip("完成！宝宝举起球啦～", 1.5)
    self.phase = "celebrate"
    Timer.once(self, self.cfg.celebrate_hold_seconds, function()
        self:_settle("完成！顶了 " .. tostring(self._player_hits) .. " 次")
    end)
    Log.info("ball rally celebrate", self._player_hits)
end

-- ============================================================
-- 共享：运动学飞行 / 落点选择 / 落点标记 / 提示 / 收尾。
-- ============================================================

-- 开始一段运动学飞行：弧高随本次水平投掷距离缩放（远→高、近→低，看起来更自然）。
-- 位移、传感和完成判定全部共享 FlightDriver 的逐帧时钟；逐帧轨迹直接 set_position，
-- 不再每帧重启 set_position_smooth 的内部插值。
---@param start_pos Vector3
function BallRallyState:_begin_flight(start_pos)
    local cfg = self.cfg
    local target = self._target
    local arc_peak = 0.0
    if target then
        local dx = target.x - start_pos.x
        local dz = target.z - start_pos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        arc_peak = MathX.clamp(cfg.arc_height_ratio * dist, cfg.arc_peak_min, cfg.arc_peak_max)
    end
    self._prop:prepare_flight(self._ball, start_pos)
    self._flight:start({
        unit = self._ball,
        from = start_pos,
        to = target,
        duration = self._flight_duration,
        arc_peak = arc_peak,
        hang = cfg.flight_hang,
        ease = "out_in",
        frames = 1,
        position_mode = "direct",
        on_step = function(pos, elapsed, progress, dt)
            self:_on_flight_step(pos, elapsed, progress, dt)
        end,
        on_complete = function()
            self:_on_flight_complete()
        end,
    })
end

---@return Vector3
function BallRallyState:_choose_player_target()
    local cfg = self.cfg
    -- 玩家可能断线读不到位置，读不到时回退到场地中心（沿用原语义）。
    local pok, player_pos = pcall(function() return self._player.get_position() end)
    if not (pok and player_pos) then
        player_pos = math.Vector3(
            (cfg.min_x + cfg.max_x) * 0.5,
            cfg.floor_y,
            (cfg.min_z + cfg.max_z) * 0.5
        )
    end

    local dx = Rand.fixed(-1.0, 1.0)
    local dz = Rand.fixed(-1.0, 1.0)
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 0.1 then
        dx = 1.0
        dz = 0.0
        length = 1.0
    end
    local distance = Rand.fixed(cfg.target_jitter_min, cfg.target_jitter_max)
    dx = dx / length * distance
    dz = dz / length * distance

    local y = cfg.floor_y + cfg.ball_ground_origin_offset
    local target = math.Vector3(
        MathX.clamp(player_pos.x + dx, cfg.min_x, cfg.max_x),
        y,
        MathX.clamp(player_pos.z + dz, cfg.min_z, cfg.max_z)
    )
    return self:_enforce_min_throw(target, y)
end

-- 落点离发球宝宝太近时投球会显得很怪：沿“宝宝→落点”方向把落点推到最小水平距离之外，再夹回场地。
---@param target Vector3
---@param y Fixed
---@return Vector3
function BallRallyState:_enforce_min_throw(target, y)
    local cfg = self.cfg
    local baby_pos = self.agent.unit.get_position()
    local min_d = cfg.min_throw_distance
    if not (baby_pos and min_d and min_d > 0.0) then
        return target
    end
    local tdx = target.x - baby_pos.x
    local tdz = target.z - baby_pos.z
    local d = math.sqrt(tdx * tdx + tdz * tdz)
    if d >= min_d then
        return target
    end
    if d < 0.1 then
        tdx, tdz, d = 1.0, 0.0, 1.0
    end
    return math.Vector3(
        MathX.clamp(baby_pos.x + tdx / d * min_d, cfg.min_x, cfg.max_x),
        y,
        MathX.clamp(baby_pos.z + tdz / d * min_d, cfg.min_z, cfg.max_z)
    )
end

---@param start_pos Vector3
---@param target_pos Vector3
---@param min_time Fixed
---@param max_time Fixed
---@return Fixed
function BallRallyState:_choose_flight_time(start_pos, target_pos, min_time, max_time)
    local cfg = self.cfg
    local dx = target_pos.x - start_pos.x
    local dz = target_pos.z - start_pos.z
    local horizontal_distance = math.sqrt(dx * dx + dz * dz)
    local minimum_for_speed = horizontal_distance / cfg.max_horizontal_speed
    local flight_time = Rand.fixed(min_time, max_time)
    if flight_time < minimum_for_speed then
        flight_time = minimum_for_speed
    end
    if flight_time < 0.5 then
        flight_time = 0.5
    end
    return flight_time
end

---@param target Vector3
function BallRallyState:_face_server_to(target)
    local baby = self.agent.unit
    local pos = baby.get_position()
    if not pos then
        return
    end
    local direction = math.Vector3(target.x - pos.x, 0.0, target.z - pos.z)
    if direction.x * direction.x + direction.z * direction.z > 0.01 then
        baby.set_direction(direction)
    end
end

---@param first boolean
function BallRallyState:_show_landing_marker(first)
    if not self._target then
        return
    end
    local cfg = self.cfg
    local y = cfg.floor_y + 1.0
    local target = self._target
    local marker_pos = math.Vector3(target.x, y, target.z)

    if first then
        self:_destroy_landing_indicator()
        -- sfx API 失败不该打断顶球流程，仅作落点预警用途，pcall 兜底。
        local ok, sfx_id = pcall(function()
            return GameAPI.play_sfx_by_key(
                cfg.indicator_sfx_key,
                marker_pos,
                math.Quaternion(0.0, 0.0, 0.0),
                cfg.indicator_sfx_scale,
                self._flight_duration + 1.0,
                1.0,
                false
            )
        end)
        if ok then
            self._indicator_sfx_id = sfx_id
        end
    elseif self._indicator_sfx_id then
        -- 同上，sfx 表现兜底。
        pcall(function()
            GlobalAPI.set_sfx_position(self._indicator_sfx_id, marker_pos)
        end)
    end
end

function BallRallyState:_destroy_landing_indicator()
    if self._indicator_sfx_id then
        -- 同上，sfx 表现兜底。
        pcall(function()
            GlobalAPI.destroy_sfx(self._indicator_sfx_id, true)
        end)
    end
    self._indicator_sfx_id = nil
end

---@param content string
---@param duration Fixed
function BallRallyState:_show_tip(content, duration)
    -- role 可能对应已断线的玩家，保留 pcall。
    if self._role then
        pcall(function() self._role.show_tips(content, duration) end)
    else
        pcall(function() GlobalAPI.show_tips(content, duration) end)
    end
end

-- 一局顶球收尾：算满足该需求，按已成功顶球次数追加奖励，归还宝宝控制权并回到空转扫描。
---@param reason string
function BallRallyState:_settle(reason)
    local agent = self.agent
    local catches = self._player_hits
    Log.info("ball rally settle", reason, "catches", catches)
    self:_show_tip(reason, 1.5)
    self:_destroy_landing_indicator()
    self._flight:stop()

    -- 恢复实体碰撞，避免下一局开局前玩家穿过球/宝宝。
    self._prop:set_collision_with(self._ball, self._player, true)
    self._prop:set_collision_with(self._ball, agent.unit, true)

    local ball_was_held = agent.unit.is_lift_status()
    if ball_was_held then
        -- 手里有球时 perform("release_lift") 即放下（ai_command_lift 是举起/放下切换）。
        agent.movement:perform("release_lift")
    end
    self._prop:settle(self._ball, ball_was_held)

    if ball_was_held then
        -- 引擎坑位：invalidate 是「立即对齐」，若同帧就切状态触发 exit -> Stop，
        -- stop_ai 会把刚发出的放球指令一并作废——松手后隔一拍再收尾
        -- （对照 PlayRpsState._finish_solo_satisfy 的同一个坑）。
        self.phase = "finishing"
        Timer.once(self, 0.1, function()
            agent:finish_ball_rally(self._role, catches)
        end)
        return
    end
    agent:finish_ball_rally(self._role, catches)
end

---@param context BabyStateContext|nil
function BallRallyState:exit(context)
    local agent = self.agent
    self._flight:stop()
    self:_destroy_landing_indicator()
    self._prop:set_collision_with(self._ball, self._player, true)
    self._prop:set_collision_with(self._ball, agent.unit, true)
    -- 抛掷/接球/庆祝中途被打断（抱走/切状态）的兜底：确保球不会永久卡在无重力状态，幂等。
    if self._ball then
        self._prop:settle(self._ball, false)
    end
    agent:set_lift_enabled(true)
    BallRallyState.super.exit(self, context)
end

return BallRallyState
