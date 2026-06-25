local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")

local SeekingItemState = Class("BabySeekingItemState", StateBase)

function SeekingItemState:Ctor(agent)
    SeekingItemState.super.Ctor(self, agent)
end

function SeekingItemState:enter(context)
    SeekingItemState.super.enter(self, context)
    local agent = self.agent
    local item = context and context.item or nil
    if not item then
        agent:enter_upset({ reason = "missing_item" })
        return
    end

    agent:set_busy(true)
    agent:set_lift_enabled(false)
    agent.pending_item = item
    agent:set_status(agent.services.resolver:get_match_text(agent.current_need, item))
    agent.services.task:emit_need_matched(agent, item)
    agent:command_pickup(item)
end

function SeekingItemState:exit(context)
    SeekingItemState.super.exit(self, context)
end

return SeekingItemState
