local ControllerRegistry = require("App.ControllerRegistry")
local PlayerSessionRegistry = require("App.PlayerSessionRegistry")
local TriggerRegistry = require("App.TriggerRegistry")
local Log = require("Util.Log")

---@class GameApplication
---@field started boolean
---@field triggers TriggerRegistry
---@field sessions PlayerSessionRegistry
---@field register_global_trigger fun(event_spec:TriggerEventSpec, callback:TriggerCallback):any
---@field register_unit_trigger fun(unit:Unit|LifeEntity|Equipment|nil, event_spec:TriggerEventSpec, callback:TriggerCallback):any

local GameApp = {}

---@type GameApplication
local application = {
    started = false,
    triggers = TriggerRegistry.New(),
    sessions = PlayerSessionRegistry.New(),
}

---@param event_spec TriggerEventSpec
---@param callback TriggerCallback
---@return any
local function register_global_trigger(event_spec, callback)
    return application.triggers:global(event_spec, callback)
end

---@param unit Unit|LifeEntity|Equipment|nil
---@param event_spec TriggerEventSpec
---@param callback TriggerCallback
---@return any
local function register_unit_trigger(unit, event_spec, callback)
    return application.triggers:unit(unit, event_spec, callback)
end

application.register_global_trigger = register_global_trigger
application.register_unit_trigger = register_unit_trigger

---@return nil
function GameApp.init()
    if application.started then
        return
    end

    application.started = true
    application.sessions:sync_all()
    Log.info("init")
    ControllerRegistry.init(application)
end

---@return nil
function GameApp.destroy()
    if not application.started then
        return
    end

    ControllerRegistry.destroy(application)
    application.triggers:destroy()
    application.triggers = TriggerRegistry.New()
    application.sessions:clear()
    application.sessions = PlayerSessionRegistry.New()
    application.started = false
    Log.info("destroy")
end

return GameApp
