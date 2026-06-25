local Class = require("BaseClass")
local ViewBinding = require("MVVM.ViewBinding")
local BabyViewModel = require("BabyStorm.Domain.BabyViewModel")
local UINodes = require("Data.UINodes")

local BabySceneView = Class("BabySceneView")

function BabySceneView:Ctor(config)
    self.config = config
    self._bindings = {}
end

function BabySceneView:attach_agent(agent)
    self:_create_scene_ui(agent)

    local binding = ViewBinding.New()
    binding:bind_one_way(agent.view_model, BabyViewModel.Field.StatusText, function()
        self:_refresh_status(agent)
    end, true)

    self._bindings[#self._bindings + 1] = { agent = agent, binding = binding }
end

function BabySceneView:_create_scene_ui(agent)
    local canvas = self.config.scene_ui.reaction_canvas
    if not (canvas and agent.unit and agent.unit.create_scene_ui_bind_unit) then
        return
    end

    agent.scene_ui = agent.unit.create_scene_ui_bind_unit(
        canvas,
        Enums.ModelSocket.socket_head,
        math.Vector3(0, self.config.baby.status_height, 0),
        999999.0,
        true,
        true
    )
end

function BabySceneView:_set_all_role_scene_label(layer, text)
    if not layer then
        return
    end

    local label = GameAPI.get_eui_node_at_scene_ui(layer, UINodes.reaction_bubble_lbl)
    if not label then
        return
    end

    local roles = GameAPI.get_all_valid_roles() or {}
    for index = 1, #roles do
        local role = roles[index]
        if role.set_label_text then
            role.set_label_text(label, text)
        end
    end
end

function BabySceneView:_refresh_status(agent)
    local text = agent.view_model:get_status_text()
    self:_set_all_role_scene_label(agent.scene_ui, text)

    if agent.unit and agent.unit.show_bubble_msg and text and text ~= "" then
        agent.unit.show_bubble_msg(text, 2.0, 20.0, math.Vector3(0, self.config.baby.status_height, 0))
    end
end

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
