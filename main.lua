local GameApp = require("App.GameApp")

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    GameApp.init()
end)

LuaAPI.global_register_trigger_event({ EVENT.GAME_END }, function()
    GameApp.destroy()
end)
