local Class = require("BaseClass")
local Enum = require("BabyStorm.Config.BabyStormEnum")
local Intent = require("BabyStorm.Domain.BabyIntent")
local BabyViewModel = require("BabyStorm.Domain.BabyViewModel")
local ActionLock = require("BabyStorm.Domain.System.ActionLock")
local MovementSystem = require("BabyStorm.Domain.System.MovementSystem")
local AnimationSystem = require("BabyStorm.Domain.System.AnimationSystem")
local NeedRuntime = require("BabyStorm.Domain.System.NeedRuntime")
local RoleUtil = require("Util.RoleUtil")
local Log = require("Util.Log")

-- 宝宝个体协调器（重构后）。
--
-- 职责：持有五个子系统 + 行为状态机，按 tick 串起单向数据流：
--   NeedRuntime -> BehaviorFSM(状态) -> MovementSystem -> AnimationSystem。
-- 本文件**不再**直接调用移动/动画引擎 API（除装备槽/举起开关等非移动非动画的小开关）。
-- 见 .claude/rules/baby-ai-architecture.md。
--
-- 行为层向子系统下发的意图字段：move_mode / anim_base / anim_overlay / anim_param。
-- 动作锁统一为 self.action_lock（reason: "behavior" 行为锁 / "ride" 骑乘 / "hold" 放下冻结）。

---@class BabyStateContext
---@field item BabyItemRecord|nil
---@field facility BabyFacilityRecord|nil
---@field lift_unit Unit|nil
---@field role Role|nil
---@field reason string|nil
---@field status_text string|nil
---@field suppress_lift_event boolean|nil
---@field delivery_method "baby_to_item"|"item_to_baby"|"baby_to_facility"|nil

---@class BabyAgent
---@field index integer
---@field unit LifeEntity|Unit
---@field services BabyServices
---@field config BabyStormConfig
---@field enum BabyStormEnum|table
---@field view_model BabyViewModel
---@field action_lock ActionLock
---@field movement MovementSystem
---@field animation AnimationSystem
---@field need_runtime NeedRuntime
---@field move_mode string
---@field anim_base string
---@field anim_overlay string|nil
---@field anim_param BabyAnimParam|nil
---@field move_target Vector3|nil
---@field pickup_target BabyItemRecord|nil
---@field states table<integer, StateBase>
---@field state_list StateBase[]
---@field active_state StateBase|nil
---@field current_need BabyNeedDef|nil
---@field last_role Role|nil
---@field last_lift_unit Unit|nil
---@field pending_item BabyItemRecord|nil
---@field pending_purpose "satisfy"|"reject"|nil
---@field is_rejecting boolean
---@field need_timeout_bonus_seconds integer
---@field timeout_action_bonus_seconds integer
---@field active_facility BabyFacilityRecord|nil
---@field _hold_remaining Fixed
---@field destroyed boolean
local BabyAgent = Class("BabyAgent")

---@param index integer
---@param unit LifeEntity|Unit
---@param services BabyServices
---@param config BabyStormConfig
function BabyAgent:Ctor(index, unit, services, config)
    self.index = index
    self.unit = unit
    self.services = services
    self.config = config
    self.enum = Enum
    self.view_model = BabyViewModel.New()

    -- 子系统
    self.action_lock = ActionLock.New(unit)
    self.movement = MovementSystem.New(self)
    self.animation = AnimationSystem.New(self)
    self.need_runtime = NeedRuntime.New()

    -- 意图字段（默认停 + 待机）
    self.move_mode = Intent.MoveMode.Stop
    self.anim_base = Intent.AnimBase.Idle
    self.anim_overlay = nil
    self.anim_param = nil
    self.move_target = nil
    self.pickup_target = nil

    -- 状态机
    self.states = {}
    self.state_list = {}
    self.active_state = nil

    -- 需求 / 交互上下文
    self.current_need = nil
    self.last_role = nil
    self.last_lift_unit = nil
    self.pending_item = nil
    self.pending_purpose = nil
    self.is_rejecting = false
    self.need_timeout_bonus_seconds = 0
    self.timeout_action_bonus_seconds = 0
    self.active_facility = nil

    self._hold_remaining = 0.0
    self.destroyed = false
end

---@return boolean
function BabyAgent:init()
    if not self.unit then
        return false
    end

    self:_configure_unit()
    self.services.view:attach_agent(self)
    self:choose_next_need()
    self:enter_idle()
    return true
end

---@private
function BabyAgent:_configure_unit()
    if not self.unit then
        return
    end
    if self.unit.set_lifted_enabled then
        self.unit.set_lifted_enabled(true)
    end
    if self.unit.set_ai_move_threshold then
        self.unit.set_ai_move_threshold(self.config.baby.ai_move_threshold)
    end
    if self.unit.set_equipment_max_count then
        self.unit.set_equipment_max_count(Enums.EquipmentSlotType.EQUIPPED, 1)
    end
end

-- ============================================================
-- 每帧 tick：单向数据流的串联点（由 BabyAgentManager 统一驱动）。
-- ============================================================

---@param dt Fixed
function BabyAgent:update(dt)
    if self.destroyed then
        return
    end

    -- 1. 需求倒计时
    if self.current_need and self.need_runtime:is_active() then
        local evt = self.need_runtime:update(dt)
        if evt.timed_out then
            self:enter_state(Enum.BabyState.Cry, { reason = "need_timeout" }, true)
            return
        elseif evt.ticked then
            if self:is_in_state(Enum.BabyState.Idle) or self:is_in_state(Enum.BabyState.Carried) then
                self:set_status(self:_format_need_countdown(self.need_runtime:get_remaining()))
            end
        end
    end

    -- 2. 放下冻结计时
    self:_update_hold(dt)

    -- 3. 行为状态 phase 推进
    if self.active_state and self.active_state:is_active() then
        self.active_state:update(dt)
    end

    -- 4. 唯一改位置处
    self.movement:reconcile(dt)
    -- 5. 唯一播动画处
    self.animation:reconcile(dt)
    -- 6. 表现层由 ViewModel 绑定被动刷新（set_status 即触发），无需在此轮询
end

-- 强制 Movement / Animation 下一帧按当前意图重新对齐。
function BabyAgent:invalidate_systems()
    self.movement:invalidate()
    self.animation:invalidate()
end

-- ============================================================
-- 小开关（非移动、非动画）：装备槽 / 举起开关 / 气泡文案
-- ============================================================

---@param text string|nil
function BabyAgent:set_status(text)
    self.view_model:set_status_text(text or "")
end

---@param value boolean
function BabyAgent:set_busy(value)
    self.view_model:set_busy(value)
end

---@param enabled boolean
function BabyAgent:set_lift_enabled(enabled)
    if self.unit and self.unit.set_lifted_enabled then
        self.unit.set_lifted_enabled(enabled and true or false)
    end
end

function BabyAgent:select_equipped_slot()
    if self.unit and self.unit.set_selected_equipment_slot then
        self.unit.set_selected_equipment_slot(Enums.EquipmentSlotType.EQUIPPED, 1)
    end
end

-- 行为/序列需要立刻停步的快捷入口（真正的移动仍由 MovementSystem 拥有）。
function BabyAgent:stop_movement()
    self.movement:force_stop()
end

-- ============================================================
-- 需求生命周期
-- ============================================================

function BabyAgent:choose_next_need()
    self:cancel_need_countdown()
    self.current_need = self.services.need:take()
    if not self.current_need then
        self.view_model:set_need(nil)
        self:set_status("没有需求")
        return
    end

    self.view_model:set_need(self.current_need)
    local seconds = self:get_need_timeout_seconds()
    Log.info("baby", self.index, "need", self.current_need.id, "timeout", seconds)
    self.need_runtime:start(seconds)
end

function BabyAgent:show_current_need()
    if self.current_need then
        self:set_status(self:_format_need_countdown(self.need_runtime:get_remaining()))
    end
end

---@param remaining integer|nil
---@return string
function BabyAgent:_format_need_countdown(remaining)
    if not self.current_need then
        return ""
    end
    if remaining and remaining > 0 then
        return self.current_need.need_text .. " " .. tostring(remaining) .. "秒"
    end
    return self.current_need.need_text
end

function BabyAgent:cancel_need_countdown()
    self.need_runtime:cancel()
end

---@param min_seconds integer
---@param max_seconds integer
---@return integer
function BabyAgent:_random_seconds(min_seconds, max_seconds)
    if max_seconds < min_seconds then
        max_seconds = min_seconds
    end
    if GameAPI and GameAPI.random_int then
        return GameAPI.random_int(min_seconds, max_seconds)
    end
    local span = max_seconds - min_seconds + 1
    return min_seconds + (self.index % span)
end

---@return integer
function BabyAgent:get_need_timeout_bonus_seconds()
    return self.need_timeout_bonus_seconds or 0
end

---@return integer
function BabyAgent:get_timeout_action_bonus_seconds()
    return self.timeout_action_bonus_seconds or 0
end

---@return integer
function BabyAgent:get_need_timeout_seconds()
    local need = self.current_need
    local min_seconds = need and need.need_timeout_min_seconds or nil
    local max_seconds = need and need.need_timeout_max_seconds or nil
    min_seconds = min_seconds or self.config.baby.need_timeout_min_seconds or 20
    max_seconds = max_seconds or self.config.baby.need_timeout_max_seconds or min_seconds

    local seconds = self:_random_seconds(min_seconds, max_seconds) + self:get_need_timeout_bonus_seconds()
    if seconds < 1 then
        seconds = 1
    end
    return seconds
end

---@return integer
function BabyAgent:get_timeout_action_seconds()
    local need = self.current_need
    local seconds = need and need.timeout_action_seconds or nil
    seconds = seconds or self.config.baby.timeout_action_seconds or 10
    seconds = seconds + self:get_timeout_action_bonus_seconds()
    if seconds < 1 then
        seconds = 1
    end
    return seconds
end

-- ============================================================
-- 放下冻结：独立的移动表现锁（reason "hold"），不切状态、不动需求。
-- ============================================================

---@param duration Fixed
function BabyAgent:hold_movement(duration)
    self._hold_remaining = duration
    self.action_lock:acquire("hold")
    self.movement:invalidate()
end

---@param dt Fixed
function BabyAgent:_update_hold(dt)
    if self._hold_remaining <= 0 then
        return
    end
    self._hold_remaining = self._hold_remaining - dt
    if self._hold_remaining <= 0 then
        self._hold_remaining = 0.0
        self.action_lock:release("hold")
        self.movement:invalidate()
    end
end

function BabyAgent:cancel_movement_hold()
    if self._hold_remaining > 0 or self.action_lock:has("hold") then
        self._hold_remaining = 0.0
        self.action_lock:release("hold")
        self.movement:invalidate()
    end
end

-- ============================================================
-- 骑乘移动锁（reason "ride"，供 FacilityService 调用）
-- ============================================================

function BabyAgent:lock_ride_move_state()
    self.action_lock:acquire("ride")
    self.movement:invalidate()
end

function BabyAgent:unlock_ride_move_state()
    self.action_lock:release("ride")
    self.movement:invalidate()
end

-- ============================================================
-- 行为状态机
-- ============================================================

---@param state_id integer
---@param context BabyStateContext|nil
---@param force boolean|nil
---@return boolean
function BabyAgent:enter_state(state_id, context, force)
    if self.destroyed or not state_id then
        return false
    end
    if not force and self:is_in_state(state_id) then
        return false
    end

    local next_state = self.states[state_id]
    if not next_state then
        next_state = self:_new_state(state_id)
        self.states[state_id] = next_state
        self.state_list[#self.state_list + 1] = next_state
    end

    if self.active_state and self.active_state:is_active() then
        self.active_state:exit(context)
    end
    self.active_state = next_state
    self.view_model:set_state(state_id)
    next_state:enter(context)
    return true
end

---@param state_id integer
---@return StateBase
function BabyAgent:_new_state(state_id)
    local cls
    if state_id == Enum.BabyState.Idle then
        cls = require("BabyStorm.Domain.State.IdleState")
    elseif state_id == Enum.BabyState.Carried then
        cls = require("BabyStorm.Domain.State.CarriedState")
    elseif state_id == Enum.BabyState.SeekingItem then
        cls = require("BabyStorm.Domain.State.SeekingItemState")
    elseif state_id == Enum.BabyState.Satisfied then
        cls = require("BabyStorm.Domain.State.SatisfiedState")
    elseif state_id == Enum.BabyState.InteractingFacility then
        cls = require("BabyStorm.Domain.State.InteractingFacilityState")
    elseif state_id == Enum.BabyState.Upset then
        cls = require("BabyStorm.Domain.State.UpsetState")
    elseif state_id == Enum.BabyState.Cry then
        cls = require("BabyStorm.Domain.State.CryState")
    else
        cls = require("BabyStorm.Domain.State.StateBase")
    end

    local state = cls.New(self)
    state:init(state_id)
    return state
end

---@param state_id integer
---@return boolean
function BabyAgent:is_in_state(state_id)
    return self.active_state and self.active_state:get_state_id() == state_id and self.active_state:is_active()
end

---@return boolean
function BabyAgent:enter_idle()
    return self:enter_state(Enum.BabyState.Idle)
end

---@param context BabyStateContext|nil
---@return boolean
function BabyAgent:enter_upset(context)
    return self:enter_state(Enum.BabyState.Upset, context, true)
end

-- ============================================================
-- 举起 / 放下事件（由 manager 转发）
-- ============================================================

---@param data table|nil
function BabyAgent:on_lifted_begin(data)
    if self.destroyed then
        return
    end

    self:cancel_movement_hold()

    local lift_unit = data and data.lift_unit or nil
    local role = RoleUtil.get_role_by_unit(lift_unit)

    -- Cry 期间被抱起：概率拒绝；否则切到「被举着哭」表现，但不结束哭闹倒计时。
    if self:is_in_state(Enum.BabyState.Cry) then
        self.last_lift_unit = lift_unit
        self.last_role = role
        if self:should_reject_timeout_lift() then
            local rejected = self:reject_timeout_lift_attempt(lift_unit)
            Log.info("baby", self.index, "reject cry lift attempt", rejected)
            if rejected then
                return
            end
        end
        if self.active_state and self.active_state.on_lifted then
            self.active_state:on_lifted()
        end
        self:set_lift_enabled(true)
        self.services.task:emit_lift_baby(self)
        return
    end

    if self.view_model:is_busy() then
        return
    end

    self.is_rejecting = false
    self:enter_state(Enum.BabyState.Carried, {
        lift_unit = lift_unit,
        role = role,
    }, true)
end

---@param data table|nil
function BabyAgent:on_lifted_end(data)
    if self.destroyed or not self.unit then
        return
    end

    local pos = self.unit.get_position and self.unit.get_position()

    if self:is_in_state(Enum.BabyState.Cry) then
        self.last_lift_unit = nil
        self.last_role = nil
        if pos and self:try_match_current_need_at(pos, "baby_drop") then
            return
        end
        if self.active_state and self.active_state.on_dropped then
            self.active_state:on_dropped()
        end
        self:hold_movement(self.config.baby.drop_move_hold_seconds)
        return
    end

    if not self:is_in_state(Enum.BabyState.Carried) then
        return
    end

    if not pos then
        self:hold_movement(self.config.baby.drop_move_hold_seconds)
        self:enter_idle()
        return
    end

    if self:try_match_current_need_at(pos, "baby_drop") then
        return
    end

    local wrong = self.services.item:nearest_to(pos)
    if wrong then
        -- 不是宝宝想要的：先捡到手上，之后再丢掉并表示不满意
        self:cancel_movement_hold()
        self:enter_state(Enum.BabyState.SeekingItem, {
            item = wrong,
            reason = "wrong_item",
            delivery_method = "baby_to_item",
        }, true)
    else
        self:hold_movement(self.config.baby.drop_move_hold_seconds)
        self:enter_idle()
    end
end

-- ============================================================
-- 需求匹配
-- ============================================================

---@param pos Vector3
---@param source "baby_drop"|"item_to_baby"|nil
---@return boolean
function BabyAgent:try_match_current_need_at(pos, source)
    -- 设施需求只能由玩家抱着宝宝到目标处并放下触发。
    -- 空闲扫描只处理地面物品，避免宝宝自己走近设施导致任务事件不匹配。
    local facility = source == "baby_drop" and self:find_match_for_current_need(pos) or nil
    if facility then
        self:cancel_movement_hold()
        self:enter_state(Enum.BabyState.InteractingFacility, {
            facility = facility,
            delivery_method = source == "baby_drop" and "baby_to_facility" or nil,
        }, true)
        return true
    end

    local item = self.services.item:nearest_match(pos, self.current_need)
    if item then
        self:cancel_movement_hold()
        local delivery_method = nil
        if source == "baby_drop" then
            delivery_method = "baby_to_item"
        elseif source == "item_to_baby" then
            delivery_method = "item_to_baby"
        end
        self:enter_state(Enum.BabyState.SeekingItem, {
            item = item,
            delivery_method = delivery_method,
        }, true)
        return true
    end
    return false
end

---@param pos Vector3
---@return BabyFacilityRecord|nil
function BabyAgent:find_match_for_current_need(pos)
    if self.services.resolver and self.services.resolver:is_facility_need(self.current_need) then
        return self.services.facility:nearest_match(pos, self.current_need, self.unit)
    end
    return nil
end

-- ============================================================
-- 拾取结算（SeekItem 状态轮询命中 / manager 拾取事件 共用，均做幂等兜底）
-- ============================================================

---@param item BabyItemRecord
function BabyAgent:_resolve_pickup(item)
    -- 拾取动作（swap_equipment_slot）会同步触发 SPEC_EQUIPMENT_OBTAIN，
    -- 届时 _on_item_obtained 已经处理过对错；这里只做兜底，避免重复结算。
    if self.is_rejecting then
        return
    end
    if self.pending_purpose == "reject" then
        self:reject_wrong_item(item)
    else
        self:complete_item_obtained(item, 1)
    end
end

---@param item BabyItemRecord
---@param count integer|nil
function BabyAgent:complete_item_obtained(item, count)
    if self.destroyed or not item or item.done then
        return
    end

    item.done = true
    self.pending_item = nil
    self.pending_purpose = nil
    self.pickup_target = nil
    self:select_equipped_slot()
    self.services.item:remove(item)
    self:cancel_need_countdown()
    LuaAPI.call_delay_time(1.5, function()
        if not self.destroyed then
            self.services.task:emit_baby_pick_item(self, item, count or 1)
        end
    end)
    self:enter_state(Enum.BabyState.Satisfied, { item = item }, true)
end

---不是宝宝想要的物品：捡到手上后丢掉，然后表示不满意
---@param item BabyItemRecord|nil
function BabyAgent:reject_wrong_item(item)
    if self.destroyed or not item or self.is_rejecting then
        return
    end

    self.is_rejecting = true
    self.pending_item = nil
    self.pending_purpose = nil
    self.pickup_target = nil

    self:set_busy(true)
    self:set_lift_enabled(false)
    -- 拿在手上看一会儿，期间不再走动（直接压意图为 Stop，仍处于 SeekingItem 状态内）。
    self.move_mode = Intent.MoveMode.Stop
    self.anim_base = Intent.AnimBase.Idle
    self:invalidate_systems()
    self:select_equipped_slot()
    LuaAPI.call_delay_time(1.5, function()
        if not self.destroyed and self.is_rejecting then
            self.services.task:emit_baby_pick_item(self, item, 1)
        end
    end)
    self:set_status("咦？不是这个…")

    LuaAPI.call_delay_time(self.config.baby.reject_hold_delay, function()
        if self.destroyed then
            return
        end
        if item.equipment then
            pcall(function()
                if item.equipment.set_droppable then
                    item.equipment.set_droppable(true)
                end
                if item.equipment.drop then
                    item.equipment.drop()
                end
            end)
        end
        self:set_status("不要这个！")

        LuaAPI.call_delay_time(self.config.baby.reject_throw_delay, function()
            if self.destroyed then
                return
            end
            self.is_rejecting = false
            self:enter_upset({ item = item, reason = "wrong_item" })
        end)
    end)
end

-- ============================================================
-- 设施交互结算
-- ============================================================

---@param facility BabyFacilityRecord
function BabyAgent:complete_facility_interaction(facility)
    if self.destroyed or not facility then
        return
    end
    self:cancel_need_countdown()
    self.services.facility:end_interaction(self, facility)
    self.active_facility = nil
    self:enter_state(Enum.BabyState.Satisfied, { facility = facility }, true)
end

---@param facility BabyFacilityRecord|nil
function BabyAgent:finish_facility_satisfied(facility)
    if self.destroyed then
        return
    end
    self:choose_next_need()
    self:enter_idle()
end

---@param item BabyItemRecord|nil
function BabyAgent:finish_satisfied(item)
    if self.destroyed then
        return
    end
    if item then
        self.services.item:destroy_and_respawn(item)
    end
    self:choose_next_need()
    self:enter_idle()
end

-- 顶球玩法结束结算（由 BallRallyService 在玩家漏接、会话收尾时调用）。
-- 一律算作满足该需求：基础满足分 + 按成功顶球次数追加奖励（接的越多分越多），
-- 随后走一遍开心表现并推进到下一个需求。调用前 BallRallyService 已解除接管锁。
---@param role Role|nil
---@param catches integer
function BabyAgent:finish_ball_rally(role, catches)
    if self.destroyed then
        return
    end
    self.last_role = role
    self.services.score:award_satisfied(role)
    self.services.score:award_ball_bonus(role, catches or 0)
    if self.services.difficulty then
        self.services.difficulty:on_baby_satisfied(self)
    end
    -- 复用满足状态的开心表现 + 自动推进需求（nil 目标不会重复计分）。
    self:enter_state(Enum.BabyState.Satisfied, { reason = "ball_rally" }, true)
end

-- 猜拳需求的基础满足是"宝宝举起自己的骰子"；配对+抛骰+顶撞+落地判胜负是额外加分项，不强制玩家参与。
-- outcome（玩家视角）：
--   "win"/"draw"/"lose" —— 双方跑完抛骰、骰子干净落面判出胜负，按分档追加加分。
--   nil —— 玩家未响应的独自满足（见 _finish_solo_satisfy），或没干净落面无法判胜负，只给基础满足分。
---@param role Role|nil
---@param outcome "win"|"draw"|"lose"|nil
function BabyAgent:finish_rps(role, outcome)
    if self.destroyed then
        return
    end
    self.last_role = role
    self.services.score:award_satisfied(role)
    if outcome then
        self.services.score:award_rps_result(role, outcome)
    end
    if self.services.difficulty then
        self.services.difficulty:on_baby_satisfied(self)
    end
    -- 胜负文案从“玩家视角”翻成宝宝的表现：玩家赢=宝宝输了不服气、玩家输=宝宝赢了得意、平局。
    local status_text = (self.current_need and self.current_need.satisfied_text) or "猜拳完成啦"
    if outcome == "win" then
        status_text = "哼，这局你赢啦～"
    elseif outcome == "lose" then
        status_text = "耶！我赢啦！"
    elseif outcome == "draw" then
        status_text = "平局，再来一次嘛～"
    end
    self:enter_state(Enum.BabyState.Satisfied, {
        reason = "rps",
        status_text = status_text,
    }, true)
end

-- ============================================================
-- Cry 概率拒绝抱起
-- ============================================================

---@return boolean
function BabyAgent:should_reject_timeout_lift()
    local chance = self.config.baby.timeout_reject_lift_chance_percent or 0
    if chance <= 0 then
        return false
    end
    if chance >= 100 then
        return true
    end

    local roll
    if GameAPI and GameAPI.random_int then
        roll = GameAPI.random_int(1, 100)
    else
        local raw = LuaAPI.rand and LuaAPI.rand() or 0
        if raw < 0 then
            raw = -raw
        end
        roll = (raw % 100) + 1
    end
    Log.info("baby", self.index, "cry reject lift roll", roll, "chance", chance)
    return roll <= chance
end

---@param lift_unit Unit|LifeEntity|nil
---@return boolean
function BabyAgent:reject_timeout_lift_attempt(lift_unit)
    if self.destroyed or not self:is_in_state(Enum.BabyState.Cry) or not lift_unit then
        return false
    end
    if lift_unit.lift then
        return pcall(function() lift_unit.lift() end)
    end
    if lift_unit.cmd_lift then
        return pcall(function() lift_unit.cmd_lift() end)
    end
    if lift_unit.ai_command_lift then
        return pcall(function() lift_unit.ai_command_lift() end)
    end
    return false
end

---@return boolean
function BabyAgent:_is_lifted_now()
    if self.unit and self.unit.is_lifted_status then
        local ok, lifted = pcall(function()
            return self.unit.is_lifted_status()
        end)
        return ok and lifted or false
    end
    return false
end

-- ============================================================
-- 销毁
-- ============================================================

function BabyAgent:destroy()
    self.destroyed = true
    self.pending_item = nil
    self.pending_purpose = nil
    self.pickup_target = nil
    self.is_rejecting = false
    self.active_facility = nil
    self._hold_remaining = 0.0

    if self.active_state and self.active_state:is_active() then
        self.active_state:exit(nil)
    end
    self.need_runtime:cancel()
    self.animation:cleanup()
    self.action_lock:release_all()

    if self.view_model then
        self.view_model:clear()
    end
    self.states = {}
    self.state_list = {}
    self.active_state = nil
end

return BabyAgent
