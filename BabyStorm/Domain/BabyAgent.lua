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
---@field suppress_lift_event boolean|nil

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
---@field movement_hold_token integer
---@field movement_held boolean
---@field movement_hold_locked boolean
---@field pickup_token integer
---@field need_timer_token integer
---@field timeout_action_token integer
---@field need_countdown_remaining integer|nil
---@field timeout_action_anchor_pos Vector3|nil
---@field timeout_action_visual_cancelled boolean
---@field timeout_action_remaining integer|nil
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
    self.movement_hold_token = 0
    self.movement_held = false
    self.movement_hold_locked = false
    self.pickup_token = 0
    self.need_timer_token = 0
    self.timeout_action_token = 0
    self.need_countdown_remaining = nil
    self.timeout_action_anchor_pos = nil
    self.timeout_action_visual_cancelled = false
    self.timeout_action_remaining = nil
    self.timeout_move_locked = false
    self.ride_move_locked = false
    self.need_timeout_bonus_seconds = 0
    self.timeout_action_bonus_seconds = 0
    self.active_facility = nil
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

    -- Idle 与 Carried 都持续展示需求倒计时；其他忙碌状态保留各自的表现文案。
    if self:is_in_state(self.enum.BabyState.Idle)
        or self:is_in_state(self.enum.BabyState.Carried) then
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
    self.timeout_action_visual_cancelled = false
    self.timeout_action_remaining = duration
    local lifted = self:_is_lifted_now()
    Log.info("baby", self.index, "timeout action", duration)

    self:set_busy(true)
    if lifted then
        -- 已经处于被举起姿势时，只停止旧巡逻回调；stop_movement / 选装备槽都会
        -- 让引擎把被举起动作刷新成站立，因此地面动作准备必须完全跳过。
        self:cancel_patrol()
    else
        self:_prepare_timeout_action_pose()
    end
    self.pending_item = nil
    self.pending_purpose = nil
    self.is_rejecting = false
    self.pickup_token = self.pickup_token + 1

    if self.active_facility then
        self.services.facility:end_interaction(self, self.active_facility)
        self.active_facility = nil
    end

    self.view_model:add_stress(1)
    -- Timeout 是行为状态，抱起只取消其动作表现，不结束倒计时或刷新需求。
    self:set_lift_enabled(true)
    if lifted then
        self.timeout_action_visual_cancelled = true
        self:_unlock_timeout_move_state()
    else
        self:_lock_timeout_move_state()
        self:_play_timeout_action(duration)
    end
    self:_tick_timeout_action(token, duration)
end

function BabyAgent:_prepare_timeout_action_pose()
    self:cancel_patrol()
    self:stop_movement()
    self:select_equipped_slot()
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


function BabyAgent:_lock_timeout_move_state()
    -- BUFF_FORBID_MOVE 是计数型 buff，必须幂等，避免只移除一次后永久无法移动。
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

-- 骑滑板期间彻底锁住宝宝的 AI/移动，防止引擎因每帧 set_position 位移而触发
-- 待机/移动动画，把强制播放的骑行动作顶掉。与超时锁同款 BUFF，但独立计数。
function BabyAgent:lock_ride_move_state()
    if not self.ride_move_locked then
        if self.unit and self.unit.add_state then
            pcall(function()
                self.unit.add_state(Enums.BuffState.BUFF_FORBID_MOVE)
            end)
        end
        self.ride_move_locked = true
    end
    if self.unit and self.unit.stop_ai then
        pcall(function() self.unit.stop_ai() end)
    end
    if self.unit and self.unit.ai_command_stop_move then
        pcall(function() self.unit.ai_command_stop_move(0.1) end)
    end
    if self.unit and self.unit.set_attr_ratio_fixed then
        pcall(function() self.unit.set_attr_ratio_fixed("move_speed", 0.0) end)
    end
end

function BabyAgent:unlock_ride_move_state()
    if self.unit and self.ride_move_locked and self.unit.remove_state then
        pcall(function()
            self.unit.remove_state(Enums.BuffState.BUFF_FORBID_MOVE)
        end)
    end
    self.ride_move_locked = false
    if self.unit and self.unit.set_attr_ratio_fixed then
        pcall(function() self.unit.set_attr_ratio_fixed("move_speed", 1.0) end)
    end
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
    if self.destroyed or self.timeout_action_token ~= token
        or not self:is_in_state(self.enum.BabyState.Timeout) then
        return
    end

    self.timeout_action_remaining = remaining

    -- 补救窗口：Timeout 行为结束前仍持续判断当前需求。抱起过程中不启动 AI，
    -- 放下事件会立即再判一次，避免宝宝还在手里时切到寻物状态。
    if not self:_is_lifted_now() then
        local pos = self.unit and self.unit.get_position and self.unit.get_position()
        if pos and self:try_match_current_need_at(pos) then
            return
        end
    end

    if remaining <= 0 then
        self:finish_timeout_action(token)
        return
    end

    self:set_status("没满足！" .. tostring(remaining) .. "秒")
    -- 全身动作（如 23）单次播放约 1 秒后会被待机动画顶掉，这里每秒重发一次，
    -- 让“没满足”动作在整段超时时间内持续表现。
    if not self.timeout_action_visual_cancelled then
        self:_refresh_timeout_anim(remaining)
    end
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

function BabyAgent:_stop_timeout_action_visual()
    local action_id = self.config.baby.timeout_action_id or 23
    -- 只停止 Timeout 对应的全身动作。全局 stop_play_body_anim 会连同引擎当前的
    -- 被举起姿势一起重置成站立，不能用于抓举事件回调。
    if self.unit and self.unit.stop_play_body_anim_by_id then
        pcall(function()
            self.unit.stop_play_body_anim_by_id(action_id)
        end)
    elseif self.unit and self.unit.stop_play_body_anim_with_id then
        pcall(function()
            self.unit.stop_play_body_anim_with_id(action_id)
        end)
    elseif self.unit and self.unit.stop_play_body_anim then
        pcall(function()
            self.unit.stop_play_body_anim()
        end)
    elseif self.unit and self.unit.stop_anim then
        pcall(function()
            self.unit.stop_anim()
        end)
    end
end

-- 只取消动作表现，Timeout 行为状态、剩余时间和当前需求全部保留。
function BabyAgent:cancel_timeout_action_visual()
    if self.timeout_action_visual_cancelled then
        return
    end
    self.timeout_action_visual_cancelled = true
    self:_stop_timeout_action_visual()
end

-- 预留玩法函数（当前不调用）：主动拒绝本次 Timeout 抱起。
-- 未来可在 on_lifted_begin 中按概率调用，让抓举者立即放下宝宝。
---@param lift_unit Unit|LifeEntity|nil
---@return boolean
function BabyAgent:reject_timeout_lift_attempt(lift_unit)
    if self.destroyed or not self:is_in_state(self.enum.BabyState.Timeout) or not lift_unit then
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

-- 放下后若仍在 Timeout 且没有匹配到目标，恢复剩余时长的没满足动作。
function BabyAgent:resume_timeout_action_visual()
    local token = self.timeout_action_token
    -- 放下事件回调触发时，引擎的 lifted 标记和默认姿势可能尚未完成切换；
    -- 下一帧再恢复，避免恢复的 Timeout 动作又被放下默认站立覆盖。
    LuaAPI.call_delay_time(0.0333, function()
        if self.destroyed or self.timeout_action_token ~= token
            or not self:is_in_state(self.enum.BabyState.Timeout) or self:_is_lifted_now() then
            return
        end
        self.timeout_action_visual_cancelled = false
        self:_lock_timeout_move_state()
        self:_play_timeout_action(self.timeout_action_remaining or 1)
    end)
end

-- 离开 Timeout 状态时注销旧回调并清理表现；不会刷新当前需求。
function BabyAgent:cancel_timeout_action()
    local visual_cancelled = self.timeout_action_visual_cancelled
    self.timeout_action_token = self.timeout_action_token + 1
    self.timeout_action_anchor_pos = nil
    self.timeout_action_remaining = nil
    self.timeout_action_visual_cancelled = false
    self:_unlock_timeout_move_state()
    if not visual_cancelled then
        self:_stop_timeout_action_visual()
    end
end

---@param token integer
function BabyAgent:finish_timeout_action(token)
    if self.destroyed or self.timeout_action_token ~= token then
        return
    end

    local lifted = self:_is_lifted_now()
    local lift_unit = self.last_lift_unit
    local role = self.last_role
    local visual_cancelled = self.timeout_action_visual_cancelled
    self.timeout_action_anchor_pos = nil
    self.timeout_action_remaining = nil
    self:_unlock_timeout_move_state()
    if not visual_cancelled then
        self:_stop_timeout_action_visual()
    end

    self:choose_next_need()
    if lifted then
        self:enter_state(self.enum.BabyState.Carried, {
            lift_unit = lift_unit,
            role = role,
            suppress_lift_event = true,
        }, true)
    else
        self:enter_state(self.enum.BabyState.Idle, nil, true)
    end
end

function BabyAgent:cancel_patrol()
    self.patrol_token = self.patrol_token + 1
end

-- 独立的移动表现锁：不切换行为状态、不修改需求，扫描和倒计时照常运行。
---@param duration Fixed
function BabyAgent:hold_movement(duration)
    self.movement_hold_token = self.movement_hold_token + 1
    local token = self.movement_hold_token
    self.movement_held = true
    self:stop_movement()
    if not self.movement_hold_locked and self.unit and self.unit.add_state then
        pcall(function()
            self.unit.add_state(Enums.BuffState.BUFF_FORBID_MOVE)
        end)
        self.movement_hold_locked = true
    end

    LuaAPI.call_delay_time(duration, function()
        if self.destroyed or self.movement_hold_token ~= token then
            return
        end
        self.movement_held = false
        self:_unlock_movement_hold()
        if self:is_in_state(Enum.BabyState.Idle) and not self.view_model:is_busy() then
            self:_command_next_patrol_point(self.patrol_token)
        end
    end)
end

function BabyAgent:_unlock_movement_hold()
    if self.unit and self.movement_hold_locked and self.unit.remove_state then
        pcall(function()
            self.unit.remove_state(Enums.BuffState.BUFF_FORBID_MOVE)
        end)
    end
    self.movement_hold_locked = false
end

-- 再次抱起或检测到目标时提前解除，避免硬锁影响后续拾取/设施交互。
function BabyAgent:cancel_movement_hold()
    self.movement_hold_token = self.movement_hold_token + 1
    self.movement_held = false
    self:_unlock_movement_hold()
end

function BabyAgent:start_patrol()
    if not self.unit then
        return
    end

    self.patrol_token = self.patrol_token + 1
    local token = self.patrol_token
    if not self.movement_held then
        self:_command_next_patrol_point(token)
    end
    self:_scan_nearby_item(token)
end

-- 空闲/巡逻时就近扫描当前需求的物品：玩家把可拾取的小物件放到宝宝身边时，
-- 宝宝据此自己去捡。与巡逻共用 patrol_token，离开空闲（cancel_patrol/进入其它状态）
-- 即自动停止；只在不忙时反应（不打断正在进行的事），只认掉落在地上的系统物品。
---@param token integer
function BabyAgent:_scan_nearby_item(token)
    if self.destroyed or not self.unit or self.patrol_token ~= token then
        return
    end

    if not self.view_model:is_busy() then
        local pos = self.unit.get_position and self.unit.get_position()
        if pos then
            if self:try_match_current_need_at(pos) then
                return
            end
        end
    end

    LuaAPI.call_delay_time(self.config.baby.item_scan_interval, function()
        self:_scan_nearby_item(token)
    end)
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
    if self.destroyed or not self.unit or self.movement_held
        or self.view_model:is_busy() or self.patrol_token ~= token then
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
    if self.destroyed then
        return
    end

    self:cancel_movement_hold()

    local lift_unit = data and data.lift_unit or nil
    local role = RoleUtil.get_role_by_unit(lift_unit)
    if self:is_in_state(Enum.BabyState.Timeout) then
        self.last_lift_unit = lift_unit
        self.last_role = role
        self:cancel_timeout_action_visual()
        self:_unlock_timeout_move_state()
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
    if self:is_in_state(Enum.BabyState.Timeout) then
        self.last_lift_unit = nil
        self.last_role = nil
        if pos and self:try_match_current_need_at(pos) then
            return
        end
        self:resume_timeout_action_visual()
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

    if self:try_match_current_need_at(pos) then
        return
    end

    local wrong = self.services.item:nearest_to(pos)
    if wrong then
        -- 不是宝宝想要的：先捡到手上，之后再丢掉并表示不满意
        self:cancel_movement_hold()
        self:enter_state(Enum.BabyState.SeekingItem, { item = wrong, reason = "wrong_item" }, true)
    else
        self:hold_movement(self.config.baby.drop_move_hold_seconds)
        self:enter_idle()
    end
end

---@param pos Vector3
---@return boolean
function BabyAgent:try_match_current_need_at(pos)
    local facility = self:find_match_for_current_need(pos)
    if facility then
        self:cancel_movement_hold()
        self:enter_state(Enum.BabyState.InteractingFacility, { facility = facility }, true)
        return true
    end

    local item = self.services.item:nearest_match(pos, self.current_need)
    if item then
        self:cancel_movement_hold()
        self:enter_state(Enum.BabyState.SeekingItem, { item = item }, true)
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
    local radius = self.config.baby.contact_radius
    if baby_pos and item_pos and UnitUtil.distance_xz_sq(baby_pos, item_pos) <= radius * radius then
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

---@return nil
function BabyAgent:destroy()
    self.destroyed = true
    self:cancel_movement_hold()
    self:cancel_patrol()
    self:cancel_need_countdown()
    self.timeout_action_token = self.timeout_action_token + 1
    self.pickup_token = self.pickup_token + 1
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









