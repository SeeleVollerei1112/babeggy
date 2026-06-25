local Class = require("BaseClass")
local TaskEvents = require("Util.TaskEvents")

local TaskEventService = Class("TaskEventService")

function TaskEventService:Ctor()
end

function TaskEventService:_emit_for_agent(agent, event_name, extra)
    if agent.last_role then
        TaskEvents.emit(agent.last_role, event_name, extra)
    else
        TaskEvents.emit_all(event_name, extra)
    end
end

function TaskEventService:emit_lift_baby(agent)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.LIFT_BABY, {
        baby = agent.unit,
        lift_unit = agent.last_lift_unit,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = 1,
    })
end

function TaskEventService:emit_need_matched(agent, item)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.NEED_MATCHED, {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = 1,
    })
end

function TaskEventService:emit_baby_pick_item(agent, item, count)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.BABY_PICK_ITEM, {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = count or 1,
    })
end

function TaskEventService:emit_wrong_item(agent, item)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.WRONG_ITEM, {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = 1,
    })
end

function TaskEventService:emit_baby_satisfied(agent, item)
    self:_emit_for_agent(agent, TaskEvents.EVENTS.BABY_SATISFIED, {
        baby = agent.unit,
        item_id = item and item.def.item_key or nil,
        need = agent.current_need and agent.current_need.need_text or nil,
        amount = 1,
    })
end

return TaskEventService
