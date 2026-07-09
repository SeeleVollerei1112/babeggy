local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

-- 设施注册表（无状态能力层）。原 FacilityService 瘦身而来：只负责
--   注册（按名字/实体ID 解析设施单位）、就近匹配、按 kind 查询、
--   互动按钮配置、交互 begin/end 自定义事件发送、“是否宝宝”判定。
-- 木偶戏（座位跟随/施力/巡游/骑手跟随）全部在 Domain/Interaction 子状态 + Core/Drivers；
-- 占用（active_agent）与交互生命周期由 InteractingFacilityState 拥有，本表只存记录。

---@class BabyFacilityRecord
---@field def BabyNeedDef
---@field unit Unit|nil
---@field area Unit|nil
---@field contact_area Unit|nil
---@field active_agent BabyAgent|nil      -- 占用者，由 InteractingFacilityState enter/exit 写
---@field orient_unit Unit|nil            -- 坐姿朝向源（投石车投臂），由 CatapultInteraction 解析缓存
---@field crib_session CribCareSession|nil -- 以下 crib_* 字段由 CribService 拥有（Phase 5 迁移）
---@field crib_tilted boolean|nil
---@field crib_reset_progress number|nil
---@field crib_reset_pressing any
---@field crib_upright_rot Quaternion|nil
---@field crib_progress_layer any
---@field crib_progress_node any

---@class FacilityRegistry
---@field config BabyStormConfig
---@field resolver NeedResolver|nil
---@field facilities BabyFacilityRecord[]
local FacilityRegistry = Class("FacilityRegistry")

---@param config BabyStormConfig
function FacilityRegistry:Ctor(config)
    self.config = config
    self.resolver = nil
    self.facilities = {}
    self._is_baby_unit = nil
end

---@param resolver NeedResolver
function FacilityRegistry:set_need_resolver(resolver)
    self.resolver = resolver
end

---注入“是否宝宝单位”判定。宝宝也是 character，滑板等交互必须靠它把宝宝从“踩板玩家”里排除掉。
---@param fn fun(unit:Unit|LifeEntity|nil):boolean
function FacilityRegistry:set_baby_unit_filter(fn)
    self._is_baby_unit = fn
end

---@param unit Unit|LifeEntity|nil
---@return boolean
function FacilityRegistry:is_baby(unit)
    return self._is_baby_unit ~= nil and self._is_baby_unit(unit) or false
end

-- ============================================================
-- 注册
-- ============================================================

---@return nil
function FacilityRegistry:init()
    local needs = self.config.needs
    for index = 1, #needs do
        local need = needs[index]
        if self.resolver and self.resolver:is_facility_need(need) then
            self:_register_facility(need)
        end
    end
end

-- 一个 need 可对应多个可互换的设施单位（如两个秋千座椅）：facility_names 列表里每个名字
-- 各注册一条共享同一 def 的记录，nearest_match 会就近挑空闲的那个。退化到单个 facility_name。
---@param need BabyNeedDef
function FacilityRegistry:_register_facility(need)
    local names = need.facility_names
    local ids = need.facility_unit_ids
    local registered = false
    if names and #names > 0 then
        for index = 1, #names do
            self:_register_facility_unit(need, names[index])
        end
        registered = true
    end
    -- 也支持按“实体ID”注册（投石臂等只有 id 没有稳定名字的组件）。
    if ids and #ids > 0 then
        for index = 1, #ids do
            self:_register_facility_unit(need, nil, GameAPI.get_unit(ids[index]))
        end
        registered = true
    end
    if not registered then
        self:_register_facility_unit(need, need.facility_name)
    end
end

---@param need BabyNeedDef
---@param facility_name string|nil
---@param unit_override Unit|nil 已解析的设施单位（按 id 注册时传入）
---@return BabyFacilityRecord
function FacilityRegistry:_register_facility_unit(need, facility_name, unit_override)
    local unit = unit_override or (facility_name and LuaAPI.query_unit(facility_name)) or nil
    local area = need.area_name and LuaAPI.query_unit(need.area_name) or nil
    local contact_area = need.contact_area_name and LuaAPI.query_unit(need.contact_area_name) or nil

    if not unit then
        Log.warn("missing facility unit", need.id, facility_name)
    end
    if not area then
        Log.warn("missing facility area", need.id, need.area_name)
    end
    if need.contact_area_name and not contact_area then
        Log.warn("missing facility contact area", need.id, need.contact_area_name)
    end

    self:_configure_facility_unit(unit, need)

    local facility = {
        def = need,
        unit = unit,
        area = area,
        contact_area = contact_area,
        active_agent = nil,
    }
    self.facilities[#self.facilities + 1] = facility
    -- 诊断：打出设施解析到的单位坐标，便于核对“投臂原点离放下点多远”。
    if unit then
        local p = unit.get_position()
        if p then
            Log.info("facility registered", need.id, facility_name or "(by-id)", "pos", p.x, p.y, p.z)
        end
    end
    return facility
end

---@param unit Unit|nil
---@param need BabyNeedDef
function FacilityRegistry:_configure_facility_unit(unit, need)
    if not unit then
        return
    end

    -- 载具/秋千座椅/婴儿床/投石车不挂玩家互动按钮：交互由“玩家把宝宝抱来放下”触发，避免玩家自己按键。
    -- 婴儿床的取物/换洗/扶正都走 CribService 的场景 UI，同样不需要单位自带的互动按钮。
    if need.facility_kind == "vehicle" or need.facility_kind == "swing_seat"
        or need.facility_kind == "crib" or need.facility_kind == "catapult" then
        return
    end

    unit.enable_interact()
    unit.set_interact_button_text_by_index(1, need.action_text)
    self:_set_interact_button_text(unit, Enums.InteractBtnType.UNIT_START, need.action_text)
    self:_set_interact_button_text(unit, Enums.InteractBtnType.UNIT_STOP, "结束" .. need.action_text)
end

---@param unit Unit
---@param btn_type integer
---@param text string
function FacilityRegistry:_set_interact_button_text(unit, btn_type, text)
    local interact_id = unit.get_interact_id(1, btn_type)
    if interact_id then
        unit.set_interact_button_text(interact_id, text)
    end
end

-- ============================================================
-- 查询
-- ============================================================

---@param kind string
---@return BabyFacilityRecord[]
function FacilityRegistry:get_facilities_by_kind(kind)
    local result = {}
    for index = 1, #self.facilities do
        local facility = self.facilities[index]
        if facility.def and facility.def.facility_kind == kind then
            result[#result + 1] = facility
        end
    end
    return result
end

---@param unit Unit|LifeEntity|nil
---@param area Unit|nil
---@return boolean
function FacilityRegistry:_unit_in_area(unit, area)
    if not (unit and area) then
        return false
    end
    if unit.is_in_customtriggerspace(area, true) then
        return true
    end
    local pos = unit.get_position()
    return (pos and GameAPI.is_point_in_customtriggerspace(pos, area)) or false
end

---@param pos Vector3|nil
---@param need BabyNeedDef
---@param baby_unit Unit|LifeEntity|nil
---@return BabyFacilityRecord|nil
function FacilityRegistry:nearest_match(pos, need, baby_unit)
    local best = nil
    local best_dist = nil
    for index = 1, #self.facilities do
        local facility = self.facilities[index]
        -- 歪掉的婴儿床（crib_tilted）在扶正前不可再放宝宝：跳过它，就近选另一张可用的床。
        if self.resolver and self.resolver:item_matches_need(facility, need)
            and not facility.active_agent and not facility.crib_tilted then
            -- 只有显式配置的近身接触区能触发交互。area 可能是滑板的整个巡游范围，
            -- 不能把它当接触区，否则宝宝在区域任意位置都会被远距离送上设施。
            if facility.contact_area and self:_unit_in_area(baby_unit, facility.contact_area) then
                return facility
            end
            -- 没有专用接触区或区域判定未命中时，只按地面水平距离贴近设施本体。
            -- 设施与宝宝枢轴高度不同，计入 Y 会导致站在正上方容易命中、两侧反而困难。
            if pos and facility.unit then
                local facility_pos = facility.unit.get_position()
                if facility_pos then
                    local dist = UnitUtil.distance_xz_sq(pos, facility_pos)
                    if not best_dist or dist < best_dist then
                        best = facility
                        best_dist = dist
                    end
                end
            end
        end
    end

    local radius = (best and best.def and best.def.contact_radius) or self.config.baby.contact_radius
    if best_dist and best_dist <= radius * radius then
        return best
    end
    -- 诊断：有候选但距离超出接触半径 → 打出实际距离与半径，方便判断是加大 radius 还是投臂原点不对。
    if best and best.def then
        Log.info("facility match miss", best.def.id,
            "dist", best_dist and math.sqrt(best_dist) or -1.0, "radius", radius)
    end
    return nil
end

-- ============================================================
-- 交互自定义事件（begin/end，由 InteractingFacilityState 调用）
-- ============================================================

---@param event_name string|nil
---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param duration Fixed|integer
function FacilityRegistry:send_interaction_event(event_name, agent, facility, duration)
    if not event_name then
        return
    end

    local payload = {
        baby = agent.unit,
        facility = facility.unit,
        area = facility.area,
        facility_id = facility.def.facility_id,
        need_id = facility.def.id,
        duration_seconds = duration,
    }

    -- 直接发给设施单位本体（专为秋千等组件：坐上触发摆动、离开结束摆动回正）
    if facility.unit then
        LuaAPI.unit_send_custom_event(facility.unit, event_name, payload)
    end
    -- 同时广播全局，方便其它系统监听
    LuaAPI.global_send_custom_event(event_name, payload)
end

-- ============================================================
-- 销毁：交互收尾在 BabyAgent:destroy（状态 exit）里做，本表只清记录。
-- ============================================================

---@return nil
function FacilityRegistry:destroy()
    self.facilities = {}
end

return FacilityRegistry
