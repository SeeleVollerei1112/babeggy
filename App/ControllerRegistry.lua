local ControllerRegistry = {}

---@class GameController
---@field init fun(application:GameApplication)|nil
---@field destroy fun(application:GameApplication)|nil

---@type GameController[]
ControllerRegistry.controllers = {
    require("BabyStorm.BabyStormController"),
}

---@param application GameApplication
function ControllerRegistry.init(application)
    for index = 1, #ControllerRegistry.controllers do
        local controller = ControllerRegistry.controllers[index]
        if controller.init then
            controller.init(application)
        end
    end
end

---@param application GameApplication
function ControllerRegistry.destroy(application)
    for index = #ControllerRegistry.controllers, 1, -1 do
        local controller = ControllerRegistry.controllers[index]
        if controller.destroy then
            controller.destroy(application)
        end
    end
end

return ControllerRegistry
