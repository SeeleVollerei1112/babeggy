# 建造/焊接系统Demo

展示射线检测、物理关节、举起/放下事件、相机控制、自定义事件等高级交互模式。

## 核心概念

### 射线检测 (Raycast)
- 从指定位置沿方向发射射线
- 检测碰撞到的单位和位置
- 常用于瞄准、放置、交互检测

### 物理关节
- 使用 `create_joint_assistant` 创建物理连接
- 支持多种关节类型（FIXED固定、HINGE铰链等）
- 可用于建造、机关等系统

### 举起/放下系统
- 监听 `LIFT_BEGAN` 和 `LIFT_ENDED` 事件
- 举起时可修改被举物体属性
- 放下时可执行放置逻辑

### 自定义事件
- 从UI按钮触发Lua逻辑
- 使用 `global_register_custom_event` 注册

## 焊接控制器完整实现

```lua
local UnitPrefab = require("Data.Prefab").unit
local UINodes = require("Data.UINodes")
local class = require("Utils.ClassUtils").class

---@class StickController
local StickController = class("StickController")

function StickController:ctor()
    self.previewUnits = {}   -- 预览焊接位置的指示器
    self.charLiftInfos = {}  -- 角色举起物体的信息

    local scale = 0.5
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        local roleId = role.get_roleid()

        -- 创建焊接预览指示器
        self.previewUnits[roleId] = GameAPI.create_obstacle(
            UnitPrefab["焊接预览"],
            math.Vector3(0, 0, 0),
            math.Quaternion(0, 0, 0),
            math.Vector3(scale, scale, scale),
            role
        )

        self.charLiftInfos[roleId] = {}
        local character = role.get_ctrl_unit()

        -- 监听角色举起物体事件
        LuaAPI.unit_register_trigger_event(character, { EVENT.SPEC_LIFEENTITY_LIFT_BEGAN }, 
            function(_, _, data)
                local lifted = data.lifted_unit
                self:tryRemoveStickJoints(lifted)

                -- 举起时：变半透明 + 关闭物理
                lifted.enable_expr_device_by_name("修改透明度")
                lifted.set_physics_active(false)

                self.charLiftInfos[roleId] = { unit = lifted }

                -- 开启相机朝向同步（用于瞄准）
                role.set_camera_rotation_sync_enabled(true)
            end
        )

        -- 监听角色放下物体事件
        LuaAPI.unit_register_trigger_event(character, { EVENT.SPEC_LIFEENTITY_LIFT_ENDED }, 
            function(_, _, data)
                local lifted = data.lifted_unit

                -- 放下时：恢复透明度 + 恢复物理
                lifted.disable_expr_device_by_name("修改透明度")
                lifted.set_physics_active(true)
                self.charLiftInfos[roleId] = {}

                -- 设置放下位置（角色前方）
                local direction = character.get_orientation():apply(math.Vector3(0, 2, 0))
                lifted.set_position(character.get_position() + direction)
                lifted.set_orientation(character.get_orientation())

                -- 关闭相机朝向同步
                role.set_camera_rotation_sync_enabled(false)
            end
        )
    end

    -- 隐藏所有预览指示器
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        for _, unit in pairs(self.previewUnits) do
            role.set_unit_visible(unit, false)
        end
    end

    -- 注册焊接按钮点击事件（自定义事件）
    LuaAPI.global_register_custom_event("点击焊接", function(_, _, data)
        local role = data.role
        local liftInfo = self.charLiftInfos[role.get_roleid()]
        if self:checkRoleCanStick(role, liftInfo) then
            self:tryStickUnit(role, liftInfo)
        end
    end)
end
```

## 射线检测实现

```lua
function StickController:checkRoleCanStick(role, liftInfo)
    if not liftInfo.unit then
        return false
    end

    -- 获取相机朝向（需要先开启同步）
    local camRot = role.get_camera_rotation()
    if camRot.w == 0 then
        -- 相机朝向未更新时跳过
        return false
    end

    local character = role.get_ctrl_unit()
    -- 射线起点：角色头顶
    local startPos = character.get_position() + math.Vector3(0, 2.9, 0)
    -- 射线方向：相机朝向
    local direction = camRot:apply(math.Vector3(0, 0, 1))
    local length = 15.0
    
    liftInfo.stickTo = nil
    liftInfo.stickPos = nil

    -- 发射射线检测障碍物
    GameAPI.raycast_unit(
        startPos,                           -- 起点
        startPos + direction * length,      -- 终点
        { Enums.UnitType.OBSTACLE },        -- 检测类型
        function(unit, point, normal)       -- 命中回调
            liftInfo.stickTo = unit         -- 命中的单位
            liftInfo.stickPos = point       -- 命中位置
        end
    )

    return liftInfo.stickTo ~= nil
end
```

## 物理关节创建

```lua
function StickController:tryStickUnit(role, liftInfo)
    if liftInfo.stickTo and liftInfo.stickTo ~= liftInfo.unit then
        -- 先放下物体
        role.get_ctrl_unit().lift_unit(liftInfo.unit)

        -- 设置位置和朝向
        liftInfo.unit.set_physics_active(true)
        liftInfo.unit.set_position(liftInfo.stickPos)
        liftInfo.unit.set_orientation(liftInfo.stick_rot or role.get_ctrl_unit().get_orientation())
        
        -- 创建固定关节连接两个物体
        local joint = GameAPI.create_joint_assistant(
            Enums.JointAssistantKey.FIXED,  -- 关节类型
            liftInfo.unit,                   -- 物体A
            liftInfo.stickTo                 -- 物体B
        )

        -- 使用KV标记关节，便于后续删除
        joint.set_kv_by_type(Enums.ValueType.Bool, "isDynamicStick", true)
    end
end

function StickController:tryRemoveStickJoints(unit)
    -- 删除单位上所有动态焊接的关节
    for _, v in ipairs(GameAPI.get_joint_assistants(unit)) do
        if v.has_kv("isDynamicStick") then
            GameAPI.destroy_unit(v)
        end
    end
end
```

## 每帧更新预览

```lua
function StickController:update()
    for roleid, liftInfo in pairs(self.charLiftInfos) do
        local role = GameAPI.get_role(roleid)
        local previewUnit = self.previewUnits[role.get_roleid()]
        
        local canStick = self:checkRoleCanStick(role, liftInfo)
        
        -- 根据是否可焊接，显示/隐藏UI和预览
        role.set_node_visible(UINodes["焊接按钮"], canStick)
        role.set_unit_visible(previewUnit, canStick)

        if canStick then
            -- 更新预览位置
            local rot = role.get_ctrl_unit().get_orientation()
            previewUnit.set_position(liftInfo.stickPos)
            previewUnit.set_orientation(rot)
        end
    end
end
```

## 关键API

### 射线检测
```lua
-- 射线检测单位
GameAPI.raycast_unit(
    startPos,       -- Vector3 起点
    endPos,         -- Vector3 终点
    unitTypes,      -- table 检测的单位类型 { Enums.UnitType.OBSTACLE, ... }
    callback        -- function(unit, point, normal) 命中回调
)
```

### 物理关节
```lua
-- 创建关节
local joint = GameAPI.create_joint_assistant(
    Enums.JointAssistantKey.FIXED,  -- 关节类型：FIXED/HINGE/SLIDER等
    unitA,                           -- 第一个单位
    unitB                            -- 第二个单位
)

-- 获取单位上的所有关节
local joints = GameAPI.get_joint_assistants(unit)

-- 销毁关节
GameAPI.destroy_unit(joint)
```

### 举起/放下事件
```lua
-- 举起开始
EVENT.SPEC_LIFEENTITY_LIFT_BEGAN
-- data.lifted_unit 被举起的单位

-- 举起结束（放下）
EVENT.SPEC_LIFEENTITY_LIFT_ENDED
-- data.lifted_unit 被放下的单位

-- 主动放下物体
character.lift_unit(targetUnit)
```

### 相机控制
```lua
-- 开启/关闭相机朝向同步
role.set_camera_rotation_sync_enabled(true/false)

-- 获取相机朝向（四元数）
local camRot = role.get_camera_rotation()

-- 应用旋转到向量
local direction = camRot:apply(math.Vector3(0, 0, 1))
```

### 表达式设备（特效控制）
```lua
-- 启用表达式设备（如透明度修改）
unit.enable_expr_device_by_name("修改透明度")

-- 禁用表达式设备
unit.disable_expr_device_by_name("修改透明度")
```

### 自定义事件
```lua
-- 注册自定义事件（从UI按钮触发）
LuaAPI.global_register_custom_event("事件名称", function(_, _, data)
    local role = data.role  -- 触发事件的玩家
    -- 处理逻辑
end)
```

### 单位可见性控制
```lua
-- 对指定玩家显示/隐藏单位
role.set_unit_visible(unit, true/false)
```

### KV存储（单位数据标记）
```lua
-- 设置单位的KV数据
unit.set_kv_by_type(Enums.ValueType.Bool, "keyName", true)

-- 检查是否有指定KV
if unit.has_kv("keyName") then
    -- ...
end
```
