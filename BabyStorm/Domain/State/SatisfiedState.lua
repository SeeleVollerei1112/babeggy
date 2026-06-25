local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")

local SatisfiedState = Class("BabySatisfiedState", StateBase)

function SatisfiedState:Ctor(agent)
    SatisfiedState.super.Ctor(self, agent)
end

function SatisfiedState:enter(context)
    SatisfiedState.super.enter(self, context)
    local agent = self.agent
    local item = context and context.item or nil
    agent:set_busy(true)
    agent:set_lift_enabled(false)
    agent:stop_movement()
    agent:select_equipped_slot()

    if item then
        agent:set_status(agent.services.resolver:get_satisfied_text(agent.current_need, item))
        agent.services.task:emit_baby_satisfied(agent, item)
        agent.services.score:award_satisfied(agent.last_role)
        if agent.services.difficulty then
            agent.services.difficulty:on_baby_satisfied(agent)
        end
    else
        agent:set_status("满足了")
    end

    LuaAPI.call_delay_time(agent.config.baby.satisfied_react_time, function()
        if agent:is_in_state(agent.enum.BabyState.Satisfied) then
            agent:finish_satisfied(item)
        end
    end)
end

return SatisfiedState
