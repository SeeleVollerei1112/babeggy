# 模型切换/装扮系统Demo

展示角色模型切换、单位组创建、区域触发装扮变换的实现。

## 核心概念

### 模型切换
- 使用 `character.set_model_by_creature_key` 切换角色外观
- 使用 `character.reset_model` 恢复原始外观
- 不影响角色属性，只改变视觉表现

### 单位组
- 使用 `GameAPI.create_unit_group` 创建预制好的单位组合
- 可通过 `get_children()` 遍历子单位
- 子单位可按名称查找并设置属性

### 区域触发
- 监听角色进入/离开特定区域
- 常用于触发装扮切换、商店打开等

## 装扮区域类

```lua
local class = require("Utils.ClassUtils").class

---@class DressUpArea
local DressUpArea = class("DressUpArea")

function DressUpArea:ctor(dressUpId, info, enterCallback, exitCallback, pos, yaw)
    self.id = dressUpId
    self.info = info
    self.enterCb = enterCallback
    self.exitCb = exitCallback
    self:createArea(pos, yaw)
end

function DressUpArea:createArea(pos, yaw)
    local info = self.info
    
    -- 创建单位组
    local area = GameAPI.create_unit_group(
        Consts.JOB_CHOOSE_PREFAB,       -- 单位组预设ID
        pos,                             -- 位置
        math.Quaternion(0, yaw, 0)       -- 旋转
    )
    self.areaObj = area
    
    -- 遍历单位组中的子对象
    for _, child in ipairs(area.get_children()) do
        local childName = child.get_name()
        
        -- 找到名称标签并设置文字
        if string.find(childName, "名称", 1, true) == 1 then
            child.set_billboard_text(info.name)
        end
        
        -- 找到选择区域并注册触发器
        if string.find(childName, "选择区域", 1, true) == 1 then
            local areaId = LuaAPI.get_unit_id(child)
            
            -- 注册进入区域事件
            LuaAPI.global_register_trigger_event(
                { EVENT.ANY_LIFEENTITY_TRIGGER_SPACE, Enums.TriggerSpaceEventType.ENTER, areaId },
                function(_, _, data)
                    local character = data.event_unit
                    local role = character.get_role()
                    if role and character.get_camp_id() ~= -1 then
                        self.enterCb(role, character)
                    end
                end
            )
            
            -- 注册离开区域事件
            self.exitTrigger = LuaAPI.global_register_trigger_event(
                { EVENT.ANY_LIFEENTITY_TRIGGER_SPACE, Enums.TriggerSpaceEventType.LEAVE, areaId },
                function(_, _, data)
                    local character = data.event_unit
                    local role = character.get_role()
                    if self.exitCb then
                        self.exitCb(role, character)
                    end
                end
            )
        end
    end
    
    -- 创建展示用模型
    if info.modelCreatureKey then
        local dir = math.Vector3(0, 0, 1)
        dir:set_pitch_yaw(0, yaw + math.pi / 2)
        
        self.showObj = GameAPI.create_creature(
            info.modelCreatureKey,
            pos + dir * 1.0,
            math.Quaternion(0, yaw + math.pi / 2, 0),
            math.Vector3(1, 1, 1)
        )
    end
end
```

## 圆形布局算法

```lua
local function setupDressUpAreas()
    local dressUpDatas = {}
    for key, info in pairs(DressUpData) do
        table.insert(dressUpDatas, { key, info })
    end
    
    -- 计算圆形排列参数
    local numDressUps = #dressUpDatas
    local angleDelta = math.pi * 2.0 / numDressUps
    local radius = 30
    local currAngle = 0.0
    
    -- 创建每个装扮区域
    for _, data in ipairs(dressUpDatas) do
        local key = data[1]
        local info = data[2]
        
        -- 计算圆周上的位置
        local dir = math.Vector3(math.cos(currAngle), 0, math.sin(currAngle))
        local pos = math.Vector3(0, -4, 0) + dir * radius
        local yaw = math.pi - currAngle  -- 朝向圆心
        
        createDressUpArea(key, info, pos, yaw)
        currAngle = currAngle + angleDelta
    end
    
    -- 创建"取消装扮"区域（在圆心）
    DressUpArea.new("Default", { name = "取消装扮" }, function(role, character)
        character.reset_model()  -- 恢复原始模型
    end, nil, math.Vector3(0, -4, 0), math.pi)
end
```

## 装扮切换回调

```lua
local function createDressUpArea(key, info, pos, yaw)
    -- 进入区域时切换模型
    local function _enterCallback(role, character)
        if character.get_role_id() == -1 then
            return
        end
        character.set_model_by_creature_key(info.modelCreatureKey)
    end
    
    DressUpArea.new(key, info, _enterCallback, nil, pos, yaw)
end
```

## 装扮配置示例 (Data/DressUpData.lua)

```lua
local DressUpData = {
    ["机器人"] = {
        name = "机器人",
        modelCreatureKey = "robot_creature_key",
    },
    ["恐龙"] = {
        name = "恐龙",
        modelCreatureKey = "dino_creature_key",
    },
    ["独角兽"] = {
        name = "独角兽",
        modelCreatureKey = "unicorn_creature_key",
    },
}
return DressUpData
```

## 关键API

### 模型切换
```lua
-- 切换角色模型为指定生物外观
character.set_model_by_creature_key(creatureKey)

-- 恢复原始模型
character.reset_model()
```

### 单位组
```lua
-- 创建单位组
local group = GameAPI.create_unit_group(prefabId, position, rotation)

-- 获取子单位列表
local children = group.get_children()

-- 获取单位名称
local name = unit.get_name()

-- 获取单位ID（用于事件注册）
local unitId = LuaAPI.get_unit_id(unit)
```

### 3D文字
```lua
-- 设置单位的公告板文字（始终朝向摄像机）
unit.set_billboard_text("显示文字")
```

### 向量操作
```lua
-- 设置向量的俯仰和偏航角
local dir = math.Vector3(0, 0, 1)
dir:set_pitch_yaw(pitch, yaw)

-- 三角函数（使用math库，非标准Lua）
math.cos(angle)
math.sin(angle)
math.pi
```

### 区域触发事件
```lua
-- 进入区域
{ EVENT.ANY_LIFEENTITY_TRIGGER_SPACE, Enums.TriggerSpaceEventType.ENTER, areaUnitId }

-- 离开区域
{ EVENT.ANY_LIFEENTITY_TRIGGER_SPACE, Enums.TriggerSpaceEventType.LEAVE, areaUnitId }

-- 事件数据
data.event_unit  -- 触发事件的单位
```
