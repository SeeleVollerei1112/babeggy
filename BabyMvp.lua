local Prefab = require("Data.Prefab")
local UINodes = require("Data.UINodes")
local TaskEvents = require("Util.TaskEvents")

local BabyMvp = {}

local BABY_PREFAB_ID = 1073741937
local BABY_COUNT = 3
local TUTORIAL_AREA_NAME = "tutorial_area"
local PICKUP_RADIUS = 4.0
local PICKUP_CHECK_INTERVAL = 0.25
local PICKUP_TIMEOUT = 5.0
local PICKUP_MOVE_SPEED_RATIO = 2.0
local SCORE_REWARD = 10
local SATISFIED_REACT_TIME = 3.0
local GROUND_RAY_UP = 50.0
local GROUND_RAY_DOWN = 100.0

local ITEMS = {
    { key = 1073774699, text = "喝奶昔", name = "草莓奶昔" },
    { key = 1073786889, text = "吃冰淇淋", name = "冰淇淋" },
    { key = 1073795131, text = "吃蛋糕", name = "提拉米苏" },
}

local state = {
    area = nil,
    babies = {},
    items = {},
    need_bag = {},
    started = false,
}

local function log(message)
    LuaAPI.log("[BabyMvp] " .. tostring(message), 0)
end

local function get_id(unit)
    if unit and unit.get_id then
        return unit.get_id()
    end
    return nil
end

local function same_unit(a, b)
    if a == b then
        return true
    end
    local a_id = get_id(a)
    local b_id = get_id(b)
    return a_id ~= nil and b_id ~= nil and a_id == b_id
end

local function get_role_by_unit(unit)
    if not unit then
        return nil
    end

    if unit.get_owner then
        local owner = unit.get_owner()
        if owner then
            return owner
        end
    end

    if unit.get_role_id then
        local role_id = unit.get_role_id()
        if role_id then
            return GameAPI.get_role(role_id)
        end
    end

    local roles = GameAPI.get_all_valid_roles()
    for _, role in ipairs(roles) do
        local ctrl = role.get_ctrl_unit and role.get_ctrl_unit()
        if same_unit(ctrl, unit) then
            return role
        end
    end

    return nil
end

local function emit_for_baby(baby, event_name, extra)
    if baby.last_role then
        TaskEvents.emit(baby.last_role, event_name, extra)
    else
        TaskEvents.emit_all(event_name, extra)
    end
end

local function rand_index(count)
    return math.tointeger((LuaAPI.rand() % count) + 1)
end

local function refill_need_bag()
    state.need_bag = {}
    for _, item in ipairs(ITEMS) do
        table.insert(state.need_bag, item)
    end

    for index = #state.need_bag, 2, -1 do
        local swap_index = rand_index(index)
        state.need_bag[index], state.need_bag[swap_index] = state.need_bag[swap_index], state.need_bag[index]
    end
end

local function take_need()
    if #state.need_bag <= 0 then
        refill_need_bag()
    end
    return table.remove(state.need_bag)
end

local function random_point()
    if state.area and state.area.random_point then
        return state.area.random_point()
    end
    if state.area and state.area.get_customtriggerspaces_random_point then
        return state.area.get_customtriggerspaces_random_point()
    end
    return math.Vector3(0, 1, 0)
end

local function distance_sq(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

-- 区域随机点的 Y 可能在触发体的高度上，直接生成物品会飘在半空。
-- 从随机点上方向下打射线，取命中的最高地表，把物品落到地板上。
local function ground_point(point)
    local start_pos = math.Vector3(point.x, point.y + GROUND_RAY_UP, point.z)
    local end_pos = math.Vector3(point.x, point.y - GROUND_RAY_DOWN, point.z)
    local best_y = nil

    GameAPI.raycast_unit(start_pos, end_pos, { Enums.UnitType.OBSTACLE }, function(unit, hit_pos, normal)
        if hit_pos and (not best_y or hit_pos.y > best_y) then
            best_y = hit_pos.y
        end
    end)

    if best_y then
        return math.Vector3(point.x, best_y, point.z)
    end
    return point
end

local function set_all_role_scene_label(layer, text)
    if not layer then
        return
    end

    local label = GameAPI.get_eui_node_at_scene_ui(layer, UINodes.reaction_bubble_lbl)
    if not label then
        return
    end

    local roles = GameAPI.get_all_valid_roles()
    for _, role in ipairs(roles) do
        role.set_label_text(label, text)
    end
end

local function set_baby_status(baby, text)
    baby.status_text = text
    set_all_role_scene_label(baby.scene_ui, text)
    if baby.unit and baby.unit.show_bubble_msg then
        baby.unit.show_bubble_msg(text, 2.0, 20.0, math.Vector3(0, 1.5, 0))
    end
end

local function set_item_text(equipment, item_def)
    if equipment.set_name then
        equipment.set_name(item_def.text)
    end
    if equipment.set_desc then
        equipment.set_desc(item_def.name)
    end

    local unit = equipment.get_unit and equipment.get_unit()
    if unit then
        if unit.enable_interact then
            unit.enable_interact()
        end
        if unit.set_interact_button_text_by_index then
            unit.set_interact_button_text_by_index(1, item_def.text)
        end
    end
end

local function find_baby_by_unit(unit)
    for _, baby in ipairs(state.babies) do
        if same_unit(baby.unit, unit) then
            return baby
        end
    end
    return nil
end

local function remove_item_record(equipment)
    for index, item in ipairs(state.items) do
        if item.equipment == equipment then
            table.remove(state.items, index)
            return item
        end
    end
    return nil
end

local spawn_item

local function same_equipment(a, b)
    if a == b then
        return true
    end
    if not a or not b then
        return false
    end

    local a_unit = a.get_unit and a.get_unit()
    local b_unit = b.get_unit and b.get_unit()
    return same_unit(a_unit, b_unit)
end

local function baby_has_equipment(item, baby)
    if not baby.unit.get_equipment_list then
        return false
    end

    local list = baby.unit.get_equipment_list(item.def.key, false, false)
    if not list then
        return false
    end

    for _, equipment in ipairs(list) do
        if same_equipment(equipment, item.equipment) then
            return true
        end
    end

    return false
end

local function item_owned_by_baby(item, baby)
    if not item or not item.equipment or not baby or not baby.unit then
        return false
    end

    if baby_has_equipment(item, baby) then
        return true
    end

    if item.equipment.has_owner and not item.equipment.has_owner() then
        return false
    end

    if item.equipment.get_owner_creature then
        local owner = item.equipment.get_owner_creature()
        if owner and same_unit(owner, baby.unit) then
            return true
        end
    end

    return false
end

local function show_current_need(baby)
    if baby.need then
        set_baby_status(baby, "想要" .. baby.need.text)
    end
end

local function choose_need(baby)
    baby.need = take_need()
    log("baby " .. tostring(baby.index) .. " need " .. tostring(baby.need.key) .. " " .. baby.need.text)
    show_current_need(baby)
end

local function make_ground_target(unit)
    local random = random_point()
    local current = unit.get_position()
    return math.Vector3(random.x, current.y, random.z)
end

local function command_next_patrol_point(baby, token)
    if not baby.unit or baby.busy or baby.patrol_token ~= token then
        return
    end

    local current = baby.unit.get_position()
    local target = make_ground_target(baby.unit)
    baby.unit.set_attr_ratio_fixed("move_speed", 0.0)
    baby.unit.start_move_to_pos_with_threshold(target, 4.0, 0.5)
    log("baby " ..
        tostring(baby.index) ..
        " patrol from " ..
        tostring(current.x) ..
        "," ..
        tostring(current.y) ..
        "," ..
        tostring(current.z) .. " to " .. tostring(target.x) .. "," .. tostring(target.y) .. "," .. tostring(target.z))

    LuaAPI.call_delay_time(1.0, function()
        if baby.unit and not baby.busy and baby.patrol_token == token then
            local after = baby.unit.get_position()
            log("baby " .. tostring(baby.index) .. " patrol moved d2=" .. tostring(distance_sq(current, after)))
        end
    end)

    LuaAPI.call_delay_time(4.0, function()
        command_next_patrol_point(baby, token)
    end)
end

local function set_baby_lift_enabled(baby, enabled)
    if baby.unit and baby.unit.set_lifted_enabled then
        baby.unit.set_lifted_enabled(enabled)
    end
end

local function start_patrol(baby)
    if not baby.unit then
        return
    end

    baby.busy = false
    set_baby_lift_enabled(baby, true)
    baby.patrol_token = (baby.patrol_token or 0) + 1
    command_next_patrol_point(baby, baby.patrol_token)
end

local function select_baby_equipped_slot(baby)
    if baby.unit and baby.unit.set_selected_equipment_slot then
        baby.unit.set_selected_equipment_slot(Enums.EquipmentSlotType.EQUIPPED, 1)
    end
end

local function cleanup_item_and_continue(baby, item)
    if item.equipment and item.equipment.destroy_equipment then
        item.equipment.destroy_equipment()
    end

    spawn_item(item.def)
    choose_need(baby)
    start_patrol(baby)
end

local function finish_satisfied(baby, item)
    set_baby_status(baby, "满足了")
    emit_for_baby(baby, TaskEvents.EVENTS.BABY_SATISFIED, {
        baby = baby.unit,
        item_id = item.def.key,
        need = baby.need.text,
        amount = 1,
    })
    if baby.last_role and baby.last_role.add_score then
        baby.last_role.add_score(SCORE_REWARD)
        baby.last_role.show_tips("宝宝满足 +" .. tostring(SCORE_REWARD), 2.0)
    else
        GlobalAPI.show_tips("宝宝满足 +" .. tostring(SCORE_REWARD), 2.0)
    end
end

-- 宝宝只会拾取与需求一致的物品（见 on_baby_lifted_end），所以拾取成功必然是满足。
local function finish_interaction(baby, item)
    baby.busy = true
    set_baby_lift_enabled(baby, false)
    baby.unit.stop_ai()
    baby.unit.ai_command_stop_move(0.1)
    select_baby_equipped_slot(baby)

    set_baby_status(baby, item.def.text)
    LuaAPI.call_delay_time(SATISFIED_REACT_TIME, function()
        finish_satisfied(baby, item)
        cleanup_item_and_continue(baby, item)
    end)
end

local function complete_item_obtained(baby, item, count)
    if item.done then
        return
    end

    item.done = true
    baby.pending_item = nil
    log("item obtained " .. tostring(item.def.key))
    select_baby_equipped_slot(baby)
    remove_item_record(item.equipment)

    emit_for_baby(baby, TaskEvents.EVENTS.BABY_PICK_ITEM, {
        baby = baby.unit,
        item_id = item.def.key,
        need = baby.need and baby.need.text or nil,
        amount = count or 1,
    })

    finish_interaction(baby, item)
end

local function on_item_obtained(item, data)
    local baby = find_baby_by_unit(data.owner)
    if not baby then
        return
    end

    complete_item_obtained(baby, item, data.count or 1)
end

local function force_pickup_item(baby, item)
    if not baby.unit or not baby.unit.swap_equipment_slot then
        return false
    end

    baby.unit.swap_equipment_slot(item.equipment, Enums.EquipmentSlotType.EQUIPPED, 1)
    select_baby_equipped_slot(baby)
    log("pickup force slot " .. tostring(item.def.key))
    return true
end

local function wait_for_pickup_result(baby, item, token, elapsed)
    if baby.pending_item ~= item or baby.pickup_token ~= token or item.done then
        return
    end

    if item_owned_by_baby(item, baby) then
        log("pickup fallback confirmed " .. tostring(item.def.key))
        complete_item_obtained(baby, item, 1)
        return
    end

    local baby_pos = baby.unit.get_position and baby.unit.get_position()
    local item_pos = item.equipment.get_position and item.equipment.get_position()
    if baby_pos and item_pos and distance_sq(baby_pos, item_pos) <= PICKUP_RADIUS * PICKUP_RADIUS then
        if force_pickup_item(baby, item) then
            complete_item_obtained(baby, item, 1)
            return
        end
    end

    if elapsed >= PICKUP_TIMEOUT then
        log("pickup timeout " .. tostring(item.def.key))
        baby.pending_item = nil
        show_current_need(baby)
        start_patrol(baby)
        return
    end

    LuaAPI.call_delay_time(PICKUP_CHECK_INTERVAL, function()
        wait_for_pickup_result(baby, item, token, elapsed + PICKUP_CHECK_INTERVAL)
    end)
end

spawn_item = function(item_def)
    local equipment = GameAPI.create_equipment(item_def.key, ground_point(random_point()))
    set_item_text(equipment, item_def)

    local item = {
        def = item_def,
        equipment = equipment,
    }

    table.insert(state.items, item)
    LuaAPI.unit_register_trigger_event(equipment, { EVENT.SPEC_EQUIPMENT_OBTAIN }, function(event_name, actor, data)
        on_item_obtained(item, data)
    end)

    return item
end

local function nearest_item_to(pos, need_key)
    local best = nil
    local best_dist = nil

    for _, item in ipairs(state.items) do
        if not need_key or item.def.key == need_key then
            local item_pos = item.equipment.get_position and item.equipment.get_position()
            if item_pos then
                local dist = distance_sq(pos, item_pos)
                if not best_dist or dist < best_dist then
                    best = item
                    best_dist = dist
                end
            end
        end
    end

    if best_dist and best_dist <= PICKUP_RADIUS * PICKUP_RADIUS then
        return best
    end
    return nil
end

local function on_baby_lifted_begin(baby, data)
    if baby.busy then
        return
    end

    baby.patrol_token = (baby.patrol_token or 0) + 1
    baby.last_lift_unit = data.lift_unit
    baby.last_role = get_role_by_unit(data.lift_unit)
    baby.busy = true
    baby.unit.ai_command_stop_move(0.1)
    baby.unit.stop_ai()

    set_baby_status(baby, "被抱起")
    emit_for_baby(baby, TaskEvents.EVENTS.LIFT_BABY, {
        baby = baby.unit,
        lift_unit = data.lift_unit,
        need = baby.need and baby.need.text or nil,
        amount = 1,
    })
end

local function on_baby_lifted_end(baby)
    if baby.busy and not baby.last_lift_unit then
        return
    end

    local pos = baby.unit.get_position()
    local need_key = baby.need and baby.need.key
    local item = nearest_item_to(pos, need_key)

    if item then
        set_baby_status(baby, "去" .. item.def.text)
        emit_for_baby(baby, TaskEvents.EVENTS.NEED_MATCHED, {
            baby = baby.unit,
            item_id = item.def.key,
            need = baby.need and baby.need.text or nil,
            amount = 1,
        })
        baby.unit.start_ai()
        baby.pending_item = item
        baby.pickup_token = (baby.pickup_token or 0) + 1
        local token = baby.pickup_token
        log("baby " .. tostring(baby.index) .. " pick item " .. tostring(item.def.key))
        baby.unit.set_attr_ratio_fixed("move_speed", PICKUP_MOVE_SPEED_RATIO)
        baby.unit.ai_command_pick_up_equipment(item.equipment, Enums.MoveMode.DIRECT, 0.2)

        LuaAPI.call_delay_time(PICKUP_CHECK_INTERVAL, function()
            wait_for_pickup_result(baby, item, token, PICKUP_CHECK_INTERVAL)
        end)
    else
        -- 附近没有"想要"的物品：如果旁边有别的物品，说明拿错了，给个提示但不拾取。
        local wrong = nearest_item_to(pos)
        if wrong then
            emit_for_baby(baby, TaskEvents.EVENTS.WRONG_ITEM, {
                baby = baby.unit,
                item_id = wrong.def.key,
                need = baby.need and baby.need.text or nil,
                amount = 1,
            })
            if baby.last_role and baby.last_role.show_tips then
                baby.last_role.show_tips("不是想要的", 1.5)
            else
                GlobalAPI.show_tips("不是想要的", 1.5)
            end
        end
        show_current_need(baby)
        start_patrol(baby)
    end
end

local function create_baby(index)
    local baby = {
        index = index,
        unit = GameAPI.create_life_entity(BABY_PREFAB_ID, random_point(), math.Quaternion(0, 0, 0), 1.0, nil),
        need = nil,
        scene_ui = nil,
        last_role = nil,
        busy = false,
    }

    baby.unit.set_lifted_enabled(true)
    baby.unit.set_ai_move_threshold(0.5)
    if baby.unit.set_equipment_max_count then
        baby.unit.set_equipment_max_count(Enums.EquipmentSlotType.EQUIPPED, 1)
    end

    if Prefab.scene_eui and Prefab.scene_eui.reaction_bubble_canvas then
        baby.scene_ui = baby.unit.create_scene_ui_bind_unit(
            Prefab.scene_eui.reaction_bubble_canvas,
            Enums.ModelSocket.socket_head,
            math.Vector3(0, 1.5, 0),
            999999.0,
            true,
            true
        )
    end

    LuaAPI.unit_register_trigger_event(baby.unit, { EVENT.SPEC_LIFEENTITY_LIFTED_BEGIN },
        function(event_name, actor, data)
            on_baby_lifted_begin(baby, data)
        end)

    LuaAPI.unit_register_trigger_event(baby.unit, { EVENT.SPEC_LIFEENTITY_LIFTED_END }, function(event_name, actor, data)
        on_baby_lifted_end(baby, data)
    end)

    choose_need(baby)
    start_patrol(baby)
    table.insert(state.babies, baby)
end

function BabyMvp.start()
    if state.started then
        return
    end
    state.started = true

    state.area = LuaAPI.query_unit(TUTORIAL_AREA_NAME)
    if not state.area then
        log("missing trigger area: " .. TUTORIAL_AREA_NAME)
        GlobalAPI.show_tips("未找到触发区 tutorial_area", 3.0)
        return
    end

    for _, item_def in ipairs(ITEMS) do
        spawn_item(item_def)
    end

    for index = 1, BABY_COUNT do
        create_baby(index)
    end

    log("started")
end

return BabyMvp
