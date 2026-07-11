local Class = require("BaseClass")
local Timer = require("BabyStorm.Core.Timer")
local UnitUtil = require("Util.UnitUtil")
local RoleUtil = require("Util.RoleUtil")
local Log = require("Util.Log")

-- ============================================================
-- CribCoordinator —— 婴儿床 UI 事件路由 + 玩家手持道具 + 床级歪倒/扶正
-- ============================================================
-- 引擎侧把柜子图片点击和进度按钮按下/松开映射为 UI_CUSTOM_EVENT；本协调器校验后
-- 转发为 agent:handle_event（换洗流程本身归 CribInteraction 子状态），自己只管：
--   * 玩家去柜子取尿布/纸巾——创建真实组件交给玩家举起，记录逻辑持有物（role_held）；
--   * 床级歪倒（超时无人换洗）与扶正长按（玩家把歪的床按正）——床是设施单位，不是
--     宝宝的动画/移动，操作归这里而非 CribInteraction；
--   * 距离判定与结算自定义事件——供 CribInteraction/CribCareView 查询。
---@class CribHeldItem
---@field key string
---@field item_unit Obstacle|Unit
---@field unit Unit|LifeEntity

---@class CribCoordinator
---@field cfg BabyCribConfig
---@field triggers TriggerRegistry
---@field facility FacilityRegistry|nil
---@field cabinet_pos Vector3|nil
---@field role_held table<any, CribHeldItem>
---@field started boolean
local CribCoordinator = Class("CribCoordinator")

local UI_EVENT = {
    GET_DIAPER = "BABY_CRIB_UI_GET_DIAPER",
    GET_TISSUE = "BABY_CRIB_UI_GET_TISSUE",
    CHANGE_DIAPER_DOWN = "BABY_CRIB_UI_CHANGE_DIAPER_DOWN",
    CHANGE_DIAPER_UP = "BABY_CRIB_UI_CHANGE_DIAPER_UP",
    CLEAN_BABY_DOWN = "BABY_CRIB_UI_CLEAN_BABY_DOWN",
    CLEAN_BABY_UP = "BABY_CRIB_UI_CLEAN_BABY_UP",
    STRAIGHTEN_BED_DOWN = "BABY_CRIB_UI_STRAIGHTEN_BED_DOWN",
    STRAIGHTEN_BED_UP = "BABY_CRIB_UI_STRAIGHTEN_BED_UP",
    PROGRESS_DOWN = "BABY_CRIB_UI_PROGRESS_DOWN",
    PROGRESS_UP = "BABY_CRIB_UI_PROGRESS_UP",
    DIAPER_PICKED = "BABY_CRIB_DIAPER_PICKED",
    TISSUE_PICKED = "BABY_CRIB_TISSUE_PICKED",
}

---@param config BabyStormConfig
---@param triggers TriggerRegistry
function CribCoordinator:Ctor(config, triggers)
    self.cfg = config.crib
    self.triggers = triggers
    self.facility = nil
    self.cabinet_pos = nil
    self.role_held = {}
    self.started = false
end

---@param facility FacilityRegistry
function CribCoordinator:set_facility_service(facility)
    self.facility = facility
end

-- ============================================================
-- 生命周期
-- ============================================================

---@return boolean
function CribCoordinator:start()
    if self.started then
        return true
    end
    if not (self.cfg and self.cfg.enabled) then
        return false
    end
    self.started = true

    local cp = self.cfg.cabinet_pos
    if cp then
        self.cabinet_pos = math.Vector3(cp[1], cp[2], cp[3])
    end

    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    for index = 1, #beds do
        beds[index].crib_tilted = false
        beds[index].crib_reset_progress = 0.0
        beds[index].crib_reset_pressing = nil
    end

    self:_setup_ui_events()
    Timer.every(self, 0.1, function() self:_reset_tick() end)
    return true
end

function CribCoordinator:_setup_ui_events()
    local function bind(event_name, callback)
        self.triggers:global({ EVENT.UI_CUSTOM_EVENT, event_name }, function(_, _, data)
            callback(data and data.role or nil)
        end)
    end

    bind(UI_EVENT.GET_DIAPER, function(role)
        self:_on_pick_item(role, self:_sub_by_key("diaper"))
    end)
    bind(UI_EVENT.GET_TISSUE, function(role)
        self:_on_pick_item(role, self:_sub_by_key("tissue"))
    end)
    bind(UI_EVENT.CHANGE_DIAPER_DOWN, function(role) self:_on_action_down(role, "diaper") end)
    bind(UI_EVENT.CHANGE_DIAPER_UP, function(role) self:_on_action_up(role, "diaper") end)
    bind(UI_EVENT.CLEAN_BABY_DOWN, function(role) self:_on_action_down(role, "tissue") end)
    bind(UI_EVENT.CLEAN_BABY_UP, function(role) self:_on_action_up(role, "tissue") end)
    bind(UI_EVENT.STRAIGHTEN_BED_DOWN, function(role) self:_on_action_down(role, "reset") end)
    bind(UI_EVENT.STRAIGHTEN_BED_UP, function(role) self:_on_action_up(role, "reset") end)
    bind(UI_EVENT.PROGRESS_DOWN, function(role) self:_on_current_action(role, true) end)
    bind(UI_EVENT.PROGRESS_UP, function(role) self:_on_current_action(role, false) end)
    Log.info("crib scene UI events ready")
end

---@param role Role|nil
---@param pressing boolean
function CribCoordinator:_on_current_action(role, pressing)
    local role_id = RoleUtil.get_role_id(role)
    local facility, action = self:action_target_for_role(role, role_id)
    Log.info("crib DEBUG current_action", "role", tostring(role_id), "pressing", pressing,
        "facility", tostring(facility and facility.def and facility.def.id), "action", tostring(action))
    if not action then
        return
    end
    if pressing then
        self:_on_action_down(role, action)
    else
        self:_on_action_up(role, action)
    end
end

---@param key string
---@return BabyCribSubType|nil
function CribCoordinator:_sub_by_key(key)
    local subs = self.cfg.sub_types
    for index = 1, #subs do
        if subs[index].key == key then
            return subs[index]
        end
    end
    return nil
end

-- ============================================================
-- 取尿布 / 纸巾：创建真实组件并交给玩家举起，同时记录逻辑持有物。
-- ============================================================

---@param role Role|nil
---@param sub BabyCribSubType
function CribCoordinator:_on_pick_item(role, sub)
    local role_id = RoleUtil.get_role_id(role)
    Log.info("crib CLICK pick", sub and sub.key, "role", tostring(role_id))
    if not (role and role_id and sub) then
        return
    end
    if not self:_role_near_pos(role, self.cabinet_pos, self.cfg.cabinet_show_radius) then
        Log.info("crib pick rejected: not near cabinet", tostring(role_id))
        return
    end
    self:consume_held(role_id)

    local player = role.get_ctrl_unit and role.get_ctrl_unit() or nil
    local player_pos = player and player.get_position and player.get_position() or nil
    if not (player and player_pos and player.lift_unit and GameAPI.create_obstacle) then
        Log.warn("crib lift item unavailable", sub.key)
        return
    end

    if player.get_lifted_obstacle then
        local ok, lifted = pcall(function() return player.get_lifted_obstacle() end)
        if ok and lifted then
            if role.show_tips then
                role.show_tips("请先放下手中的物品", 1.5)
            end
            return
        end
    end

    local scale_cfg = sub.hold_scale or { 0.3, 0.3, 0.3 }
    local ok, item_unit = pcall(function()
        return GameAPI.create_obstacle(
            sub.item_prefab,
            player_pos + math.Vector3(0.0, 0.5, 0.0),
            math.Quaternion(0.0, 0.0, 0.0),
            math.Vector3(scale_cfg[1], scale_cfg[2], scale_cfg[3]),
            role
        )
    end)
    if not (ok and item_unit) then
        Log.warn("crib create lifted item failed", sub.key, tostring(item_unit))
        return
    end

    -- 举起开关 + 交给玩家举起，创建后一个 pcall 块兜住（新建道具单位理论恒有效，仅防引擎边缘失败）。
    local lift_ok, lift_err = pcall(function()
        item_unit.set_lifted_enabled(true)
        player.lift_unit(item_unit)
    end)
    if not lift_ok then
        pcall(function() GameAPI.destroy_unit(item_unit) end)
        Log.warn("crib player lift item failed", sub.key, tostring(lift_err))
        return
    end

    self.role_held[role_id] = { key = sub.key, item_unit = item_unit, unit = player }
    self.triggers:unit(item_unit, { EVENT.SPEC_OBSTACLE_LIFTED_END }, function()
        self:_on_held_item_released(role_id, item_unit)
    end)
    -- 取到对应道具算“开始照顾”：通知所有仍有会话的床，由各自的 CribInteraction 判断
    -- 是不是在等这类道具、重置歪床倒计时，给玩家走回床边的时间。
    self:_reset_idle_for_sub(sub.key)
    if role.show_tips then
        role.show_tips("拿到" .. sub.action_text .. "了", 1.5)
    end
    local picked_event = sub.key == "diaper" and UI_EVENT.DIAPER_PICKED or UI_EVENT.TISSUE_PICKED
    if LuaAPI.global_send_custom_event then
        LuaAPI.global_send_custom_event(picked_event, {
            role = role,
            role_id = role_id,
            item_prefab = sub.item_prefab,
            action = sub.key,
        })
    end
    Log.info("crib pick item lifted", sub.key, "role", role_id, tostring(item_unit))
end

---@param role_id any
---@param item_unit Obstacle|Unit
function CribCoordinator:_on_held_item_released(role_id, item_unit)
    local held = role_id and self.role_held[role_id] or nil
    if not (held and UnitUtil.same_unit(held.item_unit, item_unit)) then
        return
    end
    self.role_held[role_id] = nil
    Log.info("crib held item released", tostring(role_id), held.key)
end

---取到某类道具后，通知每张有会话的床——是否重置歪床倒计时由 CribInteraction 自己判断。
---@param sub_key string
function CribCoordinator:_reset_idle_for_sub(sub_key)
    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    for i = 1, #beds do
        local session = beds[i].crib_session
        if session then
            session.agent:handle_event({ type = "crib_item_taken", sub_key = sub_key })
        end
    end
end

---@param role_id any
function CribCoordinator:held_key(role_id)
    local held = role_id and self.role_held[role_id] or nil
    return held and held.key or nil
end

---@param role_id any
function CribCoordinator:consume_held(role_id)
    local held = role_id and self.role_held[role_id] or nil
    if not held then
        return
    end
    self.role_held[role_id] = nil
    if held.item_unit and GameAPI.destroy_unit then
        pcall(function() GameAPI.destroy_unit(held.item_unit) end)
    end
end

-- ============================================================
-- 长按：换洗（care，转发给会话宝宝）/ 扶正（reset，床级，本协调器自己处理）
-- ============================================================

---@param role Role|nil
---@param action "diaper"|"tissue"|"reset"
function CribCoordinator:_on_action_down(role, action)
    local role_id = RoleUtil.get_role_id(role)
    if not (role and role_id) then
        return
    end

    local facility, available_action = self:action_target_for_role(role, role_id)
    if not (facility and available_action == action) then
        return
    end

    if action == "reset" then
        facility.crib_reset_pressing = role_id
    else
        facility.crib_session.agent:handle_event({ type = "crib_press_begin", role = role, role_id = role_id })
    end
    Log.info("crib HUD action down", action, "role", tostring(role_id))
end

---@param role Role|nil
---@param action "diaper"|"tissue"|"reset"
function CribCoordinator:_on_action_up(role, action)
    local role_id = RoleUtil.get_role_id(role)
    if not role_id then
        return
    end

    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    for index = 1, #beds do
        local facility = beds[index]
        local session = facility.crib_session
        if action ~= "reset" and session and session.sub.key == action and session.pressing_role == role_id then
            session.agent:handle_event({ type = "crib_press_end", role_id = role_id })
        elseif action == "reset" and facility.crib_reset_pressing == role_id then
            facility.crib_reset_pressing = nil
            facility.crib_reset_progress = 0.0
        end
    end
end

-- ============================================================
-- 床级歪倒 / 扶正
-- ============================================================

---超时无人换洗：记录扶正前的朝向、叠加歪转、置歪床标志（不结算宝宝这边的交互，
---那是 CribInteraction._on_idle_tilt 的事）。
---@param facility BabyFacilityRecord
function CribCoordinator:tilt_bed(facility)
    Log.info("crib bed tilt", facility.def.id)
    local bed = facility.unit
    if bed then
        -- 读朝向 + 叠加歪转 + 写回合并进一个 pcall 块：床单位可能已被回收销毁。
        pcall(function()
            local rot = bed.get_orientation()
            if not rot then
                return
            end
            facility.crib_upright_rot = rot
            local tilt = self:_tilt_quaternion()
            if tilt then
                bed.set_orientation(tilt * rot)
            end
        end)
    end
    facility.crib_tilted = true
    facility.crib_reset_progress = 0.0
    facility.crib_reset_pressing = nil
end

---@return Quaternion|nil
function CribCoordinator:_tilt_quaternion()
    local deg = self.cfg.tilt_degrees or 22.0
    local rad = math.deg_to_rad and math.deg_to_rad(deg) or (deg * 0.0174533)
    local axis = self.cfg.tilt_axis or "z"
    if axis == "x" then
        return math.Quaternion(rad, 0.0, 0.0)
    end
    return math.Quaternion(0.0, 0.0, rad)
end

function CribCoordinator:_reset_tick()
    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    for index = 1, #beds do
        local facility = beds[index]
        if facility.crib_tilted and facility.crib_reset_pressing then
            if not self:is_role_near_bed(facility.crib_reset_pressing, facility) then
                facility.crib_reset_pressing = nil
                facility.crib_reset_progress = 0.0
            else
                local max = self.cfg.reset_progress_max or 100
                local duration = self.cfg.reset_duration_seconds or 3.0
                facility.crib_reset_progress = (facility.crib_reset_progress or 0) + max / duration * 0.1
                if facility.crib_reset_progress >= max then
                    self:_finish_reset(facility)
                end
            end
        end
    end
end

---@param facility BabyFacilityRecord
function CribCoordinator:_finish_reset(facility)
    local role_id = facility.crib_reset_pressing
    local bed = facility.unit
    if bed and facility.crib_upright_rot and bed.set_orientation then
        pcall(function() bed.set_orientation(facility.crib_upright_rot) end)
    end
    facility.crib_tilted = false
    facility.crib_reset_progress = 0.0
    facility.crib_reset_pressing = nil
    facility.crib_upright_rot = nil
    self:emit_action_event(self.cfg.reset_complete_event, role_id, facility, nil)
    Log.info("crib reset done", facility.def.id)
end

-- ============================================================
-- 公开查询（CribInteraction / CribCareView 用）
-- ============================================================

---某玩家当前贴近哪张床、可执行哪个动作（换洗 need_key 或 "reset"）。
---@param role Role
---@param role_id any
---@return BabyFacilityRecord|nil, "diaper"|"tissue"|"reset"|nil
function CribCoordinator:action_target_for_role(role, role_id)
    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    local radius = self.cfg.progress_show_radius or 4.0
    local held = role_id and self.role_held[role_id] or nil
    local best, best_action, best_distance = nil, nil, nil

    for index = 1, #beds do
        local facility = beds[index]
        local distance = self:_role_dist_sq(role, facility.unit)
        if distance and distance <= radius * radius then
            local action = nil
            local session = facility.crib_session
            if session and held and session.sub and held.key == session.sub.key then
                action = session.sub.key
            elseif not session and facility.crib_tilted then
                action = "reset"
            end
            if action and (not best_distance or distance < best_distance) then
                best = facility
                best_action = action
                best_distance = distance
            end
        end
    end
    return best, best_action
end

---@param role_id any
---@param facility BabyFacilityRecord
---@return boolean
function CribCoordinator:is_role_near_bed(role_id, facility)
    local roles = GameAPI.get_all_valid_roles() or {}
    for _, role in ipairs(roles) do
        if RoleUtil.get_role_id(role) == role_id then
            return self:_role_near_unit(role, facility.unit, self.cfg.progress_show_radius)
        end
    end
    return false
end

---@param event_name string|nil
---@param role_id any
---@param facility BabyFacilityRecord
---@param session CribCareSession|nil
function CribCoordinator:emit_action_event(event_name, role_id, facility, session)
    if not event_name then
        return
    end

    local role = session and session.last_role or nil
    if not role and role_id then
        local roles = GameAPI.get_all_valid_roles() or {}
        for index = 1, #roles do
            if RoleUtil.get_role_id(roles[index]) == role_id then
                role = roles[index]
                break
            end
        end
    end

    local payload = {
        role = role,
        role_id = role_id,
        baby = session and session.agent and session.agent.unit or nil,
        facility = facility.unit,
        need_id = facility.def and facility.def.id or "crib_care",
        action = session and session.sub and session.sub.key or "reset",
    }

    -- 床单位在会话仍存续期间恒有效（同 FacilityRegistry:send_interaction_event 的直调写法）。
    if facility.unit then
        LuaAPI.unit_send_custom_event(facility.unit, event_name, payload)
    end
    LuaAPI.global_send_custom_event(event_name, payload)
    Log.info("crib custom event", event_name, "role", tostring(role_id))
end

-- ============================================================
-- 距离工具
-- ============================================================

---@param role Role
---@param unit Unit|nil
---@return number|nil
function CribCoordinator:_role_dist_sq(role, unit)
    if not (role and unit and unit.get_position) then
        return nil
    end
    local player = role.get_ctrl_unit and role.get_ctrl_unit() or nil
    local ppos = player and player.get_position and player.get_position() or nil
    local upos = unit.get_position()
    if not (ppos and upos) then
        return nil
    end
    return UnitUtil.distance_xz_sq(ppos, upos)
end

---@param role Role
---@param unit Unit|nil
---@param radius number
---@return boolean
function CribCoordinator:_role_near_unit(role, unit, radius)
    local d = self:_role_dist_sq(role, unit)
    local r = radius or 4.0
    return d ~= nil and d <= r * r
end

---@param role Role
---@param pos Vector3|nil
---@param radius number
---@return boolean
function CribCoordinator:_role_near_pos(role, pos, radius)
    if not (role and pos) then
        return false
    end
    local player = role.get_ctrl_unit and role.get_ctrl_unit() or nil
    local ppos = player and player.get_position and player.get_position() or nil
    if not ppos then
        return false
    end
    local r = radius or 4.0
    return UnitUtil.distance_xz_sq(ppos, pos) <= r * r
end

-- ============================================================
-- 销毁
-- ============================================================

function CribCoordinator:destroy()
    for role_id, _ in pairs(self.role_held) do
        self:consume_held(role_id)
    end
    self.role_held = {}
    Timer.cancel_all(self)
    self.started = false
end

return CribCoordinator
