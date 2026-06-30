local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

local State = {
    Disabled = "disabled", -- 空转/扫描：等待某个宝宝持「玩沙滩球」需求且球可用即开局
    Prepare = "prepare",
    Holding = "holding",
    WaitRelease = "wait_release",
    ToPlayer = "to_player",
    ToBaby = "to_baby",
    Celebrate = "celebrate", -- 顶满收尾：宝宝把球举起庆祝若干秒后落球结算
}

---@class BallRallyService
---@field config BabyStormConfig
---@field cfg BabyBallRallyConfig
---@field triggers TriggerRegistry
---@field sessions PlayerSessionRegistry|nil
---@field agents BabyAgent[]|nil
---@field ball Obstacle|Unit|nil
---@field server BabyAgent|nil
---@field role Role|nil
---@field player LifeEntity|Character|nil
---@field state string
---@field state_elapsed Fixed
---@field flight_duration Fixed
---@field flight_arc_peak Fixed
---@field target Vector3|nil
---@field jump_window Fixed
---@field prompt_shown boolean
---@field release_attempted boolean
---@field pending_launch boolean
---@field launch_pos Vector3|nil
---@field indicator_sfx_id SfxID|nil
---@field rally_max integer
---@field player_hits integer
---@field _events_registered boolean
local BallRallyService = Class("BallRallyService")

local ZERO = math.Vector3(0.0, 0.0, 0.0)
local RALLY_LOCK = "ball_rally"

---@param value Fixed
---@param min_value Fixed
---@param max_value Fixed
---@return Fixed
local function clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

---@param a Fixed
---@param b Fixed
---@param t Fixed
---@return Fixed
local function lerp(a, b, t)
    return a + (b - a) * t
end

-- 飞行进度缓动：两端快、中间慢（ease-out-in，顶点自带悬停感）。
-- hang ∈ [0,1] 控制中段变慢程度：0=匀速，1=顶点近乎悬停。
---@param s Fixed 线性进度 [0,1]
---@param hang Fixed|nil
---@return Fixed
local function ease_out_in(s, hang)
    local shaped
    if s < 0.5 then
        shaped = s * (2.0 - 2.0 * s)       -- 前半段 ease-out：起手快
    else
        local k = 2.0 * s - 1.0
        shaped = 0.5 + 0.5 * k * k          -- 后半段 ease-in：落地快
    end
    return s + (shaped - s) * (hang or 0.0)
end

---@param min_value Fixed
---@param max_value Fixed
---@return Fixed
local function random_fixed(min_value, max_value)
    local raw
    if GameAPI and GameAPI.random_int then
        raw = GameAPI.random_int(0, 10000)
    else
        raw = LuaAPI.rand and LuaAPI.rand() or 0
        if raw < 0 then
            raw = -raw
        end
        raw = raw % 10001
    end
    return min_value + (max_value - min_value) * (raw / 10000.0)
end

---@param config BabyStormConfig
---@param triggers TriggerRegistry
---@param sessions PlayerSessionRegistry|nil
function BallRallyService:Ctor(config, triggers, sessions)
    self.config = config
    self.cfg = config.ball_rally
    self.triggers = triggers
    self.sessions = sessions
    self.agents = nil
    self.ball = nil
    self.server = nil
    self.role = nil
    self.player = nil
    self.state = State.Disabled
    self.state_elapsed = 0.0
    self.flight_duration = 0.0
    self.flight_arc_peak = 0.0
    self.target = nil
    self.jump_window = 0.0
    self.prompt_shown = false
    self.release_attempted = false
    self.pending_launch = false
    self.launch_pos = nil
    self.indicator_sfx_id = nil
    self.rally_max = 0
    self.player_hits = 0
    self._events_registered = false
end

-- 由 manager 启动时调用一次：仅做一次性准备（解析球/玩家、配置球、注册事件），
-- 不立即接管任何宝宝。真正的开局由 update 扫描到「持顶球需求的空闲宝宝」后触发。
---@param agents BabyAgent[]
---@return boolean
function BallRallyService:start(agents)
    local cfg = self.cfg
    if not (cfg and cfg.enabled) then
        return false
    end

    self.agents = agents
    self.ball = LuaAPI.query_unit(cfg.ball_name)
    self.role, self.player = self:_first_player()

    if not self.ball then
        Log.warn("ball rally missing ball", cfg.ball_name)
        return false
    end

    self:_configure_ball()
    self:_register_events()

    self.state = State.Disabled
    Log.info("ball rally ready (need-driven)", cfg.ball_name)
    return true
end

---@return Role|nil, LifeEntity|Character|nil
function BallRallyService:_first_player()
    local selected_role = nil
    if self.sessions then
        self.sessions:for_each(function(session)
            if not selected_role then
                selected_role = session.role
            end
        end)
    end

    if not selected_role then
        local roles = GameAPI.get_all_valid_roles() or {}
        selected_role = roles[1]
    end
    local player = selected_role and selected_role.get_ctrl_unit and selected_role.get_ctrl_unit() or nil
    return selected_role, player
end

function BallRallyService:_configure_ball()
    local ball = self.ball
    if not ball then
        return
    end
    if ball.set_lifted_enabled then
        pcall(function() ball.set_lifted_enabled(true) end)
    end
    if ball.set_physics_active then
        pcall(function() ball.set_physics_active(true) end)
    end
    -- 运动学驱动：全程关闭引擎重力，轨迹完全由 _drive_ball_kinematic 控制。
    if ball.disable_gravity then
        pcall(function() ball.disable_gravity() end)
    end
    if ball.enable_unit_ccd then
        pcall(function() ball.enable_unit_ccd() end)
    end
end

-- 球/玩家事件只注册一次（幂等）：球被举起触发发球、玩家起跳开顶球窗口。
function BallRallyService:_register_events()
    if self._events_registered then
        return
    end
    if not (self.ball and self.player) then
        return
    end
    self._events_registered = true

    self.triggers:unit(self.ball, { EVENT.SPEC_OBSTACLE_LIFTED_END }, function()
        if self.state == State.WaitRelease then
            self.pending_launch = true
        end
    end)

    -- 玩家起跳只负责“开窗”；是否顶到由落点盒判定（见 _try_player_volley），
    -- 不再依赖球与玩家的物理碰撞，避免落点漂移导致接不到。
    self.triggers:unit(self.player, { EVENT.SPEC_LIFEENTITY_JUMP }, function()
        if self.state == State.ToPlayer then
            self.jump_window = self.cfg.jump_hit_window
            Log.info("ball rally player jump armed")
        end
    end)
end

---@param unit Unit|LifeEntity|nil
---@param enabled boolean
function BallRallyService:_set_collision(unit, enabled)
    if self.ball and unit and GameAPI.enable_collision_between_units then
        pcall(function()
            GameAPI.enable_collision_between_units(self.ball, unit, enabled)
        end)
    end
end

---@param content string
---@param duration Fixed
function BallRallyService:_show_tip(content, duration)
    if self.role and self.role.show_tips then
        pcall(function() self.role.show_tips(content, duration) end)
    elseif GlobalAPI and GlobalAPI.show_tips then
        pcall(function() GlobalAPI.show_tips(content, duration) end)
    end
end

---@param dt Fixed
function BallRallyService:update(dt)
    if self.state == State.Disabled then
        self:_scan_for_session()
        return
    end

    if self.jump_window > 0.0 then
        self.jump_window = self.jump_window - dt
        if self.jump_window < 0.0 then
            self.jump_window = 0.0
        end
    end

    self.state_elapsed = self.state_elapsed + dt

    if self.state == State.Prepare then
        if self.state_elapsed >= 0.0 then
            self:_begin_hold()
        end
    elseif self.state == State.Holding then
        if self.state_elapsed >= self.cfg.hold_seconds then
            self:_request_throw()
        end
    elseif self.state == State.WaitRelease then
        self:_update_wait_release()
    elseif self.state == State.ToPlayer then
        self:_update_to_player(dt)
    elseif self.state == State.ToBaby then
        self:_update_to_baby(dt)
    elseif self.state == State.Celebrate then
        self:_update_celebrate()
    end
end

-- 空转时扫描：找到一个「正空闲且持玩沙滩球需求」的宝宝，且自由静止的球在其触发半径内，即开局。
function BallRallyService:_scan_for_session()
    if not (self.ball and self.agents) then
        return
    end
    -- 球被举着（玩家/宝宝手里）时不抢，只接管自由静止的球。
    if self.ball.is_lifted_status then
        local ok, lifted = pcall(function() return self.ball.is_lifted_status() end)
        if ok and lifted then
            return
        end
    end
    local ball_pos = self.ball.get_position and self.ball.get_position() or nil
    if not ball_pos then
        return
    end

    local agent = self:_find_ball_need_agent(ball_pos)
    if agent then
        self:_begin_session(agent)
    end
end

---@param ball_pos Vector3
---@return BabyAgent|nil
function BallRallyService:_find_ball_need_agent(ball_pos)
    local radius = self.cfg.trigger_radius or 0.0
    local radius_sq = radius * radius
    local agents = self.agents
    for index = 1, #agents do
        local agent = agents[index]
        if agent and not agent.destroyed
            and agent:is_in_state(agent.enum.BabyState.Idle)
            and agent.services.resolver:is_ball_rally_need(agent.current_need)
        then
            local pos = agent.unit and agent.unit.get_position and agent.unit.get_position() or nil
            if pos then
                local dx = pos.x - ball_pos.x
                local dz = pos.z - ball_pos.z
                if dx * dx + dz * dz <= radius_sq then
                    return agent
                end
            end
        end
    end
    return nil
end

-- 接管指定宝宝，开始一局顶球（一次性会话；漏接即在 _settle_session 收尾）。
---@param agent BabyAgent
function BallRallyService:_begin_session(agent)
    if not (agent and agent.unit and self.ball) then
        return
    end
    if not (self.role and self.player) then
        self.role, self.player = self:_first_player()
        self:_register_events()
    end
    if not (self.role and self.player) then
        Log.warn("ball rally session aborted: no player")
        return
    end

    self.server = agent
    self.player_hits = 0
    if GameAPI and GameAPI.random_int then
        self.rally_max = GameAPI.random_int(self.cfg.rally_max_min, self.cfg.rally_max_max)
    else
        self.rally_max = self.cfg.rally_max_min
    end
    self.release_attempted = false
    self.pending_launch = false

    agent:cancel_need_countdown()
    agent:set_busy(true)
    agent:set_lift_enabled(false)
    agent:set_status("和我顶球吧！")
    agent.action_lock:acquire(RALLY_LOCK)
    agent:invalidate_systems()

    self:_set_collision(self.player, false)
    self:_set_collision(agent.unit, false)
    self:_configure_ball()

    self.state = State.Prepare
    self.state_elapsed = -(self.cfg.initial_delay or 1.0)
    self:_show_tip("宝宝想玩顶球，接住它的球！", 2.0)
    Log.info("ball rally session started", "baby", agent.index)
end

function BallRallyService:_begin_hold()
    local baby = self.server and self.server.unit or nil
    local baby_pos = baby and baby.get_position and baby.get_position() or nil
    if not (baby and baby_pos and self.ball) then
        self:_settle_session("准备失败")
        return
    end

    self:_set_collision(self.player, false)
    self:_set_collision(baby, false)
    self.jump_window = 0.0
    self.pending_launch = false
    self.prompt_shown = false
    self.target = nil
    self:_destroy_landing_indicator()

    pcall(function()
        if self.ball.set_linear_velocity then
            self.ball.set_linear_velocity(ZERO)
        end
        if self.ball.set_angular_velocity then
            self.ball.set_angular_velocity(ZERO)
        end
        if self.ball.set_physics_active then
            self.ball.set_physics_active(true)
        end
        if self.ball.disable_gravity then
            self.ball.disable_gravity()
        end
        if self.ball.set_position then
            self.ball.set_position(baby_pos + math.Vector3(0.0, self.cfg.serve_ball_height, 0.0))
        end
    end)

    -- 宝宝把球举到头顶（可见的“举起接球/持球”姿势）；初次发球和每次回合都走这里，
    -- 因此玩家能稳定看到宝宝举球，而不是瞬间无动作回弹。
    if baby.lift_unit then
        pcall(function() baby.lift_unit(self.ball) end)
    end

    self.server:set_status("接住宝宝顶过来的球！")
    self.state = State.Holding
    self.state_elapsed = 0.0
    Log.info("ball rally baby holding")
end

function BallRallyService:_request_throw()
    local ball_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    if not ball_pos then
        self:_settle_session("球丢失了")
        return
    end

    self.target = self:_choose_player_target()
    self.flight_duration = self:_choose_flight_time(
        ball_pos,
        self.target,
        self.cfg.flight_time_min,
        self.cfg.flight_time_max
    )
    self:_face_server_to(self.target)
    self:_show_landing_marker(true)
    self:_show_tip("去落点接住宝宝的球！", 1.8)

    self.state = State.WaitRelease
    self.state_elapsed = 0.0
    self.release_attempted = false
    self.pending_launch = false

    local baby = self.server.unit
    if baby.ai_command_lift then
        pcall(function() baby.ai_command_lift() end)
    elseif baby.lift_unit then
        pcall(function() baby.lift_unit(self.ball) end)
    else
        self.pending_launch = true
    end
    Log.info("ball rally throw requested", self.target.x, self.target.y, self.target.z)
end

function BallRallyService:_update_wait_release()
    if self.pending_launch then
        self.pending_launch = false
        self:_launch_to_player()
        return
    end
    if self.state_elapsed < self.cfg.release_timeout then
        return
    end

    if not self.release_attempted then
        self.release_attempted = true
        self.state_elapsed = 0.0
        local lifted = false
        if self.ball.is_lifted_status then
            local ok, value = pcall(function() return self.ball.is_lifted_status() end)
            lifted = ok and value or false
        end
        if lifted and self.server.unit.lift_unit then
            pcall(function() self.server.unit.lift_unit(self.ball) end)
        else
            self.pending_launch = true
        end
        return
    end

    -- 举起系统未回调时的兜底：下一拍直接接管球的位置和速度。
    self.pending_launch = true
end

function BallRallyService:_launch_to_player()
    local start_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    if not (start_pos and self.target) then
        self:_settle_session("发球失败")
        return
    end

    self:_begin_kinematic_flight(start_pos)
    self:_set_collision(self.player, false)

    self.state = State.ToPlayer
    self.state_elapsed = 0.0
    self.jump_window = 0.0
    self.prompt_shown = false
    Log.info(
        "ball rally launched to player",
        "time", self.flight_duration,
        "target", self.target.x, self.target.y, self.target.z
    )
end

---@param dt Fixed
function BallRallyService:_update_to_player(dt)
    self:_drive_ball_kinematic()
    self:_show_landing_marker(false)

    local remaining = self.flight_duration - self.state_elapsed
    if not self.prompt_shown and remaining <= self.cfg.jump_prompt_lead then
        self.prompt_shown = true
        self:_show_tip("跳！顶球！", 1.0)
        Log.info("ball rally jump prompt")
    end

    if self:_ball_out_of_bounds() then
        self:_settle_session("球出界，本轮结束")
        return
    end

    -- 球落入落点盒 + 玩家处于起跳窗口 → 顶回宝宝（容错优先于物理精确）。
    if self:_try_player_volley() then
        return
    end

    -- 球已落到地面仍未顶到，或超过宽限时间 → 玩家漏接 → 本局结束（算满足，按已顶次数计分）。
    local ball_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    if ball_pos and ball_pos.y <= self.cfg.floor_y + self.cfg.ball_ground_origin_offset + 0.15 then
        self:_settle_session("没顶到，本轮结束！")
        return
    end
    if self.state_elapsed >= self.flight_duration + self.cfg.miss_grace then
        self:_settle_session("没顶到，本轮结束！")
    end
end

---@return boolean true 表示已顶回，调用方应立即 return
function BallRallyService:_try_player_volley()
    if self.jump_window <= 0.0 or not self.target then
        return false
    end
    local ball_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    if not ball_pos then
        return false
    end
    -- 必须等球下落进入盒子高度，避免发球/上升途中误判。
    if ball_pos.y > self.cfg.floor_y + self.cfg.player_catch_height then
        return false
    end
    local box = self.cfg.player_catch_radius
    if not self:_xz_within(ball_pos, self.target, box) then
        return false
    end
    -- 玩家要站在落点盒附近（带余量），保留“跑到落点接球”的玩法。
    local player_pos = self.player and self.player.get_position and self.player.get_position() or nil
    if player_pos and not self:_xz_within(player_pos, self.target, box + self.cfg.player_box_margin) then
        return false
    end
    Log.info("ball rally player volley", self.player_hits)
    self:_launch_to_baby()
    return true
end

---@param a Vector3
---@param b Vector3
---@param radius Fixed
---@return boolean
function BallRallyService:_xz_within(a, b, radius)
    local dx = a.x - b.x
    local dz = a.z - b.z
    return dx * dx + dz * dz <= radius * radius
end

---@param dt Fixed
function BallRallyService:_update_to_baby(dt)
    self:_drive_ball_kinematic()
    if self:_ball_out_of_bounds() then
        self:_settle_session("回球出界，本轮结束")
        return
    end

    local ball_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    local baby_pos = self.server and self.server.unit.get_position and self.server.unit.get_position() or nil
    if not (ball_pos and baby_pos) then
        self:_settle_session("接球失败，本轮结束")
        return
    end

    -- 回球目标在玩家顶回那一刻已经锁定；接球点固定，不随宝宝动作上漂。
    -- 不在落地前提前做动作：宝宝的“举起接球”由 _resolve_baby_contact → _begin_hold 在球到手那刻完成（可见）。
    local catch_pos = self.target or math.Vector3(baby_pos.x, baby_pos.y + self.cfg.catch_height, baby_pos.z)
    local catch_radius_sq = self.cfg.catch_radius * self.cfg.catch_radius

    if self.state_elapsed >= self.flight_duration - 0.2
        and UnitUtil.distance_sq(ball_pos, catch_pos) <= catch_radius_sq then
        self:_resolve_baby_contact()
        return
    end

    -- 兜底：到达预定时刻后即便位置判定差一点，也让宝宝完成这次接球。
    if self.state_elapsed >= self.flight_duration + 0.4 then
        self:_resolve_baby_contact()
    end
end

-- 球回到宝宝：达到本局回合上限 → 宝宝举球庆祝收尾；否则把球接到头顶（可见举起）再发回玩家。
function BallRallyService:_resolve_baby_contact()
    if self.player_hits >= self.rally_max then
        self:_begin_celebrate()
        return
    end
    -- 复用发球序列：_begin_hold 把球吸到宝宝头顶 lift_unit（可见的“举起接球”）→ 短暂持球 → _request_throw 再发出。
    -- 不再瞬间运动学回弹，从而玩家能稳定看到宝宝举球接球的动作。
    self:_begin_hold()
end

-- 顶满收尾：宝宝把球举到头顶庆祝 celebrate_hold_seconds 秒，然后落球结算（算满足 + 满分）。
function BallRallyService:_begin_celebrate()
    local baby = self.server and self.server.unit or nil
    local baby_pos = baby and baby.get_position and baby.get_position() or nil
    if not (baby and baby_pos and self.ball) then
        self:_settle_session("完成！顶了 " .. tostring(self.player_hits) .. " 次")
        return
    end

    self:_destroy_landing_indicator()
    pcall(function()
        if self.ball.set_linear_velocity then
            self.ball.set_linear_velocity(ZERO)
        end
        if self.ball.set_angular_velocity then
            self.ball.set_angular_velocity(ZERO)
        end
        if self.ball.disable_gravity then
            self.ball.disable_gravity()
        end
        if self.ball.set_position then
            self.ball.set_position(baby_pos + math.Vector3(0.0, self.cfg.serve_ball_height, 0.0))
        end
    end)
    if baby.lift_unit then
        pcall(function() baby.lift_unit(self.ball) end)
    end

    self.server:set_status("顶满啦！举高高～")
    self:_show_tip("完成！宝宝举起球啦～", 1.5)
    self.state = State.Celebrate
    self.state_elapsed = 0.0
    Log.info("ball rally celebrate", self.player_hits)
end

function BallRallyService:_update_celebrate()
    if self.state_elapsed >= self.cfg.celebrate_hold_seconds then
        self:_settle_session("完成！顶了 " .. tostring(self.player_hits) .. " 次")
    end
end

function BallRallyService:_launch_to_baby()
    local start_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    local baby_pos = self.server and self.server.unit.get_position and self.server.unit.get_position() or nil
    if not (start_pos and baby_pos) then
        self:_settle_session("回球失败")
        return
    end

    local target = math.Vector3(
        clamp(baby_pos.x, self.cfg.min_x, self.cfg.max_x),
        baby_pos.y + self.cfg.catch_height,
        clamp(baby_pos.z, self.cfg.min_z, self.cfg.max_z)
    )
    self.target = target
    self.player_hits = self.player_hits + 1
    self.flight_duration = self:_choose_flight_time(
        start_pos,
        target,
        self.cfg.return_time_min,
        self.cfg.return_time_max
    )
    self:_destroy_landing_indicator()
    self:_set_collision(self.player, false)
    self:_begin_kinematic_flight(start_pos)

    self.state = State.ToBaby
    self.state_elapsed = 0.0
    self.jump_window = 0.0
    self.server:set_status("第 " .. tostring(self.player_hits) .. " 次，球来啦！")
    self:_show_tip("顶到了！x" .. tostring(self.player_hits), 1.0)
    Log.info(
        "ball rally returned to baby",
        self.player_hits,
        "time", self.flight_duration,
        "target", target.x, target.y, target.z
    )
end

---@return Vector3
function BallRallyService:_choose_player_target()
    local player_pos = self.player and self.player.get_position and self.player.get_position() or nil
    if not player_pos then
        player_pos = math.Vector3(
            (self.cfg.min_x + self.cfg.max_x) * 0.5,
            self.cfg.floor_y,
            (self.cfg.min_z + self.cfg.max_z) * 0.5
        )
    end

    local dx = random_fixed(-1.0, 1.0)
    local dz = random_fixed(-1.0, 1.0)
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 0.1 then
        dx = 1.0
        dz = 0.0
        length = 1.0
    end
    local distance = random_fixed(self.cfg.target_jitter_min, self.cfg.target_jitter_max)
    dx = dx / length * distance
    dz = dz / length * distance

    local y = self.cfg.floor_y + self.cfg.ball_ground_origin_offset
    local target = math.Vector3(
        clamp(player_pos.x + dx, self.cfg.min_x, self.cfg.max_x),
        y,
        clamp(player_pos.z + dz, self.cfg.min_z, self.cfg.max_z)
    )
    return self:_enforce_min_throw(target, y)
end

-- 落点离发球宝宝太近时投球会显得很怪：沿“宝宝→落点”方向把落点推到最小水平距离之外，再夹回场地。
---@param target Vector3
---@param y Fixed
---@return Vector3
function BallRallyService:_enforce_min_throw(target, y)
    local baby = self.server and self.server.unit or nil
    local baby_pos = baby and baby.get_position and baby.get_position() or nil
    local min_d = self.cfg.min_throw_distance
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
        clamp(baby_pos.x + tdx / d * min_d, self.cfg.min_x, self.cfg.max_x),
        y,
        clamp(baby_pos.z + tdz / d * min_d, self.cfg.min_z, self.cfg.max_z)
    )
end

---@param start_pos Vector3
---@param target_pos Vector3
---@param min_time Fixed
---@param max_time Fixed
---@return Fixed
function BallRallyService:_choose_flight_time(start_pos, target_pos, min_time, max_time)
    local dx = target_pos.x - start_pos.x
    local dz = target_pos.z - start_pos.z
    local horizontal_distance = math.sqrt(dx * dx + dz * dz)
    local minimum_for_speed = horizontal_distance / self.cfg.max_horizontal_speed
    local flight_time = random_fixed(min_time, max_time)
    if flight_time < minimum_for_speed then
        flight_time = minimum_for_speed
    end
    if flight_time < 0.5 then
        flight_time = 0.5
    end
    return flight_time
end

-- 开始一段运动学飞行：记录起点（落点 target、时长 flight_duration 由调用方先设好），
-- 关引擎重力、清零速度，球的轨迹此后完全由 _drive_ball_kinematic 的参数化弧线控制，
-- 落点精确等于 target，不受引擎真实重力/积分误差影响。
---@param start_pos Vector3
function BallRallyService:_begin_kinematic_flight(start_pos)
    self.launch_pos = start_pos
    -- 弧高随本次水平投掷距离缩放：远→高、近→低，看起来更自然。
    local target = self.target
    if target then
        local dx = target.x - start_pos.x
        local dz = target.z - start_pos.z
        local dist = math.sqrt(dx * dx + dz * dz)
        self.flight_arc_peak = clamp(
            self.cfg.arc_height_ratio * dist,
            self.cfg.arc_peak_min,
            self.cfg.arc_peak_max
        )
    end
    local ball = self.ball
    if not ball then
        return
    end
    pcall(function()
        if ball.set_physics_active then
            ball.set_physics_active(true)
        end
        if ball.disable_gravity then
            ball.disable_gravity()
        end
        -- 碰撞会留下角速度；不清零会让沙滩球纹理呈现螺旋回转。
        if ball.set_angular_velocity then
            ball.set_angular_velocity(ZERO)
        end
        if ball.set_position then
            ball.set_position(start_pos)
        end
        -- 运动学驱动独占球的运动：线速度清零，绝不把解析初速度交给引擎。
        -- 否则引擎会在 tick 之间按该初速度（叠加残留重力/碰撞）把球甩离轨道、
        -- 飞出世界被销毁，引发后续 self.ball 失效、整局连续判失败。
        if ball.set_linear_velocity then
            ball.set_linear_velocity(ZERO)
        end
    end)
end

-- 每 tick(0.1s) 把球平滑钉到参数化弧线上：
--   线性进度 s(0→1) 经 ease_out_in 整形为“两端快、中间慢”的 u；
--   水平按 u 在起点→落点之间插值；竖直叠加 4*peak*u*(1-u) 的拱（顶点在中段，自带悬停）。
-- 弧高(flight_arc_peak，按投掷距离缩放)与时长(flight_duration)完全解耦，s=1 时精确落到 target。
-- 用 set_position_smooth 让引擎在两 tick 之间插值过渡（视觉丝滑）；
-- 绝不 set_linear_velocity——给引擎初速度会把球甩离轨道、飞出界被销毁。
function BallRallyService:_drive_ball_kinematic()
    local ball = self.ball
    local p0 = self.launch_pos
    local p1 = self.target
    local dur = self.flight_duration
    if not (ball and p0 and p1 and dur and dur > 0.0) then
        return
    end
    local s = self.state_elapsed / dur
    if s < 0.0 then
        s = 0.0
    elseif s > 1.0 then
        s = 1.0
    end
    local u = ease_out_in(s, self.cfg.flight_hang)
    local arc = 4.0 * self.flight_arc_peak * u * (1.0 - u)
    local pos = math.Vector3(
        lerp(p0.x, p1.x, u),
        lerp(p0.y, p1.y, u) + arc,
        lerp(p0.z, p1.z, u)
    )
    pcall(function()
        if ball.set_position_smooth then
            ball.set_position_smooth(pos)
        elseif ball.set_position then
            ball.set_position(pos)
        end
    end)
end

---@param target Vector3
function BallRallyService:_face_server_to(target)
    local baby = self.server and self.server.unit or nil
    local pos = baby and baby.get_position and baby.get_position() or nil
    if not (baby and pos and baby.set_direction) then
        return
    end
    local direction = math.Vector3(target.x - pos.x, 0.0, target.z - pos.z)
    if direction.x * direction.x + direction.z * direction.z > 0.01 then
        pcall(function() baby.set_direction(direction) end)
    end
end

---@param first boolean
function BallRallyService:_show_landing_marker(first)
    if not self.target then
        return
    end
    local y = self.cfg.floor_y + 0.08
    local target = self.target
    local marker_pos = math.Vector3(target.x, y, target.z)

    if first then
        self:_destroy_landing_indicator()
        if GameAPI.play_sfx_by_key then
            local ok, sfx_id = pcall(function()
                return GameAPI.play_sfx_by_key(
                    self.cfg.indicator_sfx_key,
                    marker_pos,
                    math.Quaternion(0.0, 0.0, 0.0),
                    self.cfg.indicator_sfx_scale,
                    self.flight_duration + 1.0,
                    1.0,
                    false
                )
            end)
            if ok then
                self.indicator_sfx_id = sfx_id
            end
        end
    elseif self.indicator_sfx_id and GlobalAPI.set_sfx_position then
        pcall(function()
            GlobalAPI.set_sfx_position(self.indicator_sfx_id, marker_pos)
        end)
    end
end

function BallRallyService:_destroy_landing_indicator()
    if self.indicator_sfx_id and GlobalAPI.destroy_sfx then
        pcall(function()
            GlobalAPI.destroy_sfx(self.indicator_sfx_id, true)
        end)
    end
    self.indicator_sfx_id = nil
end

---@return boolean
function BallRallyService:_ball_out_of_bounds()
    local pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    if not pos then
        return true
    end
    local tolerance = self.cfg.boundary_tolerance or 0.0
    return pos.x < self.cfg.min_x - tolerance
        or pos.x > self.cfg.max_x + tolerance
        or pos.z < self.cfg.min_z - tolerance
        or pos.z > self.cfg.max_z + tolerance
        or pos.y < self.cfg.floor_y - 2.0
end

-- 一局顶球收尾：算满足该需求，按已成功顶球次数追加奖励，归还宝宝控制权并回到空转扫描。
---@param reason string
function BallRallyService:_settle_session(reason)
    if self.state == State.Disabled then
        return
    end

    local agent = self.server
    local catches = self.player_hits
    Log.info("ball rally settle", reason, "catches", catches)
    self:_show_tip(reason, 1.5)
    self:_destroy_landing_indicator()

    -- 先停下本次会话的驱动与状态。
    self.state = State.Disabled
    self.state_elapsed = 0.0
    self.target = nil
    self.jump_window = 0.0
    self.pending_launch = false
    self.release_attempted = false
    self.launch_pos = nil
    self.flight_arc_peak = 0.0
    self.rally_max = 0
    self.player_hits = 0
    self.server = nil

    -- 恢复实体碰撞，避免下一局开局前玩家穿过球/宝宝。
    self:_set_collision(self.player, true)
    local ball_was_held = false
    if agent and agent.unit then
        self:_set_collision(agent.unit, true)
        -- 先解锁动作锁，宝宝才能把手里的球放下（庆祝收尾时它正举着球）。
        agent.action_lock:release(RALLY_LOCK)
        if agent.unit.is_lift_status then
            local ok, value = pcall(function() return agent.unit.is_lift_status() end)
            ball_was_held = ok and value or false
        end
        if ball_was_held and agent.unit.ai_command_lift then
            -- ai_command_lift 是“举起/扔下”切换：手里有球时再调一次即把球放下。
            pcall(function() agent.unit.ai_command_lift() end)
        end
        agent:set_busy(false)
        agent:set_lift_enabled(true)
        agent:invalidate_systems()
        -- 算满足 + 按顶球次数计分 + 开心表现 + 推进下一个需求。
        agent:finish_ball_rally(self.role, catches)
    end

    -- 球收尾：恢复引擎重力让它自然落地停住——否则运动学期间关掉的重力会让球悬在半空
    -- （用户反馈“球靠在围栏上飘起来”）。被举着的球上面已让宝宝放下；漏接的球清零速度原地落下。
    -- 下一局开局 _configure_ball 会再次关重力。
    local ball = self.ball
    if ball then
        pcall(function()
            if not ball_was_held then
                if ball.set_angular_velocity then
                    ball.set_angular_velocity(ZERO)
                end
                if ball.set_linear_velocity then
                    ball.set_linear_velocity(ZERO)
                end
            end
            if ball.enable_gravity then
                ball.enable_gravity()
            end
        end)
    end
end

function BallRallyService:destroy()
    self:_destroy_landing_indicator()
    self:_set_collision(self.player, true)
    if self.server and self.server.unit then
        self:_set_collision(self.server.unit, true)
        self.server.action_lock:release(RALLY_LOCK)
        self.server:set_busy(false)
        self.server:set_lift_enabled(true)
        self.server:invalidate_systems()
    end
    self.state = State.Disabled
    self.server = nil
    self.agents = nil
    self.pending_launch = false
    Log.info("ball rally destroyed")
end

return BallRallyService
