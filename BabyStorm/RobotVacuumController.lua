local Class = require("BaseClass")
local Config = require("BabyStorm.Config.BabyStormConfig")
local BabyStormController = require("BabyStorm.BabyStormController")
local RobotDriveDriver = require("BabyStorm.Core.Drivers.RobotDriveDriver")
local RobotVacuumView = require("BabyStorm.View.RobotVacuumView")
local RoleUtil = require("Util.RoleUtil")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

-- 扫地机器人功能入口。
-- 举起/放下决定哪个玩家可启动；按钮在启动/退出间切换；
-- 连续输入与位移全部委托给 RobotDriveDriver。
---@class RobotVacuumRuntime
---@field application GameApplication|nil
---@field config RobotVacuumConfig
---@field view RobotVacuumView
---@field drive RobotDriveDriver
---@field robot Unit|nil
---@field cleaner DirtyDiaperProp|nil
---@field lifting_role Role|nil
---@field ready_role Role|nil
---@field ready_role_id RoleID|integer|nil
---@field controlling_role Role|nil
---@field controlling_role_id RoleID|integer|nil
---@field controlling_unit Unit|LifeEntity|nil
---@field move_lock_engaged boolean
local RobotVacuumRuntime = Class("RobotVacuumRuntime")

---@param application GameApplication|nil
function RobotVacuumRuntime:Ctor(application)
    self.application = application
    self.config = Config.robot_vacuum
    self.view = RobotVacuumView.New(self.config)
    self.drive = RobotDriveDriver.New()
    self.robot = nil
    self.cleaner = nil
    self.lifting_role = nil
    self.ready_role = nil
    self.ready_role_id = nil
    self.controlling_role = nil
    self.controlling_role_id = nil
    self.controlling_unit = nil
    self.move_lock_engaged = false
end

---@return boolean
function RobotVacuumRuntime:start()
    self.view:hide_all(GameAPI.get_all_valid_roles() or {})

    self.robot = LuaAPI.query_unit(self.config.unit_name)
    if not self.robot then
        Log.warn("robot vacuum unit not found", self.config.unit_name)
        return false
    end
    if not self.application then
        Log.warn("robot vacuum triggers not bound: no application")
        return false
    end

    local manager = BabyStormController.get_manager()
    self.cleaner = manager and manager:get_dirty_diaper_service() or nil
    if not self.cleaner then
        Log.warn("robot vacuum dirty diaper cleaner unavailable")
    end

    self.view:bind_start_button(self.application, function(role)
        self:_on_start_button(role)
    end)
    self.application.register_unit_trigger(
        self.robot,
        { EVENT.SPEC_OBSTACLE_LIFTED_BEGIN },
        function(_, _, data)
            self:_on_lift_begin(data)
        end
    )
    self.application.register_unit_trigger(
        self.robot,
        { EVENT.SPEC_OBSTACLE_LIFTED_END },
        function(_, _, data)
            self:_on_lift_end(data)
        end
    )
    self.application.register_unit_trigger(
        self.robot,
        { EVENT.SPEC_OBSTACLE_CONTACT_BEGIN },
        function(_, _, data)
            self:_on_contact_begin(data)
        end
    )

    Log.info("robot vacuum ready", self.config.unit_name)
    return true
end

---@param data table|nil
function RobotVacuumRuntime:_on_lift_begin(data)
    -- 控制时机器人再次被举起，必须先释放玩家 Buff，避免按钮隐藏后无法主动退出。
    self:_exit_control(false)
    self:_clear_ready_role()
    self.lifting_role = RoleUtil.get_role_by_unit(data and data.lift_unit or nil)
end

---@param data table|nil
function RobotVacuumRuntime:_on_lift_end(data)
    local role = RoleUtil.get_role_by_unit(data and data.lift_unit or nil) or self.lifting_role
    self.lifting_role = nil

    self:_prepare_robot_physics()
    self:_set_flat_orientation()
    self:_set_ready_role(role)
end

---@param data table|nil
function RobotVacuumRuntime:_on_contact_begin(data)
    local cleaner = self.cleaner
    if not (self.controlling_role_id and cleaner and data) then
        return
    end

    local unit1 = data.unit1
    local unit2 = data.unit2
    local other = unit2
    if UnitUtil.same_unit(unit2, self.robot) then
        other = unit1
    end
    cleaner:clean_unit(other)
end

function RobotVacuumRuntime:_prepare_robot_physics()
    local robot = self.robot
    if not robot then
        return
    end
    if robot.set_physics_active then
        pcall(function() robot.set_physics_active(true) end)
    end
    if robot.enable_unit_ccd then
        pcall(function() robot.enable_unit_ccd() end)
    end
end

function RobotVacuumRuntime:_set_flat_orientation()
    local robot = self.robot
    if not (robot and robot.set_orientation) then
        return
    end

    local roll = math.deg_to_rad(self.config.flat_roll_degrees)
    robot.set_orientation(math.Quaternion(0.0, 0.0, roll))
    self.drive:reset_spin()
end

---@param role Role
function RobotVacuumRuntime:_on_start_button(role)
    local role_id = RoleUtil.get_role_id(role)
    if not role_id then
        return
    end

    if self.controlling_role_id then
        if role_id == self.controlling_role_id then
            self:_exit_control(true)
        end
        return
    end
    if role_id ~= self.ready_role_id then
        return
    end

    self:_enter_control(role, role_id)
end

---@param role Role
---@param role_id RoleID|integer
---@return boolean
function RobotVacuumRuntime:_enter_control(role, role_id)
    local player = role.get_ctrl_unit and role.get_ctrl_unit() or nil
    if not (self.robot and player and player.add_state) then
        Log.warn("robot vacuum control rejected: invalid player or robot", role_id)
        return false
    end

    self:_prepare_robot_physics()
    local cleaner = self.cleaner
    local started = self.drive:start({
        robot = self.robot,
        player = player,
        move_speed = self.config.move_speed,
        spin_speed = self.config.spin_speed,
        joystick_deadzone = self.config.joystick_deadzone,
        flat_roll_degrees = self.config.flat_roll_degrees,
        collision_radius = self.config.collision_radius,
        collision_probe_height = self.config.collision_probe_height,
        collision_skin = self.config.collision_skin,
        should_block = function(unit)
            return not (cleaner and cleaner:is_cleanable(unit))
        end,
        on_step = function(pos)
            if cleaner then
                cleaner:clean_near(pos, self.config.clean_radius)
            end
        end,
    })
    if not started then
        Log.warn("robot vacuum driver failed to start", role_id)
        return false
    end

    local locked = pcall(function()
        player.add_state(Enums.BuffState.BUFF_FORBID_MOVE)
    end)
    if not locked then
        self.drive:stop()
        Log.warn("robot vacuum player lock failed", role_id)
        return false
    end

    self.controlling_role = role
    self.controlling_role_id = role_id
    self.controlling_unit = player
    self.move_lock_engaged = true
    self.view:show_controlling(role)
    Log.info("robot vacuum control started", role_id)
    return true
end

---@param show_ready boolean
function RobotVacuumRuntime:_exit_control(show_ready)
    if not self.controlling_role_id and not self.move_lock_engaged and not self.drive:is_active() then
        return
    end

    local role_id = self.controlling_role_id
    local player = self.controlling_unit
    self.drive:stop()

    if self.move_lock_engaged and player and player.remove_state then
        pcall(function()
            player.remove_state(Enums.BuffState.BUFF_FORBID_MOVE)
        end)
    end

    self.controlling_role = nil
    self.controlling_role_id = nil
    self.controlling_unit = nil
    self.move_lock_engaged = false

    if show_ready and self.ready_role then
        self.view:show_ready(self.ready_role)
    end
    Log.info("robot vacuum control stopped", role_id or "unknown")
end

---@param role Role|nil
function RobotVacuumRuntime:_set_ready_role(role)
    self:_clear_ready_role()
    if not role then
        Log.warn("robot vacuum dropped without a valid role")
        return
    end

    self.ready_role = role
    self.ready_role_id = RoleUtil.get_role_id(role)
    self.view:show_ready(role)
end

function RobotVacuumRuntime:_clear_ready_role()
    if self.ready_role then
        self.view:hide(self.ready_role)
    end
    self.ready_role = nil
    self.ready_role_id = nil
end

function RobotVacuumRuntime:destroy()
    self:_exit_control(false)
    self:_clear_ready_role()
    self.view:hide_all(GameAPI.get_all_valid_roles() or {})
    self.lifting_role = nil
    self.robot = nil
    self.cleaner = nil
    self.application = nil
end

---@class RobotVacuumController: GameController
local RobotVacuumController = {}

---@type RobotVacuumRuntime|nil
local runtime = nil

---@param application GameApplication|nil
---@return RobotVacuumRuntime
function RobotVacuumController.init(application)
    if runtime then
        return runtime
    end

    runtime = RobotVacuumRuntime.New(application)
    runtime:start()
    return runtime
end

---@param application GameApplication|nil
function RobotVacuumController.destroy(application)
    if runtime then
        runtime:destroy()
        runtime = nil
    end
end

return RobotVacuumController
