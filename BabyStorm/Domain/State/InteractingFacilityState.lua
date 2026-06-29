local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")

-- 在设施处交互（秋千 / 滑板）。座位 / 骑乘姿势与「ride」移动锁由 FacilityService 拥有，
-- 本状态只负责：声明停步意图、开始交互、按时长结算（玩家绑定型则等 FacilityService 轮询）。
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
    -- 停步；座位/骑乘动作由 FacilityService 强制播放，本状态不碰动画。
    self:set_intent({
        move_mode = Intent.MoveMode.Stop,
        anim_base = Intent.AnimBase.Idle,
        action_lock = false,
    })
    agent:set_status(agent.services.resolver:get_match_text(agent.current_need, facility))
    agent.services.task:emit_delivery(agent, facility, context and context.delivery_method or nil)

    local duration = agent.services.facility:begin_interaction(agent, facility)
    if not duration then
        agent:enter_upset({ item = facility, reason = "facility_busy" })
        return
    end
    agent.active_facility = facility
    -- 互动已开始（需求已匹配），停止耐心倒计时：否则秋千这类长互动（20~60s）
    -- 会被需求超时（20~30s）打断，触发 Cry 并刷新成另一个需求。
    agent:cancel_need_countdown()

    -- 滑板由玩家的组件交互驱动，宝宝在此等待玩家上板（FacilityService 轮询结算）。
    if agent.services.facility:is_player_bound(facility) then
        agent:set_status("等待玩家上滑板")
        return
    end

    LuaAPI.call_delay_time(duration, function()
        if agent:is_in_state(agent.enum.BabyState.InteractingFacility) then
            agent:complete_facility_interaction(facility)
        end
    end)
end

return InteractingFacilityState
