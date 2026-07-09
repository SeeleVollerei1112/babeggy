local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Timer = require("BabyStorm.Core.Timer")
local Rand = require("Util.Rand")
local Log = require("Util.Log")

local SeatInteraction = require("BabyStorm.Domain.Interaction.SeatInteraction")
local SwingInteraction = require("BabyStorm.Domain.Interaction.SwingInteraction")
local CatapultInteraction = require("BabyStorm.Domain.Interaction.CatapultInteraction")
local CribInteraction = require("BabyStorm.Domain.Interaction.CribInteraction")
local VehicleInteraction = require("BabyStorm.Domain.Interaction.VehicleInteraction")
local PlayerBoundInteraction = require("BabyStorm.Domain.Interaction.PlayerBoundInteraction")

-- 在设施处交互。按 facility_kind 装载 Interaction 子状态（木偶戏——座位跟随、施力、
-- 巡游、骑手跟随——全部在子状态 + Driver 内），本状态负责：
--   * 占用设施（active_facility / facility.active_agent）与四字段意图声明；
--   * 时长结算：Timer.once(owner=self)，状态 exit 即取消——中途被抱走/打断不会再有
--     旧设施定时器触发完成结算（修历史无主定时器 bug）；
--   * 交互 begin/end 自定义事件（经 FacilityRegistry 发送）；
--   * exit 统一收尾：子状态 exit（停驱动/动画/恢复碰撞）→ 释放占用 → 发 end 事件。
--     完成（Satisfied）/失败（Upset）/哭闹（Cry）切状态时自动走到这里，无需各处手动清理。
--
-- 等待型交互（滑板等玩家上板 / 婴儿床等换洗 / 投石车等发射）不按时长结算，
-- 由子状态或外部服务经 agent:complete_facility_interaction / fail_facility_interaction 推进。
---@class InteractingFacilityState: StateBase
---@field _facility BabyFacilityRecord|nil
---@field _sub InteractionBase|nil
local InteractingFacilityState = Class("BabyInteractingFacilityState", StateBase)

---@param agent BabyAgent
function InteractingFacilityState:Ctor(agent)
    InteractingFacilityState.super.Ctor(self, agent)
    self._facility = nil
    self._sub = nil
end

---@param def BabyNeedDef
---@return InteractionBase
local function interaction_class_for(def)
    if def.facility_kind == "vehicle" then
        if def.vehicle_drive_mode == "player_bound" then
            return PlayerBoundInteraction
        end
        return VehicleInteraction
    elseif def.facility_kind == "swing_seat" then
        return SwingInteraction
    elseif def.facility_kind == "catapult" then
        return CatapultInteraction
    elseif def.facility_kind == "crib" then
        return CribInteraction
    end
    return SeatInteraction
end

-- 必须返回 Fixed（小数）：该值会作为定时器间隔使用，传整数会被当成 0 立即触发。
---@param def BabyNeedDef
---@return Fixed
local function roll_duration(def)
    local min_seconds = def.interact_min_seconds or 20
    local max_seconds = def.interact_max_seconds or 60
    if max_seconds < min_seconds then
        max_seconds = min_seconds
    end
    return Rand.int(min_seconds, max_seconds) + 0.0
end

---@param context BabyStateContext|nil
function InteractingFacilityState:enter(context)
    InteractingFacilityState.super.enter(self, context)
    self._facility = nil
    self._sub = nil

    local agent = self.agent
    local facility = context and context.facility or nil
    if not facility then
        agent:enter_upset({ reason = "missing_facility" })
        return
    end
    if facility.active_agent and facility.active_agent ~= agent then
        agent:enter_upset({ item = facility, reason = "facility_busy" })
        return
    end

    agent:set_busy(true)
    agent:set_lift_enabled(false)
    agent:set_status(agent.services.resolver:get_match_text(agent.current_need, facility))
    agent.services.task:emit_delivery(agent, facility, context and context.delivery_method or nil)

    -- 占用设施 + 交互上下文
    facility.active_agent = agent
    agent.active_facility = facility
    self._facility = facility
    -- 互动已开始（需求已匹配），停止耐心倒计时：否则秋千这类长互动（20~60s）
    -- 会被需求超时（20~30s）打断，触发 Cry 并刷新成另一个需求。
    agent:cancel_need_countdown()

    local def = facility.def
    local duration = roll_duration(def)
    self._sub = interaction_class_for(def).New(agent, facility)
    self:set_intent(self._sub:get_intent())
    self._sub:enter(duration)
    agent.services.facility:send_interaction_event(def.interact_begin_event, agent, facility, duration)
    Log.info("facility begin", def.id, "baby", agent.index, "duration", duration)

    -- 时长结算：owner=self，状态 exit 即取消（等待型交互由子状态/外部服务推进结算）。
    if self._sub:is_timed() then
        Timer.once(self, duration, function()
            agent:complete_facility_interaction(facility)
        end)
    end
end

---@param event table
function InteractingFacilityState:handle_event(event)
    if self._sub then
        self._sub:handle_event(event)
    end
end

---@param context BabyStateContext|nil
function InteractingFacilityState:exit(context)
    local agent = self.agent
    local facility = self._facility
    if facility then
        if self._sub then
            self._sub:exit()
            self._sub = nil
        end
        facility.active_agent = nil
        if agent.active_facility == facility then
            agent.active_facility = nil
        end
        agent.services.facility:send_interaction_event(facility.def.interact_end_event, agent, facility, 0)
        Log.info("facility end", facility.def.id, "baby", agent.index)
        self._facility = nil
    end
    InteractingFacilityState.super.exit(self, context)
end

return InteractingFacilityState
