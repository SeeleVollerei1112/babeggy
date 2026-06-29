local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

local State = {
    Disabled = "disabled",
    Prepare = "prepare",
    Holding = "holding",
    WaitRelease = "wait_release",
    ToPlayer = "to_player",
    ToBaby = "to_baby",
}

---@class BallRallyService
---@field config BabyStormConfig
---@field cfg BabyBallRallyConfig
---@field triggers TriggerRegistry
---@field sessions PlayerSessionRegistry|nil
---@field ball Obstacle|Unit|nil
---@field server BabyAgent|nil
---@field role Role|nil
---@field player LifeEntity|Character|nil
---@field state string
---@field state_elapsed Fixed
---@field flight_duration Fixed
---@field target Vector3|nil
---@field jump_window Fixed
---@field prompt_shown boolean
---@field release_attempted boolean
---@field pending_launch boolean
---@field gravity Fixed
---@field launch_pos Vector3|nil
---@field launch_velocity Vector3|nil
---@field indicator_sfx_id SfxID|nil
---@field rally_goal integer
---@field player_hits integer
---@field baby_jump_triggered boolean
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
    self.ball = nil
    self.server = nil
    self.role = nil
    self.player = nil
    self.state = State.Disabled
    self.state_elapsed = 0.0
    self.flight_duration = 0.0
    self.target = nil
    self.jump_window = 0.0
    self.prompt_shown = false
    self.release_attempted = false
    self.pending_launch = false
    -- 运动学弧线高度参数（不再需要匹配引擎真实重力，纯表现，可调）。
    self.gravity = self.cfg and self.cfg.gravity or 9.8
    self.launch_pos = nil
    self.launch_velocity = nil
    self.indicator_sfx_id = nil
    self.rally_goal = 0
    self.player_hits = 0
    self.baby_jump_triggered = false
end

---@param agents BabyAgent[]
---@return boolean
function BallRallyService:start(agents)
    local cfg = self.cfg
    if not (cfg and cfg.enabled) then
        return false
    end

    self.ball = LuaAPI.query_unit(cfg.ball_name)
    self.server = agents and agents[cfg.server_baby_index or 1] or nil
    self.role, self.player = self:_first_player()

    if not self.ball then
        Log.warn("ball rally missing ball", cfg.ball_name)
        return false
    end
    if not (self.server and self.server.unit) then
        Log.warn("ball rally missing server baby", cfg.server_baby_index)
        return false
    end
    if not (self.role and self.player) then
        Log.warn("ball rally missing player")
        return false
    end

    self.server:cancel_need_countdown()
    self.server:set_busy(true)
    self.server:set_lift_enabled(false)
    self.server:set_status("和我顶球吧！")
    self.server.action_lock:acquire(RALLY_LOCK)
    self.server:invalidate_systems()

    self:_set_collision(self.player, false)
    self:_set_collision(self.server.unit, false)
    self:_configure_ball()
    self:_register_events()

    self.state = State.Prepare
    self.state_elapsed = -(cfg.initial_delay or 1.0)
    self:_show_tip("准备接宝宝的球！", 2.0)
    Log.info("ball rally started", cfg.ball_name, "server", self.server.index)
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

function BallRallyService:_register_events()
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
    end
end

function BallRallyService:_begin_hold()
    local baby = self.server and self.server.unit or nil
    local baby_pos = baby and baby.get_position and baby.get_position() or nil
    if not (baby and baby_pos and self.ball) then
        self:_reset_round("准备失败")
        return
    end

    self:_set_collision(self.player, false)
    self:_set_collision(baby, false)
    self.jump_window = 0.0
    self.pending_launch = false
    self.prompt_shown = false
    self.target = nil
    self:_destroy_landing_indicator()

    if GameAPI and GameAPI.random_int then
        self.rally_goal = GameAPI.random_int(self.cfg.rally_round_min, self.cfg.rally_round_max)
    else
        self.rally_goal = self.cfg.rally_round_min
    end
    self.player_hits = 0
    self.baby_jump_triggered = false

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

    if baby.lift_unit then
        pcall(function() baby.lift_unit(self.ball) end)
    end

    self.server:set_status("准备连续顶 " .. tostring(self.rally_goal) .. " 轮！")
    self.state = State.Holding
    self.state_elapsed = 0.0
    Log.info("ball rally baby holding", "goal", self.rally_goal)
end

function BallRallyService:_request_throw()
    local ball_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    if not ball_pos then
        self:_reset_round("球丢失了")
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
    self:_show_tip("第 1/" .. tostring(self.rally_goal) .. " 轮，去落点准备接球！", 1.8)

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
        self:_reset_round("发球失败")
        return
    end

    local velocity = self:_solve_velocity(start_pos, self.target, self.flight_duration)
    self:_begin_kinematic_flight(start_pos, velocity)
    self:_set_collision(self.player, false)

    self.state = State.ToPlayer
    self.state_elapsed = 0.0
    self.jump_window = 0.0
    self.prompt_shown = false
    Log.info(
        "ball rally launched to player",
        "time", self.flight_duration,
        "velocity", velocity.x, velocity.y, velocity.z
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
        self:_reset_round("球出界了，再来一次！")
        return
    end

    -- 球落入落点盒 + 玩家处于起跳窗口 → 顶回宝宝（容错优先于物理精确）。
    if self:_try_player_volley() then
        return
    end

    -- 球已落到地面仍未顶到，或超过宽限时间 → 本轮失败。
    local ball_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    if ball_pos and ball_pos.y <= self.cfg.floor_y + self.cfg.ball_ground_origin_offset + 0.15 then
        self:_reset_round("没顶到，再来一次！")
        return
    end
    if self.state_elapsed >= self.flight_duration + self.cfg.miss_grace then
        self:_reset_round("没顶到，再来一次！")
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
    Log.info("ball rally player volley", self.player_hits, self.rally_goal)
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
        self:_reset_round("回球出界了")
        return
    end

    local ball_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    local baby_pos = self.server and self.server.unit.get_position and self.server.unit.get_position() or nil
    if not (ball_pos and baby_pos) then
        self:_reset_round("接球失败")
        return
    end

    -- 回球目标在玩家顶回那一刻已经锁定；宝宝跳起后自身 Y 会变化，不能让接球点跟着上漂。
    local catch_pos = self.target or math.Vector3(baby_pos.x, baby_pos.y + self.cfg.catch_height, baby_pos.z)
    local catch_radius_sq = self.cfg.catch_radius * self.cfg.catch_radius
    local remaining = self.flight_duration - self.state_elapsed
    if not self.baby_jump_triggered and remaining <= self.cfg.baby_jump_lead then
        self.baby_jump_triggered = true
        if self.server.unit.ai_command_jump then
            pcall(function() self.server.unit.ai_command_jump() end)
        elseif self.server.unit.jump then
            pcall(function() self.server.unit.jump() end)
        end
        self.server:set_status("宝宝回顶！")
        Log.info("ball rally baby jump", self.player_hits, self.rally_goal)
    end

    if self.state_elapsed >= self.flight_duration - 0.2
        and UnitUtil.distance_sq(ball_pos, catch_pos) <= catch_radius_sq then
        self:_resolve_baby_contact()
        return
    end

    -- 兜底：到达预定时刻后即便位置判定差一点，也让宝宝完成这次回顶。
    if self.state_elapsed >= self.flight_duration + 0.4 then
        self:_resolve_baby_contact()
    end
end

function BallRallyService:_resolve_baby_contact()
    if self.player_hits >= self.rally_goal then
        local completed = self.rally_goal
        self:_show_tip("完成 " .. tostring(completed) .. " 轮连续顶球！", 1.5)
        Log.info("ball rally completed", completed)
        self:_begin_hold()
        return
    end
    self:_baby_rebound()
end

function BallRallyService:_baby_rebound()
    local start_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    if not start_pos then
        self:_reset_round("宝宝回顶失败")
        return
    end

    self.target = self:_choose_player_target()
    self.flight_duration = self:_choose_flight_time(
        start_pos,
        self.target,
        self.cfg.flight_time_min,
        self.cfg.flight_time_max
    )
    local velocity = self:_solve_velocity(start_pos, self.target, self.flight_duration)
    self:_begin_kinematic_flight(start_pos, velocity)
    self:_set_collision(self.player, false)

    self.state = State.ToPlayer
    self.state_elapsed = 0.0
    self.jump_window = 0.0
    self.prompt_shown = false
    self.baby_jump_triggered = false
    self:_show_landing_marker(true)

    local next_round = self.player_hits + 1
    self:_show_tip(
        "第 " .. tostring(next_round) .. "/" .. tostring(self.rally_goal) .. " 轮，准备！",
        1.5
    )
    Log.info(
        "ball rally baby rebound",
        self.player_hits, self.rally_goal,
        "time", self.flight_duration,
        "velocity", velocity.x, velocity.y, velocity.z
    )
end

function BallRallyService:_launch_to_baby()
    local start_pos = self.ball and self.ball.get_position and self.ball.get_position() or nil
    local baby_pos = self.server and self.server.unit.get_position and self.server.unit.get_position() or nil
    if not (start_pos and baby_pos) then
        self:_reset_round("回球失败")
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
    local velocity = self:_solve_velocity(start_pos, target, self.flight_duration)
    self:_destroy_landing_indicator()
    self:_set_collision(self.player, false)
    self:_begin_kinematic_flight(start_pos, velocity)

    self.state = State.ToBaby
    self.state_elapsed = 0.0
    self.jump_window = 0.0
    self.baby_jump_triggered = false
    self.server:set_status("第 " .. tostring(self.player_hits) .. " 轮，球来啦！")
    self:_show_tip(
        "顶到了！" .. tostring(self.player_hits) .. "/" .. tostring(self.rally_goal),
        1.0
    )
    Log.info(
        "ball rally returned to baby",
        self.player_hits, self.rally_goal,
        "time", self.flight_duration,
        "velocity", velocity.x, velocity.y, velocity.z
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

    return math.Vector3(
        clamp(player_pos.x + dx, self.cfg.min_x, self.cfg.max_x),
        self.cfg.floor_y + self.cfg.ball_ground_origin_offset,
        clamp(player_pos.z + dz, self.cfg.min_z, self.cfg.max_z)
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

---@param start_pos Vector3
---@param target_pos Vector3
---@param flight_time Fixed
---@return Vector3
function BallRallyService:_solve_velocity(start_pos, target_pos, flight_time)
    local vx = (target_pos.x - start_pos.x) / flight_time
    local vz = (target_pos.z - start_pos.z) / flight_time
    local vy = (
        target_pos.y - start_pos.y
        + 0.5 * self.gravity * flight_time * flight_time
    ) / flight_time
    return math.Vector3(vx, vy, vz)
end

-- 开始一段运动学飞行：记录起点与初速度，关引擎重力，球的轨迹此后完全由
-- _drive_ball_kinematic 按解析抛物线（用 self.gravity 这个纯弧线参数）控制，
-- 落点精确等于 target，不受引擎真实重力/积分误差影响。
---@param start_pos Vector3
---@param velocity Vector3
function BallRallyService:_begin_kinematic_flight(start_pos, velocity)
    self.launch_pos = start_pos
    self.launch_velocity = velocity
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
        if ball.set_linear_velocity then
            ball.set_linear_velocity(velocity)
        end
    end)
end

-- 每 tick 把球钉在解析抛物线上：set_position 校正位置（消除累积误差→落点精确），
-- set_linear_velocity 给瞬时速度，让引擎在 0.1s tick 之间用速度平滑外推（视觉不卡）。
function BallRallyService:_drive_ball_kinematic()
    local ball = self.ball
    local p0 = self.launch_pos
    local v0 = self.launch_velocity
    if not (ball and p0 and v0) then
        return
    end
    local t = self.state_elapsed
    if t < 0.0 then
        t = 0.0
    end
    local g = self.gravity
    local pos = math.Vector3(
        p0.x + v0.x * t,
        p0.y + v0.y * t - 0.5 * g * t * t,
        p0.z + v0.z * t
    )
    local vel = math.Vector3(v0.x, v0.y - g * t, v0.z)
    pcall(function()
        if ball.set_position then
            ball.set_position(pos)
        end
        if ball.set_linear_velocity then
            ball.set_linear_velocity(vel)
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

---@param reason string
function BallRallyService:_reset_round(reason)
    Log.info("ball rally reset", reason)
    self:_show_tip(reason, 1.2)
    self:_destroy_landing_indicator()
    -- 球已经落地时恢复实体碰撞，避免玩家在下一次举球前穿过球体。
    self:_set_collision(self.player, true)
    self.state = State.Prepare
    self.state_elapsed = -1.0
    self.target = nil
    self.jump_window = 0.0
    self.pending_launch = false
    self.launch_pos = nil
    self.launch_velocity = nil
    if self.server then
        self.server:set_status("再来一次！")
    end
end

function BallRallyService:destroy()
    if self.state == State.Disabled then
        return
    end
    self:_set_collision(self.player, true)
    self:_destroy_landing_indicator()
    if self.server and self.server.unit then
        self:_set_collision(self.server.unit, true)
        self.server.action_lock:release(RALLY_LOCK)
        self.server:set_busy(false)
        self.server:set_lift_enabled(true)
        self.server:invalidate_systems()
    end
    self.state = State.Disabled
    self.pending_launch = false
    Log.info("ball rally destroyed")
end

return BallRallyService
