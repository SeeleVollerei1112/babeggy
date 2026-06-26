local BabyAgentManager = require("BabyStorm.BabyAgentManager")

---@class BabyStormController: GameController
local BabyStormController = {}

---@type BabyAgentManager|nil
local manager = nil

---@param application GameApplication|nil
---@return BabyAgentManager|nil
function BabyStormController.init(application)
    if manager then
        return manager
    end

    manager = BabyAgentManager.New(application)
    if not manager:start() then
        manager = nil
    end
    return manager
end

---@param application GameApplication|nil
function BabyStormController.destroy(application)
    if manager then
        manager:destroy()
        manager = nil
    end
end

---@return BabyAgentManager|nil
function BabyStormController.get_manager()
    return manager
end

return BabyStormController
