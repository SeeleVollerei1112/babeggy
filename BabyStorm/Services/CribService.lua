local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local RoleUtil = require("Util.RoleUtil")
local UINodes = require("Data.UINodes")
local Log = require("Util.Log")

-- ============================================================
-- CribService —— 婴儿床“换尿布 / 擦屁股”玩法
-- ============================================================
-- HUD 节点（均来自 Data.UINodes）：
--   hud_canvas
--   ├── get_diaper_btn / get_tissue_btn：靠近柜子时显示，点击取手持道具
--   ├── change_diaper_btn：换尿布，持续按住 8 秒
--   ├── claen_baby_btn：擦屁股，持续按住 5 秒
--   ├── straighten_bed_btn_1：扶正床，持续按住 3 秒
--   └── progress_bar：三种动作共用
-- 引擎侧把按钮点击/按下/松开映射为 UI_CUSTOM_EVENT；Lua 负责校验、显隐、进度与结算。
---@class CribCareSession
---@field agent BabyAgent
---@field sub BabyCribSubType
---@field progress number
---@field interacted boolean
---@field idle_remaining number
---@field pressing_role RoleID|integer|nil
---@field last_role Role|nil
---
---@class CribService
---@field config BabyStormConfig
---@field crib_config BabyCribConfig
---@field triggers TriggerRegistry
---@field facility FacilityService|nil
---@field cabinet_pos Vector3|nil
---@field started boolean
local CribService = Class("CribService")

local UI_EVENT = {
    GET_DIAPER = "BABY_CRIB_UI_GET_DIAPER",
    GET_TISSUE = "BABY_CRIB_UI_GET_TISSUE",
    CHANGE_DIAPER_DOWN = "BABY_CRIB_UI_CHANGE_DIAPER_DOWN",
    CHANGE_DIAPER_UP = "BABY_CRIB_UI_CHANGE_DIAPER_UP",
    CLEAN_BABY_DOWN = "BABY_CRIB_UI_CLEAN_BABY_DOWN",
    CLEAN_BABY_UP = "BABY_CRIB_UI_CLEAN_BABY_UP",
    STRAIGHTEN_BED_DOWN = "BABY_CRIB_UI_STRAIGHTEN_BED_DOWN",
    STRAIGHTEN_BED_UP = "BABY_CRIB_UI_STRAIGHTEN_BED_UP",
    DIAPER_PICKED = "BABY_CRIB_DIAPER_PICKED",
    TISSUE_PICKED = "BABY_CRIB_TISSUE_PICKED",
}
-- set_progressbar_current/max 要 Lua int：这里的 math 是定点数库，math.floor 返回 Fix32，
-- 必须再 math.tointeger 转成真正的整数，否则引擎报 “节点类型不正确 / expected int” 且进度条不刷新。
---@param x number
---@return integer
local function to_int(x)
    return math.tointeger(math.floor(x or 0)) or 0
end

---@param config BabyStormConfig
---@param triggers TriggerRegistry
function CribService:Ctor(config, triggers)
    self.config = config
    self.crib_config = config.crib
    self.triggers = triggers
    self.facility = nil
    self.cabinet_pos = nil
    self.role_held = {} ---@type table<any, CribHeldItem>
    self.started = false
    self._poll_accum = 0.0
end

---@param facility FacilityService
function CribService:set_facility_service(facility)
    self.facility = facility
end

-- ============================================================
-- 生命周期
-- ============================================================

---@return boolean
function CribService:start()
    if self.started then
        return true
    end
    if not (self.crib_config and self.crib_config.enabled) then
        return false
    end
    self.started = true

    local cp = self.crib_config.cabinet_pos
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
    self:_refresh_ui()
    return true
end

function CribService:_setup_ui_events()
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
    Log.info("crib HUD UI events ready")
end

---@param key string
---@return BabyCribSubType|nil
function CribService:_sub_by_key(key)
    local subs = self.crib_config.sub_types
    for index = 1, #subs do
        if subs[index].key == key then
            return subs[index]
        end
    end
    return nil
end
-- ============================================================
-- 会话：躺床后开始 / 结束（由 FacilityService 调用）
-- ============================================================

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function CribService:begin_session(agent, facility)
    local sub = self:_roll_sub_type()
    ---@type CribCareSession
    local session = {
        agent = agent,
        sub = sub,
        progress = 0.0,
        interacted = false,
        idle_remaining = self.crib_config.idle_tilt_seconds or 15.0,
        pressing_role = nil,
        last_role = nil,
    }
    facility.crib_session = session
    agent:set_status(sub.need_text)
    Log.info("crib session begin", facility.def.id, "baby", agent.index, "sub", sub.key)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function CribService:end_session(agent, facility)
    facility.crib_session = nil
    self:_refresh_ui()
end

---@return BabyCribSubType
function CribService:_roll_sub_type()
    local subs = self.crib_config.sub_types
    local idx = 1
    if GameAPI and GameAPI.random_int then
        idx = GameAPI.random_int(1, #subs)
    end
    return subs[idx] or subs[1]
end

-- ============================================================
-- 取尿布 / 纸巾：给点击者一件手持道具（模型挂到玩家手上 + 逻辑标记）
-- ============================================================

---@param role Role|nil
---@param sub BabyCribSubType
function CribService:_on_pick_item(role, sub)
    local role_id = RoleUtil.get_role_id(role)
    Log.info("crib CLICK pick", sub and sub.key, "role", tostring(role_id))
    if not (role and role_id and sub) then
        return
    end
    if not self:_role_near_pos(role, self.cabinet_pos, self.crib_config.cabinet_show_radius) then
        Log.info("crib pick rejected: not near cabinet", tostring(role_id))
        return
    end
    self:_clear_held(role_id)

    -- bind_model 把 尿布/纸巾 unit 预设(UnitKey) 作为模型挂到玩家右手；scale 0.3（模型偏大）。
    local player = role.get_ctrl_unit and role.get_ctrl_unit() or nil
    local bind_id = nil
    if player and player.bind_model then
        local socket = (Enums and Enums.ModelSocket and Enums.ModelSocket[sub.hold_socket or "socket_hand_r"])
            or (Enums and Enums.ModelSocket and Enums.ModelSocket.socket_hand_r)
            or (Enums and Enums.ModelSocket and Enums.ModelSocket.socket_origin)
        local off = sub.hold_offset and math.Vector3(sub.hold_offset[1], sub.hold_offset[2], sub.hold_offset[3])
            or math.Vector3(0, 0, 0)
        local scale = sub.hold_scale and math.Vector3(sub.hold_scale[1], sub.hold_scale[2], sub.hold_scale[3])
            or math.Vector3(0.3, 0.3, 0.3)
        local ok, id = pcall(function()
            return player.bind_model(sub.item_prefab, socket, off, math.Quaternion(0, 0, 0), scale)
        end)
        if ok then
            bind_id = id
        else
            Log.warn("crib hold bind_model failed", sub.key, tostring(id))
        end
    end

    self.role_held[role_id] = { key = sub.key, bind_id = bind_id, unit = player }
    -- 取到对应道具算“开始照顾”：重置正在等这类道具的宝宝的歪床倒计时，给玩家走回床边的时间。
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
    Log.info("crib pick item ok", sub.key, "role", role_id, "bind", tostring(bind_id))
    self:_refresh_ui()
end

---取到某类道具后，重置正在等这类道具换洗的宝宝的歪床倒计时。
---@param sub_key string
function CribService:_reset_idle_for_sub(sub_key)
    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    for i = 1, #beds do
        local session = beds[i].crib_session
        if session and session.sub and session.sub.key == sub_key and not session.interacted then
            session.idle_remaining = self.crib_config.idle_tilt_seconds or 25.0
        end
    end
end

---@param role_id any
function CribService:_clear_held(role_id)
    local held = role_id and self.role_held[role_id] or nil
    if not held then
        return
    end
    if held.unit and held.bind_id and held.unit.unbind_model then
        pcall(function() held.unit.unbind_model(held.bind_id) end)
    end
    self.role_held[role_id] = nil
end

-- ============================================================
-- 长按：换洗（care）/ 扶正（reset）
-- ============================================================

---@param role Role|nil
---@param action "diaper"|"tissue"|"reset"
function CribService:_on_action_down(role, action)
    local role_id = RoleUtil.get_role_id(role)
    if not (role and role_id) then
        return
    end

    local facility, available_action = self:_action_target_for_role(role, role_id)
    if not (facility and available_action == action) then
        return
    end

    if action == "reset" then
        facility.crib_reset_pressing = role_id
    else
        local session = facility.crib_session
        session.pressing_role = role_id
        session.interacted = true
        session.last_role = role
    end
    Log.info("crib HUD action down", action, "role", tostring(role_id))
end

---@param role Role|nil
---@param action "diaper"|"tissue"|"reset"
function CribService:_on_action_up(role, action)
    local role_id = RoleUtil.get_role_id(role)
    if not role_id then
        return
    end

    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    for index = 1, #beds do
        local facility = beds[index]
        local session = facility.crib_session
        if action ~= "reset" and session and session.sub.key == action and session.pressing_role == role_id then
            session.pressing_role = nil
            session.progress = 0.0
            session.interacted = false
            session.idle_remaining = self.crib_config.idle_tilt_seconds or 25.0
        elseif action == "reset" and facility.crib_reset_pressing == role_id then
            facility.crib_reset_pressing = nil
            facility.crib_reset_progress = 0.0
        end
    end
    self:_refresh_ui()
end
-- ============================================================
-- 每帧推进（由 Manager tick 驱动）
-- ============================================================

---@param dt number
function CribService:update(dt)
    if not self.started then
        return
    end
    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    for index = 1, #beds do
        self:_update_bed(beds[index], dt)
    end
    self._poll_accum = self._poll_accum + dt
    if self._poll_accum >= (self.crib_config.poll_interval or 0.2) then
        self._poll_accum = 0.0
        self:_refresh_ui()
    end
end

---@param facility BabyFacilityRecord
---@param dt number
function CribService:_update_bed(facility, dt)
    local session = facility.crib_session
    if session then
        if session.pressing_role and not self:_pressing_role_near(session.pressing_role, facility) then
            session.pressing_role = nil
            session.progress = 0.0
            session.interacted = false
        end
        if session.pressing_role then
            local max = self.crib_config.progress_max or 100
            local duration = session.sub.duration_seconds or 5.0
            session.progress = session.progress + max / duration * dt
            if session.progress >= max then
                self:_complete_care(facility)
                return
            end
        elseif not session.interacted then
            session.idle_remaining = session.idle_remaining - dt
            if session.idle_remaining <= 0 then
                self:_tilt_bed(facility)
                return
            end
        end
    elseif facility.crib_tilted and facility.crib_reset_pressing then
        if not self:_pressing_role_near(facility.crib_reset_pressing, facility) then
            facility.crib_reset_pressing = nil
            facility.crib_reset_progress = 0.0
            return
        end
        local max = self.crib_config.reset_progress_max or 100
        local duration = self.crib_config.reset_duration_seconds or 3.0
        facility.crib_reset_progress = (facility.crib_reset_progress or 0) + max / duration * dt
        if facility.crib_reset_progress >= max then
            self:_finish_reset(facility)
        end
    end
end
---@param facility BabyFacilityRecord
function CribService:_complete_care(facility)
    local session = facility.crib_session
    if not session then
        return
    end
    self:_clear_held(session.pressing_role)
    local agent = session.agent
    if session.last_role then
        agent.last_role = session.last_role
    end
    facility.crib_session = nil
    Log.info("crib care complete", facility.def.id, "baby", agent.index, "sub", session.sub.key)
    if agent and not agent.destroyed then
        agent:complete_facility_interaction(facility)
    end
    self:_emit_action_event(session.sub.complete_event, session.pressing_role, facility, session)
    self:_refresh_ui()
end

---@param facility BabyFacilityRecord
function CribService:_tilt_bed(facility)
    local session = facility.crib_session
    local agent = session and session.agent or facility.active_agent
    Log.info("crib idle tilt", facility.def.id)

    local bed = facility.unit
    if bed and bed.get_orientation then
        local ok, rot = pcall(function() return bed.get_orientation() end)
        if ok and rot then
            facility.crib_upright_rot = rot
            local tilt = self:_tilt_quaternion()
            if tilt and bed.set_orientation then
                local mok, tilted = pcall(function() return tilt * rot end)
                if mok and tilted then
                    pcall(function() bed.set_orientation(tilted) end)
                end
            end
        end
    end

    facility.crib_tilted = true
    facility.crib_reset_progress = 0.0
    facility.crib_reset_pressing = nil

    if agent and not agent.destroyed and agent.fail_facility_interaction then
        agent:fail_facility_interaction(facility)
    end
    self:_refresh_ui()
end

---@return Quaternion|nil
function CribService:_tilt_quaternion()
    local deg = self.crib_config.tilt_degrees or 22.0
    local rad = math.deg_to_rad and math.deg_to_rad(deg) or (deg * 0.0174533)
    local axis = self.crib_config.tilt_axis or "z"
    if axis == "x" then
        return math.Quaternion(rad, 0.0, 0.0)
    end
    return math.Quaternion(0.0, 0.0, rad)
end

---@param facility BabyFacilityRecord
function CribService:_finish_reset(facility)
    local role_id = facility.crib_reset_pressing
    local bed = facility.unit
    if bed and facility.crib_upright_rot and bed.set_orientation then
        pcall(function() bed.set_orientation(facility.crib_upright_rot) end)
    end
    facility.crib_tilted = false
    facility.crib_reset_progress = 0.0
    facility.crib_reset_pressing = nil
    facility.crib_upright_rot = nil
    self:_emit_action_event(self.crib_config.reset_complete_event, role_id, facility, nil)
    Log.info("crib reset done", facility.def.id)
    self:_refresh_ui()
end

---@param event_name string|nil
---@param role_id any
---@param facility BabyFacilityRecord
---@param session CribCareSession|nil
function CribService:_emit_action_event(event_name, role_id, facility, session)
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

    if facility.unit and LuaAPI.unit_send_custom_event then
        pcall(function() LuaAPI.unit_send_custom_event(facility.unit, event_name, payload) end)
    end
    if LuaAPI.global_send_custom_event then
        LuaAPI.global_send_custom_event(event_name, payload)
    end
    Log.info("crib custom event", event_name, "role", tostring(role_id))
end

-- ============================================================
-- HUD 显隐 + 公用进度条刷新
-- ============================================================

function CribService:_refresh_ui()
    local roles = GameAPI.get_all_valid_roles() or {}
    for _, role in ipairs(roles) do
        local role_id = RoleUtil.get_role_id(role)
        local cabinet_visible = self:_role_near_pos(
            role,
            self.cabinet_pos,
            self.crib_config.cabinet_show_radius
        )
        self:_set_hud_visible(role, UINodes.get_diaper_btn, cabinet_visible)
        self:_set_hud_visible(role, UINodes.get_tissue_btn, cabinet_visible)

        local facility, action = self:_action_target_for_role(role, role_id)
        self:_set_hud_visible(role, UINodes.change_diaper_btn, action == "diaper")
        self:_set_hud_visible(role, UINodes.claen_baby_btn, action == "tissue")
        self:_set_hud_visible(role, UINodes.straighten_bed_btn_1, action == "reset")
        self:_set_hud_visible(role, UINodes.progress_bar, action ~= nil)

        if facility and action then
            local current = 0
            local max = self.crib_config.progress_max or 100
            if action == "reset" then
                current = facility.crib_reset_progress or 0
                max = self.crib_config.reset_progress_max or 100
            else
                current = facility.crib_session and facility.crib_session.progress or 0
            end
            pcall(function()
                role.set_progressbar_min(UINodes.progress_bar, 0)
                role.set_progressbar_max(UINodes.progress_bar, to_int(max))
                role.set_progressbar_current(UINodes.progress_bar, to_int(current))
            end)
        end
    end
end

---@param role Role
---@param role_id any
---@return BabyFacilityRecord|nil, "diaper"|"tissue"|"reset"|nil
function CribService:_action_target_for_role(role, role_id)
    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    local radius = self.crib_config.progress_show_radius or 4.0
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

---@param role Role
---@param node ENode|nil
---@param visible boolean
function CribService:_set_hud_visible(role, node, visible)
    if role and node and role.set_node_visible then
        pcall(function() role.set_node_visible(node, visible and true or false) end)
    end
end
-- ============================================================
-- 距离工具
-- ============================================================

---@param role_id any
---@param facility BabyFacilityRecord
---@return boolean
function CribService:_pressing_role_near(role_id, facility)
    local roles = GameAPI.get_all_valid_roles() or {}
    for _, role in ipairs(roles) do
        if RoleUtil.get_role_id(role) == role_id then
            return self:_role_near_unit(role, facility.unit, self.crib_config.progress_show_radius)
        end
    end
    return false
end

---@param role Role
---@param unit Unit|nil
---@return number|nil
function CribService:_role_dist_sq(role, unit)
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
function CribService:_role_near_unit(role, unit, radius)
    local d = self:_role_dist_sq(role, unit)
    local r = radius or 4.0
    return d ~= nil and d <= r * r
end

---@param role Role
---@param pos Vector3|nil
---@param radius number
---@return boolean
function CribService:_role_near_pos(role, pos, radius)
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

function CribService:destroy()
    for role_id, _ in pairs(self.role_held) do
        self:_clear_held(role_id)
    end
    self.role_held = {}

    local roles = GameAPI.get_all_valid_roles() or {}
    for _, role in ipairs(roles) do
        self:_set_hud_visible(role, UINodes.get_diaper_btn, false)
        self:_set_hud_visible(role, UINodes.get_tissue_btn, false)
        self:_set_hud_visible(role, UINodes.change_diaper_btn, false)
        self:_set_hud_visible(role, UINodes.claen_baby_btn, false)
        self:_set_hud_visible(role, UINodes.straighten_bed_btn_1, false)
        self:_set_hud_visible(role, UINodes.progress_bar, false)
    end
    self.started = false
end
return CribService
