local Class = require("BaseClass")
local UINodes = require("Data.UINodes")

-- 扫地机器人 HUD 表现。场景节点只允许 View 层持有，控制器只传入 Role。
--[[
现有静态 UI 层级（布局和样式由编辑器维护，本模块不创建节点）：
hud_canvas
└── robot_start_btn
    ├── “启动机器人”（可开始控制）
    └── “退出控制”（正在控制）
]]
---@class RobotVacuumView
---@field config RobotVacuumConfig
local RobotVacuumView = Class("RobotVacuumView")

local TOUCH_CLICK = 1

---@param config RobotVacuumConfig
function RobotVacuumView:Ctor(config)
    self.config = config
end

---@param role Role|nil
function RobotVacuumView:hide(role)
    if role and role.set_node_visible then
        role.set_node_visible(UINodes.robot_start_btn, false)
    end
end

---@param roles Role[]|nil
function RobotVacuumView:hide_all(roles)
    local list = roles or {}
    for index = 1, #list do
        self:hide(list[index])
    end
end

---@param application GameApplication|nil
---@param callback fun(role:Role)
---@return any
function RobotVacuumView:bind_start_button(application, callback)
    if not application then
        return nil
    end
    return application.register_global_trigger(
        { EVENT.EUI_NODE_TOUCH_EVENT, UINodes.robot_start_btn, TOUCH_CLICK },
        function(_, _, data)
            local role = data and data.role or nil
            if role then
                callback(role)
            end
        end
    )
end

---@param role Role|nil
function RobotVacuumView:show_ready(role)
    self:_show(role, self.config.ready_button_text)
end

---@param role Role|nil
function RobotVacuumView:show_controlling(role)
    self:_show(role, self.config.controlling_button_text)
end

---@param role Role|nil
---@param text string
function RobotVacuumView:_show(role, text)
    if not role then
        return
    end
    if role.set_button_text then
        role.set_button_text(UINodes.robot_start_btn, text)
    end
    if role.set_button_enabled then
        role.set_button_enabled(UINodes.robot_start_btn, true)
    end
    if role.set_node_visible then
        role.set_node_visible(UINodes.robot_start_btn, true)
    end
end

return RobotVacuumView
