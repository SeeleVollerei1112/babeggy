local ControllerRegistry = require("App.ControllerRegistry")
local PlayerSessionRegistry = require("App.PlayerSessionRegistry")
local TriggerRegistry = require("App.TriggerRegistry")
local Log = require("Util.Log")

local GameApp = {}

local application = {
    started = false,
    triggers = TriggerRegistry.New(),
    sessions = PlayerSessionRegistry.New(),
}

local function register_global_trigger(event_spec, callback)
    return application.triggers:global(event_spec, callback)
end

local function register_unit_trigger(unit, event_spec, callback)
    return application.triggers:unit(unit, event_spec, callback)
end

application.register_global_trigger = register_global_trigger
application.register_unit_trigger = register_unit_trigger

function GameApp.init()
    if application.started then
        return
    end

    application.started = true
    application.sessions:sync_all()
    Log.info("init")
    ControllerRegistry.init(application)
end

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
