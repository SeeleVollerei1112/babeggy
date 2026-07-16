local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")

-- 满足后的开心表现 + 结算事件，随后回到 Idle。
---@class SatisfiedState: StateBase
local SatisfiedState = Class("BabySatisfiedState", StateBase)

---@param agent BabyAgent
function SatisfiedState:Ctor(agent)
    SatisfiedState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
function SatisfiedState:enter(context)
    SatisfiedState.super.enter(self, context)
    local agent = self.agent
    local item = context and context.item or nil
    local facility = context and context.facility or nil
    local target = item or facility
    -- 玩具型满足：物品已在 PlayingToyState:exit 原地放下并留在场上，收尾时不能再吃掉它。
    local keep_item = (context and context.keep_item) and true or false
    agent:cancel_need_countdown()
    agent:set_lift_enabled(false)
    agent:select_equipped_slot()
    self:set_intent({
        move_mode = Intent.MoveMode.Stop,
        anim_base = Intent.AnimBase.Idle,
        anim_overlay = Intent.AnimOverlay.Happy,
        action_lock = false,
    })

    if target then
        agent:set_status(agent.services.resolver:get_satisfied_text(agent.current_need, target))
        local result_delay = item and 3.0 or 1.5
        local happy_delay = result_delay + 3.0
        -- 满意事件发出 1.5 秒后再发物品/设施分类事件，分类事件之后再等 1.5 秒发开心事件。
        -- owner=self：状态 exit 时 StateBase 统一取消，不会有过期回调。
        Timer.once(self, result_delay, function()
            agent.services.task:emit_baby_satisfied(agent, target)
        end)
        Timer.once(self, happy_delay, function()
            agent.services.task:emit_baby_happy(agent, target)
        end)
        agent.services.score:award_satisfied(agent.last_role)
        if agent.services.difficulty then
            agent.services.difficulty:on_baby_satisfied(agent)
        end
    else
        agent:set_status((context and context.status_text) or "满足了")
    end

    local finish_delay = agent.config.baby.satisfied_react_time
    local minimum_finish_delay = item and 6.5 or 5.0
    if target and finish_delay < minimum_finish_delay then
        finish_delay = minimum_finish_delay
    end
    Timer.once(self, finish_delay, function()
        if facility then
            agent:finish_facility_satisfied(facility)
        else
            agent:finish_satisfied(item, keep_item)
        end
    end)
end

return SatisfiedState
