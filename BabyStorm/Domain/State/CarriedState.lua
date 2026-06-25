local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")

local CarriedState = Class("BabyCarriedState", StateBase)

function CarriedState:Ctor(agent)
    CarriedState.super.Ctor(self, agent)
end

function CarriedState:enter(context)
    CarriedState.super.enter(self, context)
    local agent = self.agent
    agent:set_busy(true)
    agent:cancel_patrol()
    agent:stop_movement()
    agent.last_lift_unit = context and context.lift_unit or nil
    agent.last_role = context and context.role or nil
    agent:set_status("被抱起")
    agent.services.task:emit_lift_baby(agent)
end

return CarriedState
