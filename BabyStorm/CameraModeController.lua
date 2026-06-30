local UINodes = require("Data.UINodes")
local RoleUtil = require("Util.RoleUtil")
local Log = require("Util.Log")

---相机视角模式切换控制器
---职责：仅负责相机表现层（俯角/距离/视场/是否可拖动），不触碰宝宝 AI 的任何一层。
---由 HUD 上的 camera_mode_switcher 按钮点击驱动，在两套预设视角间切换。
---@class CameraModeController: GameController
local CameraModeController = {}

---相机属性枚举（优先用引擎 Enums，缺失时回退到字面值）
local CameraPropertyType = (Enums and Enums.CameraPropertyType) or {
    DIST = 7,
    FOV = 8,
    PITCH_MAX = 9,
    PITCH_MIN = 10,
    PITCH = 15,
    YAW = 16,
}

---EUI 触摸事件类型：点击
local TOUCH_CLICK = 1

---视角模式
local MODE_FREE = 1  ---原始可拖动第三人称视角（未改动前）
local MODE_FIXED = 2 ---固定盆景俯视视角（锁定不可旋转）

---进入游戏时的默认模式
local DEFAULT_MODE = MODE_FIXED

---@class CameraModePreset
---@field pitch number    俯仰角（低头度数）
---@field yaw number      偏航角（朝向）
---@field dist number     相机距离（越小物体越大）
---@field fov number      视场角（越大立体感越强）
---@field pitch_min number 可拖动时的最小俯角
---@field pitch_max number 可拖动时的最大俯角
---@field draggable boolean 玩家是否可拖动旋转

---@type table<integer, CameraModePreset>
local PRESETS = {
    [MODE_FREE] = {
        pitch = 30.0, yaw = 0.0, dist = 13.0, fov = 55.0,
        pitch_min = 15.0, pitch_max = 55.0, draggable = true,
    },
    [MODE_FIXED] = {
        pitch = 40.0, yaw = 0.0, dist = 36.0, fov = 45.0,
        pitch_min = 40.0, pitch_max = 40.0, draggable = false,
    },
}

---@type table<integer, integer> role_id -> 当前模式
local role_modes = {}

---把指定预设应用到玩家相机
---@param role Role
---@param mode integer
local function apply_mode(role, mode)
    local preset = PRESETS[mode]
    if not (role and preset) then
        return
    end
    -- 先放开/锁定拖动，再写入朝向与缩放，避免被拖动逻辑覆盖
    role.set_camera_draggable(preset.draggable)
    role.set_camera_property(CameraPropertyType.PITCH_MIN, preset.pitch_min)
    role.set_camera_property(CameraPropertyType.PITCH_MAX, preset.pitch_max)
    role.set_camera_property(CameraPropertyType.PITCH, preset.pitch)
    role.set_camera_property(CameraPropertyType.YAW, preset.yaw)
    role.set_camera_property(CameraPropertyType.DIST, preset.dist)
    role.set_camera_property(CameraPropertyType.FOV, preset.fov)
end

---设置并记录某玩家的视角模式
---@param role Role
---@param mode integer
local function set_role_mode(role, mode)
    local role_id = RoleUtil.get_role_id(role)
    if not role_id then
        return
    end
    role_modes[role_id] = mode
    apply_mode(role, mode)
end

---在两套视角间切换
---@param role Role
local function toggle_role_mode(role)
    local role_id = RoleUtil.get_role_id(role)
    if not role_id then
        return
    end
    local current = role_modes[role_id] or DEFAULT_MODE
    local next_mode = (current == MODE_FIXED) and MODE_FREE or MODE_FIXED
    set_role_mode(role, next_mode)
    Log.info("camera mode switched", role_id, next_mode)
end

---@param application GameApplication|nil
function CameraModeController.init(application)
    role_modes = {}

    -- 所有在场玩家套用默认视角
    local roles = GameAPI.get_all_valid_roles() or {}
    for index = 1, #roles do
        set_role_mode(roles[index], DEFAULT_MODE)
    end

    -- 绑定 HUD 切换按钮（经 application 注册，destroy 时自动反注册）
    local handler = function(event_name, actor, data)
        local role = data and data.role
        if role then
            toggle_role_mode(role)
        end
    end
    local event_spec = { EVENT.EUI_NODE_TOUCH_EVENT, UINodes.camera_mode_switcher, TOUCH_CLICK }
    if application and application.register_global_trigger then
        application.register_global_trigger(event_spec, handler)
    else
        LuaAPI.global_register_trigger_event(event_spec, handler)
    end
end

---@param application GameApplication|nil
function CameraModeController.destroy(application)
    role_modes = {}
end

return CameraModeController
