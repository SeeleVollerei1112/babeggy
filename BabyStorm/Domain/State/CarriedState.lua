local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")

---@class CarriedState: StateBase
local CarriedState = Class("BabyCarriedState", StateBase)

---@param agent BabyAgent
function CarriedState:Ctor(agent)
    CarriedState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
function CarriedState:enter(context)
    CarriedState.super.enter(self, context)
    local agent = self.agent
    agent:set_busy(true)
    agent:cancel_patrol()
    agent:stop_movement()
    agent.last_lift_unit = context and context.lift_unit or nil
    agent.last_role = context and context.role or nil
    agent:show_current_need()
    if not (context and context.suppress_lift_event) then
        agent.services.task:emit_lift_baby(agent)
    end
end

return CarriedState
