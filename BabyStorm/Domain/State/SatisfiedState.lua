local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")

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
    agent:cancel_need_countdown()
    agent:set_busy(true)
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
        LuaAPI.call_delay_time(result_delay, function()
            if agent:is_in_state(agent.enum.BabyState.Satisfied) then
                agent.services.task:emit_baby_satisfied(agent, target)
            end
        end)
        LuaAPI.call_delay_time(happy_delay, function()
            if agent:is_in_state(agent.enum.BabyState.Satisfied) then
                agent.services.task:emit_baby_happy(agent, target)
            end
        end)
        agent.services.score:award_satisfied(agent.last_role)
        if agent.services.difficulty then
            agent.services.difficulty:on_baby_satisfied(agent)
        end
    else
        agent:set_status("满足了")
    end

    local finish_delay = agent.config.baby.satisfied_react_time
    local minimum_finish_delay = item and 6.5 or 5.0
    if target and finish_delay < minimum_finish_delay then
        finish_delay = minimum_finish_delay
    end
    LuaAPI.call_delay_time(finish_delay, function()
        if agent:is_in_state(agent.enum.BabyState.Satisfied) then
            if facility then
                agent:finish_facility_satisfied(facility)
            else
                agent:finish_satisfied(item)
            end
        end
    end)
end

return SatisfiedState
