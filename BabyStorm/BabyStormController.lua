local BabyAgentManager = require("BabyStorm.BabyAgentManager")

local BabyStormController = {}

local manager = nil

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

function BabyStormController.destroy(application)
    if manager then
        manager:destroy()
        manager = nil
    end
end

function BabyStormController.get_manager()
    return manager
end

return BabyStormController
