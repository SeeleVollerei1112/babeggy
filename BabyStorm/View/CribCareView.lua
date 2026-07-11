local Class = require("BaseClass")
local Timer = require("BabyStorm.Core.Timer")
local UnitUtil = require("Util.UnitUtil")
local RoleUtil = require("Util.RoleUtil")
local UINodes = require("Data.UINodes")
local Prefab = require("Data.Prefab")
local Log = require("Util.Log")

-- ============================================================
-- CribCareView —— 婴儿床场景 UI 表现层
-- ============================================================
-- 只管两件事：柜子画布 + 每床独立的进度条画布的绑定，与按 poll_interval 的显隐/进度刷新。
-- 不持有任何玩法判定——该给谁看哪张床的进度条、当前动作是什么，全部问 CribCoordinator。
---@class CribCareView
---@field cfg BabyCribConfig
---@field coordinator CribCoordinator
---@field facility FacilityRegistry|nil
---@field cabinet_unit Unit|nil
---@field cabinet_layer any
---@field started boolean
local CribCareView = Class("CribCareView")

-- set_progressbar_current/max 要 Lua int：这里的 math 是定点数库，math.floor 返回 Fix32，
-- 必须再 math.tointeger 转成真正的整数，否则引擎报 “节点类型不正确 / expected int” 且进度条不刷新。
---@param x number
---@return integer
local function to_int(x)
    return math.tointeger(math.floor(x or 0)) or 0
end

---@param config BabyStormConfig
---@param crib_coordinator CribCoordinator
---@param facility_registry FacilityRegistry
function CribCareView:Ctor(config, crib_coordinator, facility_registry)
    self.cfg = config.crib
    self.coordinator = crib_coordinator
    self.facility = facility_registry
    self.cabinet_unit = nil
    self.cabinet_layer = nil
    self.started = false
end

---@return boolean
function CribCareView:start()
    if self.started then
        return true
    end
    if not (self.cfg and self.cfg.enabled) then
        return false
    end
    self.started = true

    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    for index = 1, #beds do
        self:_bind_progress_ui(beds[index])
    end
    self:_bind_cabinet_ui()

    Timer.every(self, self.cfg.poll_interval or 0.2, function() self:_refresh() end)
    return true
end

---@param facility BabyFacilityRecord|nil
function CribCareView:_bind_progress_ui(facility)
    local layer_key = Prefab.scene_eui and Prefab.scene_eui.progress_bar_canvas
    local bed = facility and facility.unit
    if not (facility and bed and layer_key and bed.create_scene_ui_bind_unit) then
        Log.warn("crib progress scene UI bind skipped", facility and facility.def and facility.def.id)
        return
    end
    facility.crib_progress_layer = bed.create_scene_ui_bind_unit(
        layer_key,
        Enums.ModelSocket.socket_origin,
        math.Vector3(0.0, 1.5, 0.0),
        -1.0,
        false,
        true
    )
    facility.crib_progress_node = GameAPI.get_eui_node_at_scene_ui(
        facility.crib_progress_layer,
        UINodes.progress_bar
    )
    Log.info("crib progress scene UI bound", tostring(bed), tostring(facility.crib_progress_layer))
end

function CribCareView:_bind_cabinet_ui()
    local layer_key = Prefab.scene_eui and Prefab.scene_eui.cabinet_canvas
    local unit_name = self.cfg.cabinet_unit_name or "木制边柜3"
    local cabinet = LuaAPI.query_unit(unit_name)
    if not (layer_key and cabinet and cabinet.create_scene_ui_bind_unit) then
        Log.warn("crib cabinet scene UI bind skipped", unit_name)
        return
    end

    local offset = self.cfg.cabinet_ui_offset or { 0, 1.5, 0 }
    self.cabinet_unit = cabinet
    self.cabinet_layer = cabinet.create_scene_ui_bind_unit(
        layer_key,
        Enums.ModelSocket.socket_origin,
        math.Vector3(offset[1], offset[2], offset[3]),
        -1.0,
        false,
        true
    )
    Log.info("crib cabinet scene UI bound", unit_name, tostring(self.cabinet_layer))
end

-- 每张床都各自绑了一份进度条场景 UI，这里逐张床判断是否显示/刷新，而不是只认
-- 第一张床——否则第二张床（儿童单人床1）永远拿不到进度条。
function CribCareView:_refresh()
    local roles = GameAPI.get_all_valid_roles() or {}
    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    for _, role in ipairs(roles) do
        local role_id = RoleUtil.get_role_id(role)
        local cabinet_visible = self:_role_near_pos(role, self.coordinator.cabinet_pos, self.cfg.cabinet_show_radius)
        -- 玩家可能中途断线，role 侧场景 UI 调用保留 pcall。
        if self.cabinet_layer and GameAPI.set_scene_ui_visible then
            pcall(function() GameAPI.set_scene_ui_visible(self.cabinet_layer, role, cabinet_visible) end)
        end

        local target_facility, action = self.coordinator:action_target_for_role(role, role_id)
        for index = 1, #beds do
            local bed = beds[index]
            local progress_layer = bed.crib_progress_layer
            local progress_visible = bed == target_facility and action ~= nil
            if progress_layer and GameAPI.set_scene_ui_visible then
                pcall(function() GameAPI.set_scene_ui_visible(progress_layer, role, progress_visible) end)
            end

            if progress_visible and bed.crib_progress_node then
                local current = 0
                local max = self.cfg.progress_max or 100
                if action == "reset" then
                    current = bed.crib_reset_progress or 0
                    max = self.cfg.reset_progress_max or 100
                else
                    current = bed.crib_session and bed.crib_session.progress or 0
                end
                -- 同上，role 可能已断线，进度条写入保留 pcall。
                pcall(function()
                    role.set_progressbar_min(bed.crib_progress_node, 0)
                    role.set_progressbar_max(bed.crib_progress_node, to_int(max))
                    role.set_progressbar_current(bed.crib_progress_node, to_int(current))
                end)
            end
        end
    end
end

---@param role Role
---@param pos Vector3|nil
---@param radius number
---@return boolean
function CribCareView:_role_near_pos(role, pos, radius)
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

function CribCareView:destroy()
    -- destroy 兜底：场景 UI 图层可能已随所在单位一并被引擎回收。
    if self.cabinet_layer and GameAPI.destroy_scene_ui then
        pcall(function() GameAPI.destroy_scene_ui(self.cabinet_layer) end)
        self.cabinet_layer = nil
        self.cabinet_unit = nil
    end
    local beds = self.facility and self.facility:get_facilities_by_kind("crib") or {}
    for index = 1, #beds do
        if beds[index].crib_progress_layer and GameAPI.destroy_scene_ui then
            pcall(function() GameAPI.destroy_scene_ui(beds[index].crib_progress_layer) end)
            beds[index].crib_progress_layer = nil
            beds[index].crib_progress_node = nil
        end
    end
    Timer.cancel_all(self)
    self.started = false
end

return CribCareView
