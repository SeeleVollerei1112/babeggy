local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")

---@class InteractingFacilityState: StateBase
local InteractingFacilityState = Class("BabyInteractingFacilityState", StateBase)

---@param agent BabyAgent
function InteractingFacilityState:Ctor(agent)
    InteractingFacilityState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
function InteractingFacilityState:enter(context)
    InteractingFacilityState.super.enter(self, context)
    local agent = self.agent
    local facility = context and context.facility or nil
    if not facility then
        agent:enter_upset({ reason = "missing_facility" })
        return
    end

    agent:set_busy(true)
    agent:set_lift_enabled(false)
    agent:stop_movement()
    agent:set_status(agent.services.resolver:get_match_text(agent.current_need, facility))
    agent.services.task:emit_need_matched(agent, facility)

    local duration = agent.services.facility:begin_interaction(agent, facility)
    if not duration then
        agent:enter_upset({ item = facility, reason = "facility_busy" })
        return
    end
    agent.active_facility = facility
    -- 互动已开始（需求已匹配），停止耐心倒计时：否则秋千这类长互动（20~60s）
    -- 会被需求超时（20~30s）打断，触发 Timeout 并刷新成另一个需求。
    agent:cancel_need_countdown()

    LuaAPI.call_delay_time(duration, function()
        if agent:is_in_state(agent.enum.BabyState.InteractingFacility) then
            agent:complete_facility_interaction(facility)
        end
    end)
end

return InteractingFacilityState

