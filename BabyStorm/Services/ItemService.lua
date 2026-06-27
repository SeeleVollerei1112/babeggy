local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

---@class BabyItemRecord
---@field def BabyNeedDef
---@field equipment Equipment
---@field done boolean

---@alias ItemObtainedCallback fun(item:BabyItemRecord, data:table|nil)

---@class ItemService
---@field config BabyStormConfig
---@field arena ArenaService
---@field resolver NeedResolver|nil
---@field items BabyItemRecord[]
---@field _obtained_callback ItemObtainedCallback|nil
---@field triggers TriggerRegistry|nil
local ItemService = Class("ItemService")

---@param config BabyStormConfig
---@param arena ArenaService
function ItemService:Ctor(config, arena)
    self.config = config
    self.arena = arena
    self.items = {}
    self._obtained_callback = nil
    self.triggers = nil
end

---@param callback ItemObtainedCallback
function ItemService:on_obtained(callback)
    self._obtained_callback = callback
end

---@param triggers TriggerRegistry
function ItemService:set_trigger_registry(triggers)
    self.triggers = triggers
end

---@return nil
function ItemService:init()
    local needs = self.resolver and self.resolver:get_spawnable_equipment_needs() or self.config.needs
    for index = 1, #needs do
        self:spawn_for_need(needs[index])
    end
end

---@param resolver NeedResolver
function ItemService:set_need_resolver(resolver)
    self.resolver = resolver
end

---@param equipment Equipment|nil
---@param need BabyNeedDef
function ItemService:_set_item_text(equipment, need)
    if not equipment then
        return
    end

    -- 只改名字/描述。拾取交互交给物品预设自带的交互配置，脚本不再调用
    -- enable_interact / set_interact_button_text，避免覆盖掉预设里配好的交互。
    if equipment.set_name then
        equipment.set_name(need.action_text)
    end
    if equipment.set_desc then
        equipment.set_desc(need.item_name)
    end
end

---@param need BabyNeedDef
---@return BabyItemRecord|nil
function ItemService:spawn_for_need(need)
    local equipment = GameAPI.create_equipment(need.item_key, self.arena:random_ground_point())
    if not equipment then
        Log.warn("failed to create equipment", need.id, need.item_key)
        return nil
    end

    self:_set_item_text(equipment, need)

    local item = {
        def = need,
        equipment = equipment,
        done = false,
    }

    self.items[#self.items + 1] = item
    if not self.triggers then
        Log.warn("missing trigger registry for item", need.id)
        return item
    end

    self.triggers:unit(equipment, { EVENT.SPEC_EQUIPMENT_OBTAIN }, function(event_name, actor, data)
        if self._obtained_callback then
            self._obtained_callback(item, data)
        end
    end)
    return item
end

---@param item BabyItemRecord|nil
function ItemService:remove(item)
    if not item then
        return
    end

    for index = #self.items, 1, -1 do
        if self.items[index] == item then
            table.remove(self.items, index)
            break
        end
    end
end

---@param item BabyItemRecord|nil
function ItemService:destroy_and_respawn(item)
    if not item then
        return
    end

    self:remove(item)
    if item.equipment and item.equipment.destroy_equipment then
        item.equipment.destroy_equipment()
    end
    self:spawn_for_need(item.def)
end

---@param pos Vector3
---@param need BabyNeedDef|nil
---@return BabyItemRecord|nil
function ItemService:nearest_match(pos, need)
    local best = nil
    local best_dist = nil

    for index = 1, #self.items do
        local item = self.items[index]
        local matches = not need
        if need and self.resolver then
            matches = self.resolver:item_matches_need(item, need)
        end

        -- 被玩家/生物持有的物品不算“放在地上”，跳过：只认掉落在世界里的物品，
        -- 避免宝宝去追别人手里还拿着的东西（“放到身边”才触发需求判断）
        local held = item.equipment.has_owner and item.equipment.has_owner()
        if not item.done and matches and not held then
            local item_pos = item.equipment.get_position and item.equipment.get_position()
            if item_pos then
                local dist = UnitUtil.distance_xz_sq(pos, item_pos)
                if not best_dist or dist < best_dist then
                    best = item
                    best_dist = dist
                end
            end
        end
    end

    local radius = self.config.baby.item_pickup_radius
    if best_dist and best_dist <= radius * radius then
        return best
    end
    return nil
end

---@param pos Vector3
---@param need_key integer|nil
---@return BabyItemRecord|nil
function ItemService:nearest_to(pos, need_key)
    local synthetic_need = need_key and { item_key = need_key, resolver = "equipment" } or nil
    return self:nearest_match(pos, synthetic_need)
end

---@param a Equipment|nil
---@param b Equipment|nil
---@return boolean
local function same_equipment(a, b)
    if a == b then
        return true
    end
    if not a or not b then
        return false
    end
    local a_unit = a.get_unit and a.get_unit()
    local b_unit = b.get_unit and b.get_unit()
    return UnitUtil.same_unit(a_unit, b_unit)
end

---@param item BabyItemRecord|nil
---@param baby BabyAgent|nil
---@return boolean
function ItemService:baby_has_equipment(item, baby)
    if not (item and baby and baby.unit and baby.unit.get_equipment_list) then
        return false
    end

    local list = baby.unit.get_equipment_list(item.def.item_key, false, false)
    if not list then
        return false
    end

    for index = 1, #list do
        if same_equipment(list[index], item.equipment) then
            return true
        end
    end
    return false
end

---@param item BabyItemRecord|nil
---@param baby BabyAgent|nil
---@return boolean
function ItemService:item_owned_by_baby(item, baby)
    if not (item and item.equipment and baby and baby.unit) then
        return false
    end

    if self:baby_has_equipment(item, baby) then
        return true
    end
    if item.equipment.has_owner and not item.equipment.has_owner() then
        return false
    end
    if item.equipment.get_owner_creature then
        local owner = item.equipment.get_owner_creature()
        if owner and UnitUtil.same_unit(owner, baby.unit) then
            return true
        end
    end
    return false
end

---@param baby BabyAgent|nil
---@param item BabyItemRecord|nil
---@return boolean
function ItemService:force_pickup(baby, item)
    if not (baby and baby.unit and baby.unit.swap_equipment_slot and item and item.equipment) then
        return false
    end
    baby.unit.swap_equipment_slot(item.equipment, Enums.EquipmentSlotType.EQUIPPED, 1)
    Log.info("force pickup", item.def.id, "baby", baby.index)
    return true
end

---@return nil
function ItemService:destroy()
    for index = #self.items, 1, -1 do
        local item = self.items[index]
        if item.equipment and item.equipment.destroy_equipment then
            item.equipment.destroy_equipment()
        end
    end
    self.items = {}
end

return ItemService
