---@export_plugin
local BabyStormController = require("BabyStorm.BabyStormController")

---@class BabyStormDebugPlugin
local Debug = {}

---@export_plugin
---@desc [BabyStorm] 启动玩法
---@return nil
function Debug.start()
    BabyStormController.init()
end

---@export_plugin
---@desc [BabyStorm] 停止玩法
---@return nil
function Debug.stop()
    BabyStormController.destroy()
end

---@export_plugin
---@desc [BabyStorm] 打印运行状态
---@return nil
function Debug.snapshot()
    local manager = BabyStormController.get_manager()
    if not manager then
        LuaAPI.log("[BabyStormDebug] manager=nil", 0)
        return
    end

    local snapshot = manager:get_debug_snapshot()
    LuaAPI.log(
        "[BabyStormDebug] started=" .. tostring(snapshot.started) ..
        " babies=" .. tostring(snapshot.baby_count) ..
        " players=" .. tostring(snapshot.player_count) ..
        " chaos=" .. tostring(snapshot.chaos_level) ..
        " satisfied=" .. tostring(snapshot.satisfied_count) ..
        " elapsed=" .. tostring(snapshot.elapsed_seconds) ..
        " remaining=" .. tostring(snapshot.remaining_seconds),
        0
    )
end

return Debug
