local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

---@class BabyFacilityRecord
---@field def BabyNeedDef
---@field unit Unit|nil
---@field area Unit|nil
---@field active_agent BabyAgent|nil
---@field bind_id any
---@field seat_token integer|nil

---@class FacilityService
---@field config BabyStormConfig
---@field resolver NeedResolver|nil
---@field facilities BabyFacilityRecord[]
---@field seat_token integer|nil
local FacilityService = Class("FacilityService")

---@param config BabyStormConfig
function FacilityService:Ctor(config)
    self.config = config
    self.resolver = nil
    self.facilities = {}
    self.seat_token = 0
end

---@param resolver NeedResolver
function FacilityService:set_need_resolver(resolver)
    self.resolver = resolver
end

---@return nil
function FacilityService:init()
    local needs = self.config.needs
    for index = 1, #needs do
        local need = needs[index]
        if self.resolver and self.resolver:is_facility_need(need) then
            self:_register_facility(need)
        end
    end
end

---@param need BabyNeedDef
---@return BabyFacilityRecord
function FacilityService:_register_facility(need)
    local unit = need.facility_name and LuaAPI.query_unit(need.facility_name) or nil
    local area = need.area_name and LuaAPI.query_unit(need.area_name) or nil

    if not unit then
        Log.warn("missing facility unit", need.id, need.facility_name)
    end
    if not area then
        Log.warn("missing facility area", need.id, need.area_name)
    end

    self:_configure_facility_unit(unit, need)

    local facility = {
        def = need,
        unit = unit,
        area = area,
        active_agent = nil,
    }
    self.facilities[#self.facilities + 1] = facility
    return facility
end

---@param unit Unit|nil
---@param need BabyNeedDef
function FacilityService:_configure_facility_unit(unit, need)
    if not unit then
        return
    end

    if unit.enable_interact then
        unit.enable_interact()
    end
    if unit.set_interact_button_text_by_index then
        unit.set_interact_button_text_by_index(1, need.action_text)
    end
    if unit.get_interact_id and unit.set_interact_button_text then
        self:_set_interact_button_text(unit, Enums.InteractBtnType.UNIT_START, need.action_text)
        self:_set_interact_button_text(unit, Enums.InteractBtnType.UNIT_STOP, "结束" .. need.action_text)
    end
end

---@param unit Unit
---@param btn_type integer
---@param text string
function FacilityService:_set_interact_button_text(unit, btn_type, text)
    local ok, interact_id = pcall(function()
        return unit.get_interact_id(1, btn_type)
    end)
    if ok and interact_id then
        pcall(function()
            unit.set_interact_button_text(interact_id, text)
        end)
    end
end

---@param unit Unit|LifeEntity|nil
---@param area Unit|nil
---@return boolean
function FacilityService:_unit_in_area(unit, area)
    if not (unit and area) then
        return false
    end

    if unit.is_in_customtriggerspace then
        local ok, result = pcall(function()
            return unit.is_in_customtriggerspace(area, true)
        end)
        if ok and result then
            return true
        end
    end

    local pos = unit.get_position and unit.get_position()
    if pos and GameAPI.is_point_in_customtriggerspace then
        local ok, result = pcall(function()
            return GameAPI.is_point_in_customtriggerspace(pos, area)
        end)
        return ok and result or false
    end
    return false
end

---@param pos Vector3|nil
---@param need BabyNeedDef
---@param baby_unit Unit|LifeEntity|nil
---@return BabyFacilityRecord|nil
function FacilityService:nearest_match(pos, need, baby_unit)
    local best = nil
    local best_dist = nil
    for index = 1, #self.facilities do
        local facility = self.facilities[index]
        if self.resolver and self.resolver:item_matches_need(facility, need) and not facility.active_agent then
            -- 优先：宝宝就在设施触发区域内，直接命中
            if facility.area and self:_unit_in_area(baby_unit, facility.area) then
                return facility
            end
            -- 兜底：按与设施本体的距离做最近匹配。
            -- 即使配置了 area 也保留此分支：触发区域判定偶发失灵 / 落点略微出界时仍可命中。
            if pos and facility.unit and facility.unit.get_position then
                local facility_pos = facility.unit.get_position()
                if facility_pos then
                    local dist = UnitUtil.distance_sq(pos, facility_pos)
                    if not best_dist or dist < best_dist then
                        best = facility
                        best_dist = dist
                    end
                end
            end
        end
    end

    local radius = self.config.baby.pickup_radius
    if best_dist and best_dist <= radius * radius then
        return best
    end
    return nil
end

---@param need BabyNeedDef
---@return integer
function FacilityService:_random_duration(need)
    local min_seconds = need.interact_min_seconds or 20
    local max_seconds = need.interact_max_seconds or 60
    if max_seconds < min_seconds then
        max_seconds = min_seconds
    end

    local span = max_seconds - min_seconds + 1
    local raw = LuaAPI.rand and LuaAPI.rand() or 0
    if raw < 0 then
        raw = -raw
    end
    -- 必须返回 Fixed（小数）：该值会作为 call_delay_time 的间隔使用，
    -- 传整数会被当成 0 立即触发，导致秋千互动“坐下即结束”。
    return (min_seconds + (raw % span)) + 0.0
end

---@param agent BabyAgent|nil
---@param facility BabyFacilityRecord|nil
---@return integer|nil
function FacilityService:begin_interaction(agent, facility)
    if not (agent and facility and facility.def) then
        return nil
    end
    if facility.active_agent and facility.active_agent ~= agent then
        return nil
    end

    local duration = self:_random_duration(facility.def)
    facility.active_agent = agent
    self:_seat_agent(agent, facility, duration)
    self:_send_custom_event(facility.def.interact_begin_event, agent, facility, duration)
    Log.info("facility begin", facility.def.id, "baby", agent.index, "duration", duration)
    return duration
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param duration integer|nil
function FacilityService:_seat_agent(agent, facility, duration)
    local def = facility.def
    if not (facility.unit and agent.unit) then
        return
    end

    local play_time = duration or 0.0

    -- 先强制播放坐姿动画（force_play 可覆盖 AI 的站立/待机动画）
    if def.seat_anim_id and agent.unit.force_play_animation_by_anim_key then
        local anim_ok = pcall(function()
            agent.unit.force_play_animation_by_anim_key(def.seat_anim_id, 0.0, play_time, 1.0, true)
        end)
        Log.info("facility anim force", def.id, agent.index, "anim", def.seat_anim_id, "ok", anim_ok)
    end

    -- 再把活体单位摆到座位点（绑定 API 在本环境不挪动活体单位，改用按帧定位跟随）
    self.seat_token = (self.seat_token or 0) + 1
    facility.seat_token = self.seat_token
    self:_sync_seat(agent, facility, facility.seat_token)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param token integer
function FacilityService:_sync_seat(agent, facility, token)
    if agent.destroyed or facility.active_agent ~= agent or facility.seat_token ~= token then
        return
    end

    local def = facility.def
    if facility.unit and agent.unit and agent.unit.set_position then
        local offset = self:_to_vector3(def.seat_offset)
        local pos = nil
        if offset and facility.unit.get_local_offset_position then
            pos = facility.unit.get_local_offset_position(offset)
        elseif facility.unit.get_position then
            pos = facility.unit.get_position()
        end
        if pos then
            pcall(function() agent.unit.set_position(pos) end)
        end
        local rot = self:_to_quaternion(def.seat_rotation)
        if rot and agent.unit.set_orientation then
            pcall(function() agent.unit.set_orientation(rot) end)
        end
    end

    LuaAPI.call_delay_time(0.0333, function()
        self:_sync_seat(agent, facility, token)
    end)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_unseat_agent(agent, facility)
    local def = facility.def
    if agent.unit and def.seat_anim_id and agent.unit.stop_anim then
        pcall(function()
            agent.unit.stop_anim()
        end)
    end
    if facility.unit and facility.bind_id and facility.unit.unbind_model then
        pcall(function()
            facility.unit.unbind_model(facility.bind_id)
        end)
    end
    facility.bind_id = nil
end

---@param values Fixed[]|nil
---@return Vector3|nil
function FacilityService:_to_vector3(values)
    if not values then
        return nil
    end
    return math.Vector3(values[1], values[2], values[3])
end

---@param values Fixed[]|nil
---@return Quaternion|nil
function FacilityService:_to_quaternion(values)
    if not values then
        return nil
    end
    return math.Quaternion(
        math.deg_to_rad(values[1]),
        math.deg_to_rad(values[2]),
        math.deg_to_rad(values[3])
    )
end

---@param agent BabyAgent|nil
---@param facility BabyFacilityRecord|nil
function FacilityService:end_interaction(agent, facility)
    if not (agent and facility and facility.def) then
        return
    end
    if facility.active_agent and facility.active_agent ~= agent then
        return
    end

    facility.active_agent = nil
    self:_unseat_agent(agent, facility)
    self:_send_custom_event(facility.def.interact_end_event, agent, facility, 0)
    Log.info("facility end", facility.def.id, "baby", agent.index)
end

---@param event_name string|nil
---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param duration integer
function FacilityService:_send_custom_event(event_name, agent, facility, duration)
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
    if facility.unit and LuaAPI.unit_send_custom_event then
        LuaAPI.unit_send_custom_event(facility.unit, event_name, payload)
    end
    -- 同时广播全局，方便其它系统监听
    if LuaAPI.global_send_custom_event then
        LuaAPI.global_send_custom_event(event_name, payload)
    end
end

---@return nil
function FacilityService:destroy()
    self.facilities = {}
end

return FacilityService
