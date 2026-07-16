local Class = require("BaseClass")
local MathX = require("Util.MathX")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

---@class BabyItemRecord
---@field def BabyNeedDef
---@field equipment Equipment
---@field done boolean
---@field restocked boolean -- 补给点的货被拿走后是否已在原处补过（见 _on_obtained）

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
    self:_clear_preplaced(needs)
    for index = 1, #needs do
        self:spawn_for_need(needs[index])
    end
end

-- 开局清场：把地图里预先摆好的同款食物全部销毁（货架上的样品、以及散落在场景各处的），
-- 随后由 spawn_for_need 在补给点重新生成。
-- 为什么必须清：这些预摆的物品不在 self.items 里，ItemService 的匹配只认自己生成的记录——
-- 玩家捡到它们看着一模一样，抱到宝宝身边却不算满足需求。留着必然让人以为是 bug。
---@param needs BabyNeedDef[]
function ItemService:_clear_preplaced(needs)
    local managed = {}
    for index = 1, #needs do
        managed[needs[index].item_key] = true
    end

    local list = GameAPI.get_all_equipments() or {}
    local removed = 0
    for index = 1, #list do
        local equipment = list[index]
        -- 逐件读 key/销毁：单件失败不该中断整轮清场。
        pcall(function()
            if managed[equipment.get_key()] then
                equipment.destroy_equipment()
                removed = removed + 1
            end
        end)
    end
    Log.info("item cleared preplaced", removed)
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

-- 生成一件物品：配了 shop_pos 就固定生成在小卖部补给点（食物走这条），否则场地内随机落点。
---@param need BabyNeedDef
---@return BabyItemRecord|nil
function ItemService:spawn_for_need(need)
    local pos = MathX.to_vector3(need.shop_pos) or self.arena:random_ground_point()
    local equipment = GameAPI.create_equipment(need.item_key, pos)
    if not equipment then
        Log.warn("failed to create equipment", need.id, need.item_key)
        return nil
    end

    self:_set_item_text(equipment, need)

    local item = {
        def = need,
        equipment = equipment,
        done = false,
        restocked = false,
    }

    self.items[#self.items + 1] = item
    if not self.triggers then
        Log.warn("missing trigger registry for item", need.id)
        return item
    end

    self.triggers:unit(equipment, { EVENT.SPEC_EQUIPMENT_OBTAIN }, function(event_name, actor, data)
        self:_on_obtained(item, data)
    end)
    return item
end

-- 补给点：货被拿走的那一刻就在原处补一件新的——玩家来取、宝宝自己捡都算，小卖部始终有货。
-- 只补一次（restocked 守卫）：SPEC_EQUIPMENT_OBTAIN 在这件货被反复捡起/丢下时会重复触发，
-- 每次都补的话，一件货能刷出一整排。
---@param item BabyItemRecord
---@param data table|nil
function ItemService:_on_obtained(item, data)
    if item.def.shop_pos and not item.restocked then
        item.restocked = true
        self:spawn_for_need(item.def)
    end
    if self._obtained_callback then
        self._obtained_callback(item, data)
    end
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

-- 宝宝吃掉/用掉一件物品：销毁它。
-- 补给点的货在「被拿起」那一刻就已经补过了（见 _on_obtained），这里不能再补，否则一件变两件。
-- 只有从没被补过的（restocked=false，即随机落点那类物品）才在这里补生成一件，维持场上总量。
---@param item BabyItemRecord|nil
function ItemService:consume(item)
    if not item then
        return
    end

    self:remove(item)
    if item.equipment and item.equipment.destroy_equipment then
        item.equipment.destroy_equipment()
    end
    if not item.restocked then
        self:spawn_for_need(item.def)
    end
end

-- 把玩具放回地上：与 consume 相对——不销毁、不出列，落地后还能被再次捡起。
-- 玩具是反复把玩的道具，不像食物那样一次性吃掉（见 PlayingToyState:exit）。
---@param item BabyItemRecord|nil
function ItemService:drop_to_ground(item)
    if not (item and item.equipment) then
        return
    end
    -- 装备单位可能已被回收销毁（清场/被抢走后销毁），保留 pcall。
    pcall(function()
        if item.equipment.set_droppable then
            item.equipment.set_droppable(true)
        end
        if item.equipment.drop then
            item.equipment.drop()
        end
    end)
end

-- 「还掉在世界里、可以被走过去捡」的判定，nearest_* 系列共用一份。
--
-- has_owner() 只报**装备槽位持有**：宝宝把玩具攥在手里时它是 true，因此把玩中的玩具
-- 不会被别的宝宝抢走；玩家正常拾取的物品同理跳过。
---@param item BabyItemRecord
---@return boolean
function ItemService:_is_on_ground(item)
    if item.done then
        return false
    end
    return not (item.equipment.has_owner and item.equipment.has_owner())
end

-- 就近找一件满足 accept 的地面物品；超出 radius 返回 nil。
---@param pos Vector3
---@param radius Fixed
---@param accept fun(item:BabyItemRecord):boolean
---@return BabyItemRecord|nil
function ItemService:_nearest_accepted(pos, radius, accept)
    local best = nil
    local best_dist = nil

    for index = 1, #self.items do
        local item = self.items[index]
        if self:_is_on_ground(item) and accept(item) then
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

    if best_dist and best_dist <= radius * radius then
        return best
    end
    return nil
end

---@param pos Vector3
---@param need BabyNeedDef|nil
---@return BabyItemRecord|nil
function ItemService:nearest_match(pos, need)
    return self:_nearest_accepted(pos, self.config.baby.item_pickup_radius, function(item)
        -- need 缺省＝不挑物品（nearest_to 的“附近有什么捡什么”）；给了 need 却没有 resolver
        -- 时一律不匹配——宁可不捡，也不能在规则缺席时乱认。
        if not need then
            return true
        end
        if not self.resolver then
            return false
        end
        return self.resolver:item_matches_need(item, need)
    end)
end

-- 就近找一件可把玩的玩具，无视当前需求：给 Idle 的「随手捡玩具」用。
-- 与 nearest_match 的区别是不看需求、半径由调用方给（随手捡的搜索范围比取物大）。
---@param pos Vector3
---@param radius Fixed
---@return BabyItemRecord|nil
function ItemService:nearest_playable(pos, radius)
    return self:_nearest_accepted(pos, radius, function(item)
        return item.def.playable == true
    end)
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
