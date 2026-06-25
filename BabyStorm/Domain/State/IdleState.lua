local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")

local IdleState = Class("BabyIdleState", StateBase)

function IdleState:Ctor(agent)
    IdleState.super.Ctor(self, agent)
end

function IdleState:enter(context)
    IdleState.super.enter(self, context)
    local agent = self.agent
    agent:set_busy(false)
    agent:set_lift_enabled(true)
    agent:show_current_need()
    agent:start_patrol()
end

return IdleState
