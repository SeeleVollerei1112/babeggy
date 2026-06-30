local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local RoleUtil = require("Util.RoleUtil")
local Log = require("Util.Log")

local State = {
    Idle = "idle",
    WaitPlayer = "wait_player",
    Ready = "ready",
    Tossing = "tossing",
}

local LOCK = "rps"
local PI = 3.14159265
local TWO_PI = PI * 2.0
local ZERO = math.Vector3(0.0, 0.0, 0.0)

local RpsService = Class("RpsService")

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
    self.elapsed = 0.0
    self.ground_y = {}
    self.flight = {}
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
            -- 场景里的“手势骰子2”配置了 200 投掷力，会在脚本接管前飞出很远。
            -- 归零原生投掷力，猜拳轨迹全部由本服务控制。
            if die.set_custom_thrown_force then die.set_custom_thrown_force(0.0) end
            if die.set_custom_thrown_force_enabled then die.set_custom_thrown_force_enabled(true) end
        end)
        local pos = die.get_position and die.get_position() or nil
        self.ground_y[index] = pos and pos.y or nil
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
                    self.ground_y[die_index] = die_pos.y
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
    if not (candidate and self:_unit_near_baby(candidate)) then
        self.hold_elapsed = 0.0
        return
    end
    -- 两边必须都被引擎确认为“正在举着指定骰子”，连续稳定两拍才进入就绪。
    if not self:_unit_holds(candidate, self.player_die) then
        self.hold_elapsed = 0.0
        return
    end
    self.hold_elapsed = self.hold_elapsed + dt
    if self.hold_elapsed >= 0.2 then
        self.player_unit = candidate
        self.role = RoleUtil.get_role_by_unit(candidate)
        self.release_elapsed = 0.0
        self.state = State.Ready
        agent:set_status("一起往头顶抛！")
        Log.info("rps both holding", agent.index)
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
    self.agent:set_status(text)
end

function RpsService:_begin_toss()
    local agent = self.agent
    if not (agent and agent.unit and self.player_unit) then
        self:_abort()
        return
    end
    if agent.unit.is_lift_status and agent.unit.is_lift_status() and agent.unit.ai_command_lift then
        pcall(function() agent.unit.ai_command_lift() end)
    end

    local baby_pos = agent.unit.get_position and agent.unit.get_position() or nil
    local player_pos = self.player_unit.get_position and self.player_unit.get_position() or nil
    if not (baby_pos and player_pos) then
        self:_abort()
        return
    end
    self.flight = {}
    self:_prepare_die(self.baby_die_index, baby_pos, player_pos, -1.0)
    self:_prepare_die(self.player_die_index, player_pos, baby_pos, 1.0)
    self.elapsed = 0.0
    self.state = State.Tossing
    agent:set_status("石头、剪刀、布！")
    Log.info("rps toss started", agent.index)
end

---@param die_index integer
---@param owner_pos Vector3
---@param other_pos Vector3
---@param fallback_sign Fixed
function RpsService:_prepare_die(die_index, owner_pos, other_pos, fallback_sign)
    local die = self.dice[die_index]
    local start_pos = die.get_position and die.get_position() or owner_pos
    local dx = owner_pos.x - other_pos.x
    local dz = owner_pos.z - other_pos.z
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 0.1 then
        dx, dz, length = fallback_sign, 0.0, 1.0
    end
    local offset = self.cfg.landing_offset
    local target = math.Vector3(
        owner_pos.x + dx / length * offset,
        (self.ground_y[die_index] or owner_pos.y) + self.cfg.landing_height,
        owner_pos.z + dz / length * offset
    )
    local face = self:_random_face()
    local spin_axis, final_angle = self:_face_spin(face)
    self.flight[die_index] = {
        start = start_pos,
        target = target,
        spin_axis = spin_axis,
        final_angle = final_angle,
        turns = 1,
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
    for index = 1, #self.dice do
        local die = self.dice[index]
        local flight = self.flight[index]
        if flight then
            local start_pos = flight.start
            local target = flight.target
            local arc = 4.0 * self.cfg.throw_height * t * (1.0 - t)
            local pos = math.Vector3(
                start_pos.x + (target.x - start_pos.x) * t,
                start_pos.y + (target.y - start_pos.y) * t + arc,
                start_pos.z + (target.z - start_pos.z) * t
            )
            local angle = (flight.turns * TWO_PI + flight.final_angle) * t
            local rot
            if flight.spin_axis == "x" then
                rot = math.Quaternion(angle, 0.0, 0.0)
            else
                rot = math.Quaternion(0.0, 0.0, angle)
            end
            pcall(function()
                if die.set_position_smooth then die.set_position_smooth(pos) else die.set_position(pos) end
                if die.set_orientation_smooth then
                    die.set_orientation_smooth(rot)
                elseif die.set_orientation then
                    die.set_orientation(rot)
                end
            end)
        end
    end
    if t >= 1.0 then
        self:_finish_toss()
    end
end

function RpsService:_finish_toss()
    for index = 1, #self.dice do
        local die = self.dice[index]
        local flight = self.flight[index]
        if flight then
            pcall(function()
                if die.set_position then die.set_position(flight.target) end
                if die.set_orientation then
                    if flight.spin_axis == "x" then
                        die.set_orientation(math.Quaternion(flight.final_angle, 0.0, 0.0))
                    else
                        die.set_orientation(math.Quaternion(0.0, 0.0, flight.final_angle))
                    end
                end
                if die.set_physics_active then die.set_physics_active(true) end
                if die.enable_gravity then die.enable_gravity() end
            end)
        end
    end
    local agent = self.agent
    local role = self.role
    self:_release_agent()
    self:_clear_session()
    if agent and not agent.destroyed then
        agent:finish_rps(role)
    end
    Log.info("rps toss finished")
end

---@return integer
function RpsService:_random_face()
    if GameAPI and GameAPI.random_int then
        return GameAPI.random_int(1, 6)
    end
    return math.tointeger(LuaAPI.rand() % 6) + 1
end

---@param face integer
---@return "x"|"z", Fixed
function RpsService:_face_spin(face)
    if face == 2 then return "x", PI end
    if face == 3 then return "x", PI * 0.5 end
    if face == 4 then return "x", -PI * 0.5 end
    if face == 5 then return "z", PI * 0.5 end
    if face == 6 then return "z", -PI * 0.5 end
    return "x", 0.0
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
    self.elapsed = 0.0
    self.flight = {}
end

function RpsService:_abort()
    self:_release_agent()
    self:_clear_session()
end

function RpsService:destroy()
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
