local GameApp = require("App.GameApp")

---@param event_name string|nil
---@param actor any
---@param data any
local function on_game_init(event_name, actor, data)
    GameApp.init()
end

---@param event_name string|nil
---@param actor any
---@param data any
local function on_game_end(event_name, actor, data)
    GameApp.destroy()
end

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, on_game_init)
LuaAPI.global_register_trigger_event({ EVENT.GAME_END }, on_game_end)
