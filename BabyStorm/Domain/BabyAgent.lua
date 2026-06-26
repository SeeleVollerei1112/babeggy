local Class = require("BaseClass")
local Enum = require("BabyStorm.Config.BabyStormEnum")
local BabyViewModel = require("BabyStorm.Domain.BabyViewModel")
local RoleUtil = require("Util.RoleUtil")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

---@class BabyStateContext
---@field item BabyItemRecord|nil
---@field facility BabyFacilityRecord|nil
---@field lift_unit Unit|nil
---@field role Role|nil
---@field reason string|nil

---@class BabyAgent
---@field index integer
---@field unit LifeEntity|Unit
---@field services BabyServices
---@field config BabyStormConfig
---@field enum BabyStormEnum|table
---@field view_model BabyViewModel
---@field states table<integer, StateBase>
---@field state_list StateBase[]
---@field active_state StateBase|nil
---@field current_need BabyNeedDef|nil
---@field last_role Role|nil
---@field last_lift_unit Unit|nil
---@field pending_item BabyItemRecord|nil
---@field pending_purpose "satisfy"|"reject"|nil
---@field is_rejecting boolean
---@field patrol_token integer
---@field pickup_token integer
---@field need_timer_token integer
---@field timeout_action_token integer
---@field need_countdown_remaining integer|nil
---@field timeout_action_anchor_pos Vector3|nil
---@field timeout_move_locked boolean
---@field need_timeout_bonus_seconds integer
---@field timeout_action_bonus_seconds integer
---@field active_facility BabyFacilityRecord|nil
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
    self.states = {}
    self.state_list = {}
    self.active_state = nil
    self.current_need = nil
    self.last_role = nil
    self.last_lift_unit = nil
    self.pending_item = nil
    self.pending_purpose = nil
    self.is_rejecting = false
    self.patrol_token = 0
    self.pickup_token = 0
    self.need_timer_token = 0
    self.timeout_action_token = 0
    self.need_countdown_remaining = nil
    self.timeout_action_anchor_pos = nil
    self.timeout_move_locked = false
    self.need_timeout_bonus_seconds = 0
    self.timeout_action_bonus_seconds = 0
    self.active_facility = nil
    self.ride_token = 0
    self.ride_elapsed = 0
    self.ride_required = 0
    self.ride_idle_elapsed = 0
    self.ride_driving = false
    self.ride_started = false
    self.ride_vehicle = nil
    self.ride_carrier = nil
    self._ride_vehicle_unit = nil
    self.ride_collision_disabled = false
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

function BabyAgent:stop_movement()
    if not self.unit then
        return
    end
    if self.unit.stop_ai then
        self.unit.stop_ai()
    end
    if self.unit.ai_command_stop_move then
        self.unit.ai_command_stop_move(0.1)
    end
end

function BabyAgent:select_equipped_slot()
    if self.unit and self.unit.set_selected_equipment_slot then
        self.unit.set_selected_equipment_slot(Enums.EquipmentSlotType.EQUIPPED, 1)
    end
end

function BabyAgent:choose_next_need()
    self:cancel_need_countdown()
    self.current_need = self.services.need:take()
    if not self.current_need then
        self.view_model:set_need(nil)
        self:set_status("没有需求")
        return
    end

    self.view_model:set_need(self.current_need)
    self:start_need_countdown()
    Log.info("baby", self.index, "need", self.current_need.id)
end

function BabyAgent:show_current_need()
    if self.current_need then
        self:set_status(self:_format_need_countdown(self.need_countdown_remaining))
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
    self.need_timer_token = self.need_timer_token + 1
    self.need_countdown_remaining = nil
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
    return min_seconds + ((self.index + self.need_timer_token) % span)
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

function BabyAgent:start_need_countdown()
    if not self.current_need then
        return
    end

    self.need_timer_token = self.need_timer_token + 1
    local token = self.need_timer_token
    local seconds = self:get_need_timeout_seconds()
    Log.info("baby", self.index, "need timeout", seconds)
    self.need_countdown_remaining = seconds
    self:_tick_need_countdown(token, seconds)
end

---@param token integer
---@param remaining integer
function BabyAgent:_tick_need_countdown(token, remaining)
    if self.destroyed or self.need_timer_token ~= token or not self.current_need then
        return
    end
    self.need_countdown_remaining = remaining
    if remaining <= 0 then
        self:_handle_need_timeout(token)
        return
    end

    -- 计时持续推进，但只有在 Idle（正在展示需求）时才刷新气泡，
    -- 否则会把“被抱起 / 去荡秋千 / 捡起来看看”等状态气泡每秒覆盖回“想要…X秒”。
    if self:is_in_state(self.enum.BabyState.Idle) then
        self:set_status(self:_format_need_countdown(remaining))
    end
    LuaAPI.call_delay_time(1.0, function()
        self:_tick_need_countdown(token, remaining - 1)
    end)
end

---@param token integer
function BabyAgent:_handle_need_timeout(token)
    if self.destroyed or self.need_timer_token ~= token or not self.current_need then
        return
    end

    self:cancel_need_countdown()
    self:enter_state(self.enum.BabyState.Timeout, { reason = "need_timeout" }, true)
end

function BabyAgent:begin_timeout_action()
    if self.destroyed then
        return
    end

    self.timeout_action_token = self.timeout_action_token + 1
    local token = self.timeout_action_token
    local duration = self:get_timeout_action_seconds()
    Log.info("baby", self.index, "timeout action", duration)

    self:set_busy(true)
    self:_prepare_timeout_action_pose()
    self.pending_item = nil
    self.pending_purpose = nil
    self.is_rejecting = false
    self.pickup_token = self.pickup_token + 1

    if self.active_facility then
        self.services.facility:end_interaction(self, self.active_facility)
        self.active_facility = nil
    end

    self.view_model:add_stress(1)
    self:_wait_timeout_release_then_play(token, duration, 0)
end

function BabyAgent:_prepare_timeout_action_pose()
    self:cancel_patrol()
    self:_release_lift_for_timeout()
    self:stop_movement()
    self:_lock_timeout_move_state()
    self:select_equipped_slot()
end

function BabyAgent:_release_lift_for_timeout()
    local lift_unit = self.last_lift_unit
    if lift_unit then
        if lift_unit.lift then
            pcall(function() lift_unit.lift() end)
        end
        if lift_unit.cmd_lift then
            pcall(function() lift_unit.cmd_lift() end)
        end
        if lift_unit.ai_command_lift then
            pcall(function() lift_unit.ai_command_lift() end)
        end
    end
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

---@param token integer
---@param duration integer
---@param attempts integer
function BabyAgent:_wait_timeout_release_then_play(token, duration, attempts)
    if self.destroyed or self.timeout_action_token ~= token or not self:is_in_state(self.enum.BabyState.Timeout) then
        return
    end

    if self:_is_lifted_now() and attempts < 12 then
        Log.info("baby", self.index, "wait lift release", attempts)
        self:_release_lift_for_timeout()
        LuaAPI.call_delay_time(0.1, function()
            self:_wait_timeout_release_then_play(token, duration, attempts + 1)
        end)
        return
    end

    Log.info("baby", self.index, "lift released", not self:_is_lifted_now())
    self.last_lift_unit = nil
    self:set_lift_enabled(false)
    self:stop_movement()
    self:_lock_timeout_move_state()
    self:_play_timeout_action(duration)
    self:_tick_timeout_action(token, duration)
end

function BabyAgent:_lock_timeout_move_state()
    -- 本方法在一次超时流程中会被调用两次（_prepare_timeout_action_pose 与
    -- _wait_timeout_release_then_play）。BUFF_FORBID_MOVE 是计数型 buff，
    -- 加两次只移除一次会导致宝宝永久无法移动，因此这里做幂等保护：只加一次。
    if not self.timeout_move_locked then
        if self.unit and self.unit.add_state then
            pcall(function()
                self.unit.add_state(Enums.BuffState.BUFF_FORBID_MOVE)
            end)
        end
        self.timeout_move_locked = true
    end
    if self.unit and self.unit.ai_command_stop_move then
        pcall(function()
            self.unit.ai_command_stop_move(0.1)
        end)
    end
    if self.unit and self.unit.set_attr_ratio_fixed then
        pcall(function()
            self.unit.set_attr_ratio_fixed("move_speed", 0.0)
        end)
    end
end

function BabyAgent:_unlock_timeout_move_state()
    if self.unit and self.timeout_move_locked and self.unit.remove_state then
        pcall(function()
            self.unit.remove_state(Enums.BuffState.BUFF_FORBID_MOVE)
        end)
    end
    self.timeout_move_locked = false
end

---@param duration integer
function BabyAgent:_play_timeout_action(duration)
    local action_id = self.config.baby.timeout_action_id or 23
    local play_time = duration + 0.0
    if not self.unit then
        return
    end

    -- 先清除可能因 AI 移动而屏蔽的动画，确保哭闹动作能播出来
    if self.unit.clear_banned_anim then
        pcall(function() self.unit.clear_banned_anim() end)
    end

    -- timeout_action_id（如 23）是“全身动作编号”，必须用 play_body_anim_by_id；
    -- force_play_animation_by_anim_key 需要的是 AnimKey（如座位动画 21013），
    -- 两者编号空间不同，用错 API 会“进入状态但看不到动作表现”。
    if self.unit.play_body_anim_by_id then
        local ok = pcall(function()
            self.unit.play_body_anim_by_id(action_id, 0.0, play_time, true)
        end)
        Log.info("baby", self.index, "timeout body anim", action_id, "ok", ok)
        return
    end
    if self.unit.force_play_animation_by_anim_key then
        local ok = pcall(function()
            self.unit.force_play_animation_by_anim_key(action_id, 0.0, play_time, 1.0, true)
        end)
        Log.info("baby", self.index, "timeout anim", action_id, "ok", ok)
    end
end

---@param token integer
---@param remaining integer
function BabyAgent:_tick_timeout_action(token, remaining)
    if self.destroyed or self.timeout_action_token ~= token then
        return
    end

    if remaining <= 0 then
        self:finish_timeout_action(token)
        return
    end

    self:set_status("没满足！" .. tostring(remaining) .. "秒")
    -- 全身动作（如 23）单次播放约 1 秒后会被待机动画顶掉，这里每秒重发一次，
    -- 让“没满足”动作在整段超时时间内持续表现。
    self:_refresh_timeout_anim(remaining)
    LuaAPI.call_delay_time(1.0, function()
        self:_tick_timeout_action(token, remaining - 1)
    end)
end

---@param remaining integer
function BabyAgent:_refresh_timeout_anim(remaining)
    if not (self.unit and self.unit.play_body_anim_by_id) then
        return
    end
    local action_id = self.config.baby.timeout_action_id or 23
    pcall(function()
        self.unit.play_body_anim_by_id(action_id, 0.0, remaining + 0.0, true)
    end)
end

---@param token integer
function BabyAgent:finish_timeout_action(token)
    if self.destroyed or self.timeout_action_token ~= token then
        return
    end

    self.timeout_action_anchor_pos = nil
    self:_unlock_timeout_move_state()

    -- 与 _play_timeout_action 的 play_body_anim_by_id 对应，优先停全身动画
    if self.unit and self.unit.stop_play_body_anim then
        pcall(function()
            self.unit.stop_play_body_anim()
        end)
    elseif self.unit and self.unit.stop_anim then
        pcall(function()
            self.unit.stop_anim()
        end)
    end

    self:choose_next_need()
    self:enter_state(self.enum.BabyState.Idle, nil, true)
end

function BabyAgent:cancel_patrol()
    self.patrol_token = self.patrol_token + 1
end

function BabyAgent:start_patrol()
    if not self.unit then
        return
    end

    self.patrol_token = self.patrol_token + 1
    self:_command_next_patrol_point(self.patrol_token)
end

---@return Vector3
function BabyAgent:_make_ground_target()
    local random = self.services.arena:random_point()
    local current = self.unit.get_position and self.unit.get_position() or random
    if not random then
        return current or math.Vector3(0, 0, 0)
    end
    return math.Vector3(random.x, current.y, random.z)
end

---@param token integer
function BabyAgent:_command_next_patrol_point(token)
    if self.destroyed or not self.unit or self.view_model:is_busy() or self.patrol_token ~= token then
        return
    end

    local target = self:_make_ground_target()
    if self.unit.set_attr_ratio_fixed then
        self.unit.set_attr_ratio_fixed("move_speed", 0.0)
    end
    if self.unit.start_move_to_pos_with_threshold then
        self.unit.start_move_to_pos_with_threshold(target, self.config.baby.patrol_threshold, 0.5)
    end

    LuaAPI.call_delay_time(self.config.baby.patrol_interval, function()
        self:_command_next_patrol_point(token)
    end)
end

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
    local cls = nil
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
    elseif state_id == Enum.BabyState.Timeout then
        cls = require("BabyStorm.Domain.State.TimeoutState")
    elseif state_id == Enum.BabyState.Riding then
        cls = require("BabyStorm.Domain.State.RidingState")
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

---@param data table|nil
function BabyAgent:on_lifted_begin(data)
    if self.destroyed or self.view_model:is_busy() then
        return
    end

    self.is_rejecting = false
    local lift_unit = data and data.lift_unit or nil
    local role = RoleUtil.get_role_by_unit(lift_unit)
    self:enter_state(Enum.BabyState.Carried, {
        lift_unit = lift_unit,
        role = role,
    }, true)
end

---@param data table|nil
function BabyAgent:on_lifted_end(data)
    if self.destroyed or not self.unit or not self:is_in_state(Enum.BabyState.Carried) then
        return
    end

    -- 开小车需求：玩家抱着宝宝上载具时引擎会强制放下宝宝（触发本回调），
    -- 这里改为进入 Riding 状态——由我们把宝宝按帧粘在玩家头上，跟着玩家骑行。
    if self.services.resolver and self.services.resolver:is_ride_need(self.current_need) then
        self:enter_state(Enum.BabyState.Riding, { lift_unit = self.last_lift_unit, role = self.last_role }, true)
        return
    end

    local pos = self.unit.get_position and self.unit.get_position()
    if not pos then
        self:enter_idle()
        return
    end

    local facility = self:find_match_for_current_need(pos)
    if facility then
        self:enter_state(Enum.BabyState.InteractingFacility, { facility = facility }, true)
        return
    end

    local item = self.services.item:nearest_match(pos, self.current_need)
    if item then
        self:enter_state(Enum.BabyState.SeekingItem, { item = item }, true)
        return
    end

    local wrong = self.services.item:nearest_to(pos)
    if wrong then
        -- 不是宝宝想要的：先捡到手上，之后再丢掉并表示不满意
        self:enter_state(Enum.BabyState.SeekingItem, { item = wrong, reason = "wrong_item" }, true)
    else
        self:enter_idle()
    end
end

---@param pos Vector3
---@return BabyFacilityRecord|nil
function BabyAgent:find_match_for_current_need(pos)
    if self.services.resolver and self.services.resolver:is_facility_need(self.current_need) then
        return self.services.facility:nearest_match(pos, self.current_need, self.unit)
    end
    return nil
end

---@param item BabyItemRecord|nil
---@param purpose "satisfy"|"reject"|nil
function BabyAgent:command_pickup(item, purpose)
    if not (self.unit and item and item.equipment) then
        self:enter_upset({ reason = "pickup_failed" })
        return
    end

    self.pending_purpose = purpose or "satisfy"

    if self.unit.start_ai then
        self.unit.start_ai()
    end

    self.pickup_token = self.pickup_token + 1
    local token = self.pickup_token

    if self.unit.set_attr_ratio_fixed then
        self.unit.set_attr_ratio_fixed("move_speed", self.config.baby.pickup_move_speed_ratio)
    end
    if self.unit.ai_command_pick_up_equipment then
        self.unit.ai_command_pick_up_equipment(item.equipment, Enums.MoveMode.DIRECT, 0.2)
    end

    LuaAPI.call_delay_time(self.config.baby.pickup_check_interval, function()
        self:_wait_for_pickup_result(item, token, self.config.baby.pickup_check_interval)
    end)
end

---@param item BabyItemRecord
---@param token integer
---@param elapsed Fixed
function BabyAgent:_wait_for_pickup_result(item, token, elapsed)
    if self.destroyed or self.pending_item ~= item or self.pickup_token ~= token or not item or item.done then
        return
    end

    if self.services.item:item_owned_by_baby(item, self) then
        self:_resolve_pickup(item)
        return
    end

    local baby_pos = self.unit.get_position and self.unit.get_position()
    local item_pos = item.equipment.get_position and item.equipment.get_position()
    local radius = self.config.baby.pickup_radius
    if baby_pos and item_pos and UnitUtil.distance_sq(baby_pos, item_pos) <= radius * radius then
        if self.services.item:force_pickup(self, item) then
            self:_resolve_pickup(item)
            return
        end
    end

    if elapsed >= self.config.baby.pickup_timeout then
        self.pending_item = nil
        if self.pending_purpose == "reject" then
            -- 没能走到错误物品也照样表示不满意
            self.pending_purpose = nil
            self:enter_upset({ item = item, reason = "wrong_item" })
        else
            self:enter_upset({ reason = "pickup_timeout" })
        end
        return
    end

    LuaAPI.call_delay_time(self.config.baby.pickup_check_interval, function()
        self:_wait_for_pickup_result(item, token, elapsed + self.config.baby.pickup_check_interval)
    end)
end

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
    self:select_equipped_slot()
    self.services.item:remove(item)
    self:cancel_need_countdown()
    self.services.task:emit_baby_pick_item(self, item, count or 1)
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
    self.pickup_token = self.pickup_token + 1

    self:set_busy(true)
    self:set_lift_enabled(false)
    self:stop_movement()
    self:select_equipped_slot()
    -- 先拿在手上看一会儿（气泡：疑惑）
    self:set_status("咦？不是这个…")

    -- 拿在手上一会儿，再把错误物品丢出去
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
        -- 丢出去（气泡：嫌弃）
        self:set_status("不要这个！")

        -- 丢完之后再进入不满意提示（气泡：不是想要的）
        LuaAPI.call_delay_time(self.config.baby.reject_throw_delay, function()
            if self.destroyed then
                return
            end
            self.is_rejecting = false
            self:enter_upset({ item = item, reason = "wrong_item" })
        end)
    end)
end

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

-- ===== 开小车需求：宝宝被玩家“挂”在头上，跟随玩家骑载具移动 =====
-- 玩家上载具会强制放下宝宝，所以这里不依赖引擎抱举，而是按帧 set_position
-- 把宝宝粘到玩家头部插槽；只有“玩家正在骑载具”时才推进倒计时。

---@return integer
function BabyAgent:_ride_required_seconds()
    local need = self.current_need
    local min_seconds = (need and need.interact_min_seconds) or self.config.baby.ride_min_seconds or 15
    local max_seconds = (need and need.interact_max_seconds) or self.config.baby.ride_max_seconds or min_seconds
    return self:_random_seconds(min_seconds, max_seconds)
end

---@return Vector3
function BabyAgent:_ride_seat_offset()
    local values = (self.current_need and self.current_need.ride_seat_offset) or self.config.baby.ride_seat_offset
    if values then
        return math.Vector3(values[1], values[2], values[3])
    end
    return math.Vector3(0.0, 1.2, 0.0)
end

---@return Unit|false|nil
function BabyAgent:_resolve_ride_vehicle()
    if self._ride_vehicle_unit ~= nil then
        return self._ride_vehicle_unit
    end
    local name = self.current_need and self.current_need.vehicle_name or nil
    if name and LuaAPI.query_unit then
        local ok, unit = pcall(function() return LuaAPI.query_unit(name) end)
        self._ride_vehicle_unit = (ok and unit) or false
    else
        self._ride_vehicle_unit = false
    end
    return self._ride_vehicle_unit
end

---@param carrier Unit|LifeEntity|nil
---@return boolean
function BabyAgent:_carrier_driving(carrier)
    if not carrier then
        return false
    end

    -- 主判定：该 UGC 滑板不触发标准载具事件，也不在 get_driving_vehicle 里登记；
    -- 但玩家坐上去后坐标与滑板几乎重合，因此用“玩家是否贴在滑板上”判断是否在骑行。
    local vehicle = self:_resolve_ride_vehicle()
    if vehicle and vehicle.get_position and carrier.get_position then
        local vp = vehicle.get_position()
        local cp = carrier.get_position()
        if vp and cp then
            local radius = self.config.baby.ride_mount_radius or 1.2
            if UnitUtil.distance_sq(cp, vp) <= radius * radius then
                return true
            end
        end
    end

    -- 兜底：标准载具事件 / get_driving_vehicle（对真·可骑乘载具有效）
    if self.services.is_unit_driving then
        return self.services.is_unit_driving(carrier) and true or false
    end
    return false
end

---@return boolean
function BabyAgent:is_riding_state()
    return self:is_in_state(self.enum.BabyState.Riding)
end

---玩家（抱起宝宝者）上了载具：开始把宝宝挂到头上骑行
---@param vehicle Vehicle|nil
function BabyAgent:on_carrier_enter_vehicle(vehicle)
    if self.destroyed or not self:is_riding_state() then
        return
    end
    self.ride_driving = true
    self.ride_vehicle = vehicle
    self.ride_idle_elapsed = 0
end

---玩家下了载具
function BabyAgent:on_carrier_exit_vehicle()
    if self.destroyed then
        return
    end
    self.ride_driving = false
    self.ride_vehicle = nil
    self.ride_idle_elapsed = 0
end

---@param context BabyStateContext|nil
function BabyAgent:begin_ride(context)
    if self.destroyed then
        return
    end

    local carrier = (context and context.lift_unit) or self.last_lift_unit
    self:set_busy(true)
    self:cancel_patrol()
    self:stop_movement()
    self:set_lift_enabled(false)

    self.ride_token = self.ride_token + 1
    self.ride_elapsed = 0
    self.ride_idle_elapsed = 0
    self.ride_required = self:_ride_required_seconds()
    self.ride_driving = false
    self.ride_started = false
    self.ride_carrier = carrier
    self._ride_last_remain = nil

    if not carrier then
        self:enter_idle()
        return
    end

    Log.info("baby", self.index, "ride wait carrier mount")
    self:_ride_step(self.ride_token)
end

---@param token integer
function BabyAgent:_ride_step(token)
    if self.destroyed or self.ride_token ~= token or not self:is_riding_state() then
        return
    end

    -- 帧同步逻辑帧固定约 1/30s；按帧推进让跟随更顺滑
    local dt = 0.0333
    local carrier = self.ride_carrier
    local driving = self.ride_driving or self:_carrier_driving(carrier)

    if driving then
        if not self.ride_started then
            self.ride_started = true
            self:cancel_need_countdown() -- 需求已匹配，停掉耐心倒计时
            self:_set_baby_physics(false) -- 关闭宝宝物理：不受重力、不与人/车碰撞，做纯视觉乘客
            self:_set_ride_collision(false) -- 双保险：再关一次成对碰撞
            Log.info("baby", self.index, "ride start", self.ride_required)
        end
        self.ride_idle_elapsed = 0
        self:_glue_to_ride_anchor(carrier)
        self.ride_elapsed = self.ride_elapsed + dt
        if self.ride_elapsed >= self.ride_required then
            self:_complete_ride(carrier)
            return
        end
        local remain = math.ceil(self.ride_required - self.ride_elapsed)
        if remain ~= self._ride_last_remain then
            self._ride_last_remain = remain
            local text = (self.current_need and self.current_need.matched_text) or "开小车中"
            self:set_status(text .. " " .. tostring(remain) .. "秒")
        end
    elseif not self.ride_started then
        -- 还没骑车：等待玩家上载具；超时则当作普通放下
        self.ride_idle_elapsed = self.ride_idle_elapsed + dt
        if self.ride_idle_elapsed >= (self.config.baby.ride_confirm_seconds or 2.0) then
            Log.info("baby", self.index, "ride canceled (no mount)")
            self:enter_idle()
            return
        end
        if self._ride_last_remain ~= -2 then
            self._ride_last_remain = -2
            self:set_status("带我去开小车~")
        end
    else
        -- 骑过车但中途下来了：宝宝继续挂在头上，超时则放弃
        self:_glue_to_ride_anchor(carrier)
        self.ride_idle_elapsed = self.ride_idle_elapsed + dt
        if self.ride_idle_elapsed >= (self.config.baby.ride_idle_grace or 5.0) then
            Log.info("baby", self.index, "ride aborted (idle)")
            self:_drop_near_carrier(carrier)
            self:enter_idle()
            return
        end
        if self._ride_last_remain ~= -1 then
            self._ride_last_remain = -1
            self:set_status("快开起来呀~")
        end
    end

    if LuaAPI.call_delay_frame then
        LuaAPI.call_delay_frame(1, function()
            self:_ride_step(token)
        end)
    else
        LuaAPI.call_delay_time(dt, function()
            self:_ride_step(token)
        end)
    end
end

---把宝宝粘到“骑行锚点”上：优先用载具（滑板）的变换——它随移动转向，朝向才正确；
---取不到载具时退回抱起者（玩家）。
---@param carrier Unit|LifeEntity|nil
function BabyAgent:_glue_to_ride_anchor(carrier)
    if not (self.unit and self.unit.set_position) then
        return
    end

    local anchor = self:_resolve_ride_vehicle() or carrier
    if not anchor then
        return
    end

    local offset = self:_ride_seat_offset()
    local pos = nil
    if anchor.get_local_offset_position then
        local ok, p = pcall(function() return anchor.get_local_offset_position(offset) end)
        if ok and p then
            pos = p
        end
    end
    if not pos and anchor.get_position then
        local cp = anchor.get_position()
        if cp then
            pos = math.Vector3(cp.x + offset.x, cp.y + offset.y, cp.z + offset.z)
        end
    end
    if pos then
        if self.unit.set_position_smooth then
            pcall(function() self.unit.set_position_smooth(pos) end) -- 带渲染插值，跟随更顺滑
        else
            pcall(function() self.unit.set_position(pos) end)
        end
    end
    if anchor.get_orientation then
        local ok, rot = pcall(function() return anchor.get_orientation() end)
        if ok and rot then
            if self.unit.set_orientation_smooth then
                pcall(function() self.unit.set_orientation_smooth(rot) end)
            elseif self.unit.set_orientation then
                pcall(function() self.unit.set_orientation(rot) end)
            end
        end
    end
end

---开关宝宝自身的物理（重力/碰撞）；骑行时关掉让它当纯视觉乘客
---@param active boolean
function BabyAgent:_set_baby_physics(active)
    if not self.unit then
        return
    end
    if self.unit.set_physics_active then
        pcall(function() self.unit.set_physics_active(active) end)
    elseif self.unit.set_physic_enable then
        pcall(function() self.unit.set_physic_enable(active) end)
    end
end

---开关宝宝与玩家、载具之间的碰撞
---@param enabled boolean
function BabyAgent:_set_ride_collision(enabled)
    if not (GameAPI and GameAPI.enable_collision_between_units and self.unit) then
        return
    end
    if enabled == not self.ride_collision_disabled then
        return -- 状态未变化
    end

    local others = {}
    if self.ride_carrier then
        others[#others + 1] = self.ride_carrier
    end
    local vehicle = self:_resolve_ride_vehicle()
    if vehicle then
        others[#others + 1] = vehicle
    end
    for index = 1, #others do
        local other = others[index]
        pcall(function() GameAPI.enable_collision_between_units(self.unit, other, enabled) end)
    end
    self.ride_collision_disabled = not enabled
end

---离开骑行状态时的统一清理（由 RidingState:exit 调用）
function BabyAgent:cleanup_ride()
    self.ride_token = self.ride_token + 1
    self.ride_driving = false
    self.ride_started = false
    self:_set_baby_physics(true) -- 恢复物理
    if self.ride_collision_disabled then
        self:_set_ride_collision(true) -- 恢复碰撞
    end
end

---@param carrier Unit|LifeEntity|nil
function BabyAgent:_drop_near_carrier(carrier)
    if not (carrier and carrier.get_position and self.unit and self.unit.set_position) then
        return
    end
    local cp = carrier.get_position()
    if cp then
        pcall(function() self.unit.set_position(cp) end)
    end
end

---@param carrier Unit|LifeEntity|nil
function BabyAgent:_complete_ride(carrier)
    if self.destroyed then
        return
    end
    self.ride_token = self.ride_token + 1 -- 终止骑行循环
    self:cancel_need_countdown()
    self:_drop_near_carrier(carrier)
    Log.info("baby", self.index, "ride complete")
    self:enter_state(Enum.BabyState.Satisfied, { ride = true }, true)
end

---@return nil
function BabyAgent:destroy()
    self.destroyed = true
    self:cancel_patrol()
    self:cancel_need_countdown()
    self.timeout_action_token = self.timeout_action_token + 1
    self.pickup_token = self.pickup_token + 1
    self.ride_token = self.ride_token + 1
    self.pending_item = nil
    self.pending_purpose = nil
    self.is_rejecting = false
    self.active_facility = nil
    self.timeout_action_anchor_pos = nil
    self:_unlock_timeout_move_state()
    if self.view_model then
        self.view_model:clear()
    end
    self.states = {}
    self.state_list = {}
    self.active_state = nil
end

return BabyAgent









