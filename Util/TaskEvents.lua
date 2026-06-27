local TaskEvents = {}

---@class TaskEventPayload
---@field role Role|nil
---@field role_id RoleID|integer|nil
---@field baby Unit|LifeEntity|nil
---@field lift_unit Unit|nil
---@field item_id integer|nil
---@field need string|nil
---@field need_type "item"|"facility"|nil
---@field amount integer|nil

---@type table<string, string>
TaskEvents.EVENTS = {
    LIFT_BABY = "TASK_LIFT_BABY", -- 玩家举起宝宝蛋
    LIFT_BABY_WANTS_ITEM = "TASK_LIFT_BABY_WANTS_ITEM", -- 举起的宝宝当前想要物品/食物
    LIFT_BABY_WANTS_FACILITY = "TASK_LIFT_BABY_WANTS_FACILITY", -- 举起的宝宝当前想去设施玩
    DELIVER_BABY_TO_ITEM = "TASK_DELIVER_BABY_TO_ITEM", -- 将宝宝带到想要的物品旁并放下
    DELIVER_ITEM_TO_BABY = "TASK_DELIVER_ITEM_TO_BABY", -- 将宝宝想要的物品带到宝宝身边
    DELIVER_BABY_TO_FACILITY = "TASK_DELIVER_BABY_TO_FACILITY", -- 将宝宝带到目标设施旁并放下
    NEED_MATCHED = "TASK_BABY_NEED_MATCHED", -- 当前物品或设施与宝宝需求匹配
    BABY_PICK_ITEM = "TASK_BABY_PICK_ITEM", -- 宝宝已经拾取物品
    BABY_SATISFIED = "TASK_BABY_SATISFIED", -- 宝宝需求已满足（通用）
    BABY_SATISFIED_ITEM = "TASK_BABY_SATISFIED_ITEM", -- 宝宝对物品/食物感到满意
    BABY_SATISFIED_FACILITY = "TASK_BABY_SATISFIED_FACILITY", -- 宝宝完成设施游玩并感到满意
    BABY_HAPPY = "TASK_BABY_HAPPY", -- 宝宝进入开心状态，可用于完成任务
    WRONG_ITEM = "TASK_BABY_WRONG_ITEM", -- 宝宝确认拿到的不是想要的物品
    NOT_WANTED_ITEM = "TASK_BABY_NOT_WANTED_ITEM", -- 错误物品反馈结束，可跳回重新配送任务
}


---@param role Role|nil
---@return RoleID|integer|nil
local function get_role_id(role)
    if not role then
        return nil
    end
    if role.get_roleid then
        return role.get_roleid()
    end
    return nil
end

---@param role Role|nil
---@param event_name string|nil
---@param data TaskEventPayload|table|nil
local function send(role, event_name, data)
    if not role or not event_name then
        return
    end

    local unit = role.get_ctrl_unit and role.get_ctrl_unit()
    if not unit then
        return
    end

    LuaAPI.unit_send_custom_event(unit, event_name, data)
end

---@param role Role|nil
---@param event_name string
---@param extra TaskEventPayload|table|nil
function TaskEvents.emit(role, event_name, extra)
    local role_id = get_role_id(role)
    if not role_id then
        return
    end

    local data = {
        role = role,
        role_id = role_id,
    }

    if extra then
        for key, value in pairs(extra) do
            data[key] = value
        end
    end

    send(role, event_name, data)
    LuaAPI.log("[TaskEvents] emit " .. tostring(event_name) .. " role=" .. tostring(role_id), 0)
end

---@param event_name string
---@param extra TaskEventPayload|table|nil
function TaskEvents.emit_all(event_name, extra)
    local roles = GameAPI.get_all_valid_roles() or {}
    for index = 1, #roles do
        local role = roles[index]
        TaskEvents.emit(role, event_name, extra)
    end
end

return TaskEvents
