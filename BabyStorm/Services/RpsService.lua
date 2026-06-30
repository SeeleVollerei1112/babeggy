local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local RoleUtil = require("Util.RoleUtil")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Log = require("Util.Log")

local State = {
    Idle = "idle",
    WaitPlayer = "wait_player",
    Ready = "ready",
    Tossing = "tossing",   -- 脚本把骰子向上抛到头顶区域（只控位移，不再人为旋转）
    Settling = "settling", -- 抛到顶后交给物理：玩家/宝宝顶撞翻面，轮询到静止再结算
}

local LOCK = "rps"
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
    -- 落地结算（轮询静止）+ 宝宝自动顶撞用的运行时字段。
    self.settle_elapsed = 0.0
    self.rest_frames = 0
    self.bonk_count = 0
    self.bonk_timer = 0.0
    self.pending_jump = nil
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
    elseif self.state == State.Settling then
        self:_update_settle(dt)
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
    -- 抛点：自己头顶偏一点点（两颗骰子稍微错开）。落地朝向不再人为指定，
    -- 交给后续顶撞的物理碰撞自然翻面（见 §"新方案"）。
    local target = math.Vector3(
        owner_pos.x + dx / length * offset,
        (self.ground_y[die_index] or owner_pos.y) + self.cfg.landing_height,
        owner_pos.z + dz / length * offset
    )
    self.flight[die_index] = {
        start = start_pos,
        target = target,
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
            -- 只控位移：把骰子向上抛到头顶区域。旋转交给物理顶撞，脚本不再转。
            pcall(function()
                if die.set_position_smooth then die.set_position_smooth(pos) else die.set_position(pos) end
            end)
        end
    end
    if t >= 1.0 then
        self:_release_to_physics()
    end
end

-- 抛到顶后把两颗骰子交还物理引擎：恢复重力与碰撞，使其能被顶飞/翻面/自由落体。
-- 不再吸附到预定朝向——朝向由后续顶撞的真实碰撞决定。随后进入 Settling 轮询静止。
function RpsService:_release_to_physics()
    for index = 1, #self.dice do
        local die = self.dice[index]
        local flight = self.flight[index]
        if flight then
            pcall(function()
                if die.set_position then die.set_position(flight.target) end
                if die.set_linear_velocity then die.set_linear_velocity(ZERO) end
                if die.set_angular_velocity then die.set_angular_velocity(ZERO) end
                if die.set_physics_active then die.set_physics_active(true) end
                if die.enable_gravity then die.enable_gravity() end
            end)
        end
    end
    self:_begin_settle()
end

-- 进入结算阶段：放开宝宝的移动锁，让它能自己走两步 + 起跳顶骰子；
-- 玩家侧不脚本化，玩家自己跳。两颗骰子都静止后才结算。
function RpsService:_begin_settle()
    local agent = self.agent
    if agent and not agent.destroyed then
        -- 干净地解锁（移除 BUFF_FORBID_MOVE、恢复 move_speed），让宝宝能位移和起跳。
        agent.action_lock:release(LOCK)
        -- 仍保持 busy（IdleState:update 会因 busy 早退，不会抢 move_mode），
        -- 仅把意图设为 Stop，避免 Wander 把移速压回 0 挡住顶撞用的走位。
        agent.move_mode = Intent.MoveMode.Stop
        agent:invalidate_systems()
        agent:set_status("顶一下让它翻面！")
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

    -- 宝宝自动顶撞：走一点点距离 → 起跳顶骰子，重复若干次后停手让它落地。
    self:_drive_baby_bonk(dt)

    -- 轮询静止：给一点缓冲时间让骰子先下落，之后连续若干帧都静止才算落定。
    if self.settle_elapsed >= self.cfg.settle_min_time and self:_dice_at_rest() then
        self.rest_frames = self.rest_frames + 1
    else
        self.rest_frames = 0
    end

    if self.rest_frames >= self.cfg.settle_rest_frames
        or self.settle_elapsed >= self.cfg.settle_timeout
    then
        self:_finish_settle()
    end
end

-- 宝宝顶撞循环：每隔 baby_bonk_interval 朝骰子方向走一小步再起跳，最多 baby_bonk_max 次。
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

    local dir = self:_baby_bonk_dir(unit)
    if dir and unit.ai_command_start_move then
        pcall(function() unit.ai_command_start_move(dir, self.cfg.baby_bonk_move_time) end)
    end
    self.pending_jump = self.cfg.baby_bonk_move_time
end

-- 宝宝走位方向：朝自己那颗骰子的水平方向偏移一点（贴着骰子边缘顶 → 触发翻面）。
---@param unit Unit
---@return Vector3|nil
function RpsService:_baby_bonk_dir(unit)
    local baby_pos = unit.get_position and unit.get_position() or nil
    local die_pos = self.baby_die and self.baby_die.get_position and self.baby_die.get_position() or nil
    if not baby_pos then
        return nil
    end
    local dx, dz = 1.0, 0.0
    if die_pos then
        dx = die_pos.x - baby_pos.x
        dz = die_pos.z - baby_pos.z
    end
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 0.1 then
        dx, dz, length = 1.0, 0.0, 1.0
    end
    return math.Vector3(dx / length, 0.0, dz / length)
end

-- 两颗骰子都接近静止（线速度足够小）才算落定。玩家一直顶 → 速度不为 0 → 不结算。
---@return boolean
function RpsService:_dice_at_rest()
    local eps = self.cfg.settle_rest_speed
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
    end
    return true
end

function RpsService:_finish_settle()
    local agent = self.agent
    local role = self.role
    self:_release_agent()
    self:_clear_session()
    if agent and not agent.destroyed then
        agent:finish_rps(role)
    end
    Log.info("rps settle finished")
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
    self.settle_elapsed = 0.0
    self.rest_frames = 0
    self.bonk_count = 0
    self.bonk_timer = 0.0
    self.pending_jump = nil
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
