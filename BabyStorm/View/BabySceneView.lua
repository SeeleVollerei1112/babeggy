local Class = require("BaseClass")
local ViewBinding = require("MVVM.ViewBinding")
local BabyViewModel = require("BabyStorm.Domain.BabyViewModel")

---@class BabySceneBinding
---@field agent BabyAgent
---@field binding ViewBinding

---@class BabySceneView
---@field config BabyStormConfig
---@field _bindings BabySceneBinding[]
local BabySceneView = Class("BabySceneView")

---@param config BabyStormConfig
function BabySceneView:Ctor(config)
    self.config = config
    self._bindings = {}
end

---@param agent BabyAgent
function BabySceneView:attach_agent(agent)
    local binding = ViewBinding.New()
    binding:bind_one_way(agent.view_model, BabyViewModel.Field.StatusText, function()
        self:_refresh_status(agent)
    end, true)

    self._bindings[#self._bindings + 1] = { agent = agent, binding = binding }
end

---@param agent BabyAgent
function BabySceneView:_refresh_status(agent)
    local text = agent.view_model:get_status_text()
    if not agent.unit then
        return
    end

    if (not text or text == "") and agent.unit.hide_bubble_msg then
        agent.unit.hide_bubble_msg()
        return
    end

    if agent.unit.show_bubble_msg and text and text ~= "" then
        local show_time = self.config.baby.bubble_show_seconds or 999999.0
        agent.unit.show_bubble_msg(text, show_time, 20.0, math.Vector3(0, self.config.baby.status_height, 0))
    end
end

---@return nil
function BabySceneView:destroy()
    for index = #self._bindings, 1, -1 do
        local binding = self._bindings[index].binding
        if binding then
            binding:destroy()
        end
    end
    self._bindings = {}
end

return BabySceneView
