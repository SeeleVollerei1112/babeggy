local Class = require("BaseClass")
local TaskEvents = require("Util.TaskEvents")
local Timer = require("BabyStorm.Core.Timer")

---@class TaskEventService
local TaskEventService = Class("TaskEventService")

function TaskEventService:Ctor()
end

---@param agent BabyAgent
---@param event_name string
---@param extra TaskEventPayload|table|nil
function TaskEventService:_emit_for_agent(agent, event_name, extra)
    if agent.last_role then
        TaskEvents.emit(agent.last_role, event_name, extra)
    else
        TaskEvents.emit_all(event_name, extra)
    end
end

---@param agent BabyAgent
---@param event_name string
---@param extra TaskEventPayload|table|nil
---@param delay Fixed
function TaskEventService:_emit_for_agent_after(agent, event_name, extra, delay)
    local role = agent.last_role
    -- owner=agent：agent destroy 时 Timer 的 owner_dead 检查自动失效，无需手写 agent.destroyed 守卫。
    Timer.once(agent, delay, function()
        if role then
            TaskEvents.emit(role, event_name, extra)
        else
            TaskEvents.emit_all(event_name, extra)
        end
    end)
end

---@param agent BabyAgent
---@return boolean
function TaskEventService:_is_facility_need(agent)
    return agent.services
        and agent.services.resolver
        and agent.services.resolver:is_facility_need(agent.current_need)
        or false
end

---@param agent BabyAgent
function TaskEventService:emit_lift_baby(agent)
    local need_type = self:_is_facility_need(agent) and "facility" or "item"
    local payload = {
        baby = agent.unit,
        lift_unit = agent.last_lift_unit,
        need = agent.current_need and agent.current_need.need_text or nil,
        need_type = need_type,
        amount = 1,
    }
    self:_emit_for_agent(agent, TaskEvents.EVENTS.LIFT_BABY, payload)

    local typed_event = need_type == "facility"
        and TaskEvents.EVENTS.LIFT_BABY_WANTS_FACILITY
        or TaskEvents.EVENTS.LIFT_BABY_WANTS_ITEM
    self:_emit_for_agent_after(agent, typed_event, payload, 1.5)
end

---@param agent BabyAgent
---@param item BabyItemRecord
function TaskEventService:emit_deliver_baby_to_item(agent, item)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.DELIVER_BABY_TO_ITEM, {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = 1,
    })
end

---@param agent BabyAgent
---@param item BabyItemRecord
function TaskEventService:emit_deliver_item_to_baby(agent, item)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.DELIVER_ITEM_TO_BABY, {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = 1,
    })
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function TaskEventService:emit_deliver_baby_to_facility(agent, facility)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.DELIVER_BABY_TO_FACILITY, {
        baby = agent.unit,
        item_id = facility and facility.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = 1,
    })
end

---@param agent BabyAgent
---@param target BabyItemRecord|BabyFacilityRecord
---@param delivery_method string|nil
function TaskEventService:emit_delivery(agent, target, delivery_method)
    if delivery_method == "baby_to_item" then
        self:emit_deliver_baby_to_item(agent, target)
    elseif delivery_method == "item_to_baby" then
        self:emit_deliver_item_to_baby(agent, target)
    elseif delivery_method == "baby_to_facility" then
        self:emit_deliver_baby_to_facility(agent, target)
    else
        self:emit_need_matched(agent, target)
    end
end

---@param agent BabyAgent
---@param item BabyItemRecord|BabyFacilityRecord|nil
function TaskEventService:emit_need_matched(agent, item)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.NEED_MATCHED, {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = 1,
    })
end

---@param agent BabyAgent
---@param item BabyItemRecord|nil
---@param count integer|nil
function TaskEventService:emit_baby_pick_item(agent, item, count)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.BABY_PICK_ITEM, {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = count or 1,
    })
end

---@param agent BabyAgent
---@param item BabyItemRecord|BabyFacilityRecord|nil
function TaskEventService:emit_wrong_item(agent, item)
    local payload = {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = 1,
    }
    self:_emit_for_agent(agent, TaskEvents.EVENTS.WRONG_ITEM, payload)
    self:_emit_for_agent_after(agent, TaskEvents.EVENTS.NOT_WANTED_ITEM, payload, 1.5)
end

---@param agent BabyAgent
---@param item BabyItemRecord|BabyFacilityRecord|nil
function TaskEventService:emit_baby_satisfied(agent, item)
    local need_type = self:_is_facility_need(agent) and "facility" or "item"
    local payload = {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        need_type = need_type,
        amount = 1,
    }
    self:_emit_for_agent(agent, TaskEvents.EVENTS.BABY_SATISFIED, payload)

    local typed_event = need_type == "facility"
        and TaskEvents.EVENTS.BABY_SATISFIED_FACILITY
        or TaskEvents.EVENTS.BABY_SATISFIED_ITEM
    self:_emit_for_agent_after(agent, typed_event, payload, 1.5)
end

---@param agent BabyAgent
---@param item BabyItemRecord|BabyFacilityRecord|nil
function TaskEventService:emit_baby_happy(agent, item)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.BABY_HAPPY, {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = 1,
    })
end

return TaskEventService
