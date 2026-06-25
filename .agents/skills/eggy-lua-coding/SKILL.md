---
name: eggy-lua-coding
description: |
  蛋仔派对帧同步编辑器 Lua 开发技能。提供开发流程、API 探索、核心代码模式、编码规则等参考。

  使用场景：编写游戏运行时 Lua 代码，开发自定义玩法/地图、了解 EggyAPI、编写游戏逻辑。
---

# Lua 开发指南

## 专业的开发流程

1. 需求分析
2. 代码实现设计
3. 实现计划指定
4. 按计划实现
5. 测试验证

## API 探索

1. grep 搜索 `EggyAPI.lua` 查找相关 API
2. 阅读 LuaDoc 注解理解参数和返回值
3. 参考 demos 中的实际使用样例

## 核心代码模式

### 游戏初始化
```lua
LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        local character = role.get_ctrl_unit()
    end
end)
```

### 事件注册
```lua
-- 全局定时器
LuaAPI.global_register_trigger_event({ EVENT.REPEAT_TIMEOUT, 1.0 }, callback)

-- 单位事件
LuaAPI.unit_register_trigger_event(unit, { EVENT.ON_DEAD }, callback)
```

### 创建单位
```lua
local equipment = GameAPI.create_equipment(prefabID, position)
local creature = GameAPI.create_creature(creatureKey, position, rotation)
```

### UI 操作
```lua
role.set_label_text(nodeId, "文本")
role.set_node_visible(nodeId, true)
role.send_ui_custom_event("EVENT_NAME", {})
```

### 位置和移动
```lua
local pos = unit.get_position()
unit.set_position(math.Vector3(x, y, z))
local dir = unit.get_direction()
```

## 编码规则（请遵守）

### 基础规则

1. 坐标：左手坐标系，Y 轴向上
2. 逻辑帧：30 帧/秒
3. 数值：使用定点数(Fixed)
4. 沙盒限制：无 io/os/debug 库
5. 性能：优先事件而非 Tick 轮询
6. 所有 Lua 文件必须使用 UTF-8 编码

### 不使用 number 类型，使用 interger + Fixed 类型

- Lua沙盒环境支持 interger 类型和 Fixed 类型的隐式转换：`local x = 5.0 + 1  -- 支持，x 是 Fixed 类型`
- API调用不一定支持 interger 类型和 Fixed 类型的隐式转换，建议主动使用 `math.tointeger()` 和 `math.tofixed()` 进行转换：`Role.set_unit_outline(_unit, 1.0, 0xFF0000)  -- 错误，第二个参数需要 interger 类型`

### `math` 库删除的 API

- `math.type()`：删除
- `math.ult()`：删除
- `math.random()`：删除，请使用 `LuaAPI.rand()`
- `math.randomseed()`：删除，`LuaAPI.rand()` 使用自动分配的seed来保证联机状态下的同步性
- `math.deg()`：删除（改名），请使用 `math.deg_to_rad()`
- `math.rad()`：删除（改名），请使用 `math.rad_to_deg()`
- `math.modf()`：删除
- `math.pi`：删除，请直接使用字面值常量
- `math.maxinteger`：删除
- `math.mininteger`：删除
- `math.huge`：删除

### table 键不能使用 Fixed 类型

```lua
my_table[math.floor(1.0)]      -- 错误
my_table[math.tointeger(1.0)]  -- 正确
```

### 方法调用用 `.` 而非 `:`
```lua
role.get_ctrl_unit()  -- 正确
role:get_ctrl_unit()  -- 错误
```

### Vector3 分量直接访问
```lua
local pos = unit.get_position()
local x = pos.x  -- 正确
```

### 延迟调用
```lua
LuaAPI.call_delay_time(1.0, function() end)  -- 正确
```

### Fixed 类型传浮点数
```lua
role.set_camera_property(Enums.CameraPropertyType.DIST, 30.0)  -- 正确
```

### Quaternion 用弧度
```lua
local PI = 3.14159265
local rot = math.Quaternion(0, PI, 0)  -- 180度
```

### game_execute 引号规则

```batch
# 正确：外层双引号，Lua内全单引号
%CLI% exec "EditorAPI.game_execute('local x = ''hello''; print(''MCP|'' .. x)')"
```

## 参考文档

| 需求 | 文档 |
|-----|------|
| 游戏概念、单位类型、坐标系、物理系统 | `references/concepts.md` |
| Lua 环境限制、沙盒约束 | `references/lua-env.md` |
| 性能优化技巧、编码规范 | `references/dev-tips.md` |
| 类定义模式、OOP写法 | `references/patterns/class-utils.md` |
| 事件注册/取消/模式 | `references/patterns/event-patterns.md` |
| Manager 管理器模式 | `references/patterns/manager-patterns.md` |
| 战斗/怪物AI/波次刷怪/英雄等级 | `references/demos/fight-demo.md` |
| 物品系统/背包/商店 | `references/demos/items-demo.md` |
| 建造/射线检测/物理关节/相机控制 | `references/demos/build-demo.md` |
| 脚本扩展/单位创建监听/碰撞事件 | `references/demos/gameplay-demo.md` |
| 存档系统/称号/3D场景UI | `references/demos/label-demo.md` |
| 开放世界/动态地块加载/对象池 | `references/demos/openworld-demo.md` |
| 模型切换/角色装扮/区域触发变换 | `references/demos/textures-demo.md` |
| 无尽跳跃/成就系统/游戏结束存档 | `references/demos/unlimitjump-demo.md` |

## 具体功能请参考

| 功能 | 文档 |
|-----|------|
| UI界面（EUI） | `references/features/eggy-eui-lua-dev/SKILL.md` |