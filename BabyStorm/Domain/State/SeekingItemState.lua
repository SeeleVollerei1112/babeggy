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
        -- 先推进到“宝宝挑选物品中”，实际捡起后再发拾取事件进入判断节点。
        agent:set_status("捡起来看看")
        agent.services.task:emit_delivery(agent, item, context.delivery_method)
        agent:command_pickup(item, "reject")
        return
    end

    agent:set_status(agent.services.resolver:get_match_text(agent.current_need, item))
    agent.services.task:emit_delivery(agent, item, context and context.delivery_method or nil)
    agent:command_pickup(item, "satisfy")
end

---@param context BabyStateContext|nil
function SeekingItemState:exit(context)
    SeekingItemState.super.exit(self, context)
end

return SeekingItemState
