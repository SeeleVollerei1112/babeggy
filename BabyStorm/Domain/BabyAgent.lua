local Class = require("BaseClass")
local Enum = require("BabyStorm.Config.BabyStormEnum")
local BabyViewModel = require("BabyStorm.Domain.BabyViewModel")
local RoleUtil = require("Util.RoleUtil")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

local BabyAgent = Class("BabyAgent")

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
    self.patrol_token = 0
    self.pickup_token = 0
    self.destroyed = false
end

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

function BabyAgent:set_status(text)
    self.view_model:set_status_text(text or "")
end

function BabyAgent:set_busy(value)
    self.view_model:set_busy(value)
end

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
    self.current_need = self.services.need:take()
    if not self.current_need then
        self:set_status("没有需求")
        return
    end

    self.view_model:set_need(self.current_need)
    Log.info("baby", self.index, "need", self.current_need.id)
end

function BabyAgent:show_current_need()
    if self.current_need then
        self:set_status(self.current_need.need_text)
    end
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

function BabyAgent:_make_ground_target()
    local random = self.services.arena:random_point()
    local current = self.unit.get_position and self.unit.get_position() or random
    return math.Vector3(random.x, current.y, random.z)
end

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
    elseif state_id == Enum.BabyState.Upset then
        cls = require("BabyStorm.Domain.State.UpsetState")
    else
        cls = require("BabyStorm.Domain.State.StateBase")
    end

    local state = cls.New(self)
    state:init(state_id)
    return state
end

function BabyAgent:is_in_state(state_id)
    return self.active_state and self.active_state:get_state_id() == state_id and self.active_state:is_active()
end

function BabyAgent:enter_idle()
    return self:enter_state(Enum.BabyState.Idle)
end

function BabyAgent:enter_upset(context)
    return self:enter_state(Enum.BabyState.Upset, context, true)
end

function BabyAgent:on_lifted_begin(data)
    if self.destroyed or self.view_model:is_busy() then
        return
    end

    local lift_unit = data and data.lift_unit or nil
    local role = RoleUtil.get_role_by_unit(lift_unit)
    self:enter_state(Enum.BabyState.Carried, {
        lift_unit = lift_unit,
        role = role,
    }, true)
end

function BabyAgent:on_lifted_end(data)
    if self.destroyed or not self.unit or not self:is_in_state(Enum.BabyState.Carried) then
        return
    end

    local pos = self.unit.get_position and self.unit.get_position()
    if not pos then
        self:enter_idle()
        return
    end

    local item = self.services.item:nearest_match(pos, self.current_need)
    if item then
        self:enter_state(Enum.BabyState.SeekingItem, { item = item }, true)
        return
    end

    local wrong = self.services.item:nearest_to(pos)
    if wrong then
        self:enter_upset({ item = wrong, reason = "wrong_item" })
    else
        self:enter_idle()
    end
end

function BabyAgent:command_pickup(item)
    if not (self.unit and item and item.equipment) then
        self:enter_upset({ reason = "pickup_failed" })
        return
    end

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

function BabyAgent:_wait_for_pickup_result(item, token, elapsed)
    if self.destroyed or self.pending_item ~= item or self.pickup_token ~= token or not item or item.done then
        return
    end

    if self.services.item:item_owned_by_baby(item, self) then
        self:complete_item_obtained(item, 1)
        return
    end

    local baby_pos = self.unit.get_position and self.unit.get_position()
    local item_pos = item.equipment.get_position and item.equipment.get_position()
    local radius = self.config.baby.pickup_radius
    if baby_pos and item_pos and UnitUtil.distance_sq(baby_pos, item_pos) <= radius * radius then
        if self.services.item:force_pickup(self, item) then
            self:complete_item_obtained(item, 1)
            return
        end
    end

    if elapsed >= self.config.baby.pickup_timeout then
        self.pending_item = nil
        self:enter_upset({ reason = "pickup_timeout" })
        return
    end

    LuaAPI.call_delay_time(self.config.baby.pickup_check_interval, function()
        self:_wait_for_pickup_result(item, token, elapsed + self.config.baby.pickup_check_interval)
    end)
end

function BabyAgent:complete_item_obtained(item, count)
    if self.destroyed or not item or item.done then
        return
    end

    item.done = true
    self.pending_item = nil
    self:select_equipped_slot()
    self.services.item:remove(item)
    self.services.task:emit_baby_pick_item(self, item, count or 1)
    self:enter_state(Enum.BabyState.Satisfied, { item = item }, true)
end

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

function BabyAgent:destroy()
    self.destroyed = true
    self:cancel_patrol()
    self.pickup_token = self.pickup_token + 1
    self.pending_item = nil
    if self.view_model then
        self.view_model:clear()
    end
    self.states = {}
    self.state_list = {}
    self.active_state = nil
end

return BabyAgent
