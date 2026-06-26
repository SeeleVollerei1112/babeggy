local TaskEvents = {}

---@class TaskEventPayload
---@field role Role|nil
---@field role_id RoleID|integer|nil
---@field baby Unit|LifeEntity|nil
---@field lift_unit Unit|nil
---@field item_id integer|nil
---@field need string|nil
---@field amount integer|nil

---@type table<string, string>
TaskEvents.EVENTS = {
    LIFT_BABY = "TASK_LIFT_BABY",
    NEED_MATCHED = "TASK_BABY_NEED_MATCHED",
    BABY_PICK_ITEM = "TASK_BABY_PICK_ITEM",
    BABY_SATISFIED = "TASK_BABY_SATISFIED",
    WRONG_ITEM = "TASK_BABY_WRONG_ITEM", -- 不是宝宝想要的：放下宝宝时附近只有不对的物品
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
