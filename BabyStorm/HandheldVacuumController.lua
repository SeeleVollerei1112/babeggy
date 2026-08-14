local Class = require("BaseClass")
local Config = require("BabyStorm.Config.BabyStormConfig")
local BabyStormController = require("BabyStorm.BabyStormController")
local VacuumSuctionDriver = require("BabyStorm.Core.Drivers.VacuumSuctionDriver")
local MathX = require("Util.MathX")
local RoleUtil = require("Util.RoleUtil")
local Log = require("Util.Log")

---@class HandheldVacuumRuntime
---@field application GameApplication|nil
---@field config HandheldVacuumConfig
---@field vacuum Obstacle|Unit|nil
---@field cleaners table
---@field suction VacuumSuctionDriver
---@field lifting_role Role|nil
---@field active boolean
local HandheldVacuumRuntime = Class("HandheldVacuumRuntime")

---@param application GameApplication|nil
function HandheldVacuumRuntime:Ctor(application)
    self.application = application
    self.config = Config.handheld_vacuum
    self.vacuum = nil
    self.cleaners = {}
    self.suction = VacuumSuctionDriver.New()
    self.lifting_role = nil
    self.active = false
end

---@return boolean
function HandheldVacuumRuntime:start()
    if not self.application then
        Log.warn("handheld vacuum triggers not bound: no application")
        return false
    end

    local ok, vacuum = pcall(function()
        return GameAPI.create_obstacle(
            self.config.prefab_id,
            MathX.to_vector3(self.config.spawn_pos),
            math.Quaternion(0.0, 0.0, 0.0),
            math.Vector3(1.0, 1.0, 1.0),
            nil
        )
    end)
    if not (ok and vacuum) then
        Log.warn("handheld vacuum create failed", self.config.prefab_id, tostring(vacuum))
        return false
    end
    self.vacuum = vacuum

    local manager = BabyStormController.get_manager()
    self.cleaners = manager and manager:get_vacuum_cleaners() or {}
    if #self.cleaners == 0 then
        Log.warn("handheld vacuum cleaners unavailable")
    end

    self.application.register_unit_trigger(
        self.vacuum,
        { EVENT.SPEC_OBSTACLE_LIFTED_BEGIN },
        function(_, _, data)
            self:_on_lift_begin(data)
        end
    )
    self.application.register_unit_trigger(
        self.vacuum,
        { EVENT.SPEC_OBSTACLE_LIFTED_END },
        function(_, _, data)
            self:_on_lift_end(data)
        end
    )

    Log.info("handheld vacuum ready", self.config.prefab_id)
    return true
end

---@param data table|nil
function HandheldVacuumRuntime:_on_lift_begin(data)
    if self.active then
        return
    end
    self.active = true
    local lift_unit = data and data.lift_unit or nil
    self.lifting_role = RoleUtil.get_role_by_unit(lift_unit)
    if #self.cleaners > 0 then
        self.suction:start({
            source = self.vacuum,
            cleaners = self.cleaners,
            pull_radius = self.config.pull_radius,
            destroy_radius = self.config.destroy_radius,
            pull_speed = self.config.pull_speed,
        })
    end
    self:_emit(self.config.pick_up_event, lift_unit)
    Log.info("handheld vacuum started", RoleUtil.get_role_id(self.lifting_role) or "unknown")
end

---@param data table|nil
function HandheldVacuumRuntime:_on_lift_end(data)
    if not self.active then
        return
    end
    self.active = false
    local lift_unit = data and data.lift_unit or nil
    local role = RoleUtil.get_role_by_unit(lift_unit) or self.lifting_role
    self.suction:stop()
    self.lifting_role = role
    self:_emit(self.config.put_down_event, lift_unit)
    Log.info("handheld vacuum stopped", RoleUtil.get_role_id(role) or "unknown")
    self.lifting_role = nil
end

---@param event_name string
---@param lift_unit Unit|LifeEntity|nil
function HandheldVacuumRuntime:_emit(event_name, lift_unit)
    local payload = {
        role = self.lifting_role,
        role_id = RoleUtil.get_role_id(self.lifting_role),
        vacuum = self.vacuum,
        lift_unit = lift_unit,
    }
    LuaAPI.unit_send_custom_event(self.vacuum, event_name, payload)
    LuaAPI.global_send_custom_event(event_name, payload)
end

function HandheldVacuumRuntime:destroy()
    if self.active then
        self.active = false
        self.suction:stop()
        self:_emit(self.config.put_down_event, nil)
    end
    if self.vacuum then
        pcall(function() GameAPI.destroy_unit(self.vacuum) end)
    end
    self.lifting_role = nil
    self.cleaners = {}
    self.vacuum = nil
    self.application = nil
end

---@class HandheldVacuumController: GameController
local HandheldVacuumController = {}

---@type HandheldVacuumRuntime|nil
local runtime = nil

---@param application GameApplication|nil
---@return HandheldVacuumRuntime
function HandheldVacuumController.init(application)
    if runtime then
        return runtime
    end

    runtime = HandheldVacuumRuntime.New(application)
    runtime:start()
    return runtime
end

---@param application GameApplication|nil
function HandheldVacuumController.destroy(application)
    if runtime then
        runtime:destroy()
        runtime = nil
    end
end

return HandheldVacuumController
