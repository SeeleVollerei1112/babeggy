local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")

---@class SeekingItemState: StateBase
local SeekingItemState = Class("BabySeekingItemState", StateBase)

---@param agent BabyAgent
function SeekingItemState:Ctor(agent)
    SeekingItemState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
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

    if context and context.reason == "wrong_item" then
        -- 不是宝宝想要的：走过去捡起来，稍后丢掉（不算匹配，不发匹配/拾取任务事件）
        agent:set_status("捡起来看看")
        agent:command_pickup(item, "reject")
        return
    end

    agent:set_status(agent.services.resolver:get_match_text(agent.current_need, item))
    agent.services.task:emit_need_matched(agent, item)
    agent:command_pickup(item, "satisfy")
end

---@param context BabyStateContext|nil
function SeekingItemState:exit(context)
    SeekingItemState.super.exit(self, context)
end

return SeekingItemState
