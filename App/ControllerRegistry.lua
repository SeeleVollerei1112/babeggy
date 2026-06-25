local ControllerRegistry = {}

ControllerRegistry.controllers = {
    require("BabyStorm.BabyStormController"),
}

function ControllerRegistry.init(application)
    for index = 1, #ControllerRegistry.controllers do
        local controller = ControllerRegistry.controllers[index]
        if controller.init then
            controller.init(application)
        end
    end
end

function ControllerRegistry.destroy(application)
    for index = #ControllerRegistry.controllers, 1, -1 do
        local controller = ControllerRegistry.controllers[index]
        if controller.destroy then
            controller.destroy(application)
        end
    end
end

return ControllerRegistry
