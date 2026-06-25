# 脚本扩展Demo

展示单位创建监听器、导出函数给编辑器调用、碰撞事件处理等脚本扩展模式。

## 核心概念

### 单位创建监听器
- 监听特定类型/预设ID的单位被创建
- 在单位创建时自动注册事件或初始化逻辑
- 适用于动态生成的单位（如投射物、特效等）

### 导出函数
- 使用 `---@export` 注解标记函数
- 函数可被编辑器中的蓝图/触发器调用
- 支持参数和返回值

### 碰撞事件
- 监听单位与其他物体的碰撞
- 常用于投射物命中检测

## 完整示例

```lua
-- 常量定义
local ARROW_PRESET_ID = 1404042  -- 箭的预设ID
local CLOUD_PRESET_ID = 100636   -- 云朵的预设ID
local CLOUD_OFFSET = math.Vector3(2.5, 2.5, 2.5)

-- 局部变量
local Vector3 = math.Vector3
local Quaternion = math.Quaternion
local created_clouds = {}
local resurrect_count = 0

-- 创建云朵函数
local function create_cloud(arrow)
    -- 在箭的位置创建云朵
    local position = arrow.get_position() 
        - arrow.get_orientation():apply(Vector3(0.0, 1.0, 0.0)) * CLOUD_OFFSET
    local orientation = Quaternion(0.0, 0.0, 0.0)
    local scale = Vector3(1.0, 1.0, 1.0)
    return GameAPI.create_obstacle(CLOUD_PRESET_ID, position, orientation, scale, nil)
end

-- 监听箭的创建
LuaAPI.register_unit_creation_handler(
    Enums.UnitType.OBSTACLE,  -- 单位类型
    ARROW_PRESET_ID,          -- 预设ID
    function(arrow)           -- 创建回调
        -- 为新创建的箭注册碰撞事件
        LuaAPI.unit_register_trigger_event(
            arrow, 
            { EVENT.SPEC_OBSTACLE_CONTACT_BEGAN },
            function()
                -- 箭碰撞时创建云朵
                table.insert(created_clouds, create_cloud(arrow))
            end
        )
    end
)

-- 导出函数：供编辑器调用
---@export
---@desc 当重生时调用Lua
---@param save_clouds boolean 是否保留云朵
---@return integer 重生次数
function on_resurrection(save_clouds)
    print("Resurrect with clouds: " .. tostring(save_clouds))

    if not save_clouds then
        -- 清理所有创建的云朵
        for _, v in ipairs(created_clouds) do
            GameAPI.destroy_unit(v)
        end
        created_clouds = {}
    end

    resurrect_count = resurrect_count + 1
    return resurrect_count
end
```

## 关键API

### 单位创建监听
```lua
-- 监听特定类型和预设的单位创建
LuaAPI.register_unit_creation_handler(
    Enums.UnitType.OBSTACLE,  -- 单位类型
    presetId,                  -- 预设ID（编辑器中配置）
    function(unit)             -- 创建时的回调
        -- unit 是新创建的单位
    end
)

-- 单位类型枚举
Enums.UnitType.OBSTACLE    -- 障碍物
Enums.UnitType.CREATURE    -- 生物
Enums.UnitType.EQUIPMENT   -- 装备
```

### 碰撞事件
```lua
-- 障碍物碰撞开始
EVENT.SPEC_OBSTACLE_CONTACT_BEGAN

-- 障碍物碰撞结束
EVENT.SPEC_OBSTACLE_CONTACT_ENDED

-- 注册碰撞事件
LuaAPI.unit_register_trigger_event(unit, { EVENT.SPEC_OBSTACLE_CONTACT_BEGAN }, 
    function(eventName, actor, data)
        -- data.contact_unit 碰撞的另一个单位
    end
)
```

### 导出函数注解
```lua
-- 基本导出
---@export
function my_function()
end

-- 带描述的导出
---@export
---@desc 函数描述，会显示在编辑器中
function my_function()
end

-- 带参数和返回值的导出
---@export
---@desc 计算两数之和
---@param a number 第一个数
---@param b number 第二个数
---@return number 计算结果
function add(a, b)
    return a + b
end
```

## 使用场景

### 投射物系统
```lua
local BULLET_PRESET_ID = 12345

LuaAPI.register_unit_creation_handler(Enums.UnitType.OBSTACLE, BULLET_PRESET_ID, 
    function(bullet)
        -- 子弹命中时造成伤害
        LuaAPI.unit_register_trigger_event(bullet, { EVENT.SPEC_OBSTACLE_CONTACT_BEGAN },
            function(_, _, data)
                local target = data.contact_unit
                if target and target.modify_attr then
                    target.modify_attr(Enums.AttrType.HP, -10)
                end
                GameAPI.destroy_unit(bullet)
            end
        )
    end
)
```

### 陷阱系统
```lua
local TRAP_PRESET_ID = 67890

LuaAPI.register_unit_creation_handler(Enums.UnitType.OBSTACLE, TRAP_PRESET_ID,
    function(trap)
        LuaAPI.unit_register_trigger_event(trap, { EVENT.SPEC_OBSTACLE_CONTACT_BEGAN },
            function(_, _, data)
                local unit = data.contact_unit
                -- 检查是否是角色
                if unit.get_role then
                    local role = unit.get_role()
                    if role then
                        role.show_tips("触发陷阱！", 2.0)
                    end
                end
            end
        )
    end
)
```

## 注意事项

1. **导出函数必须是全局函数**：使用 `function name()` 而非 `local function name()`
2. **预设ID从编辑器获取**：在编辑器中查看单位的预设ID
3. **碰撞事件可能频繁触发**：考虑添加冷却或状态检查
4. **创建监听器在游戏开始前注册**：确保不会错过任何单位创建
