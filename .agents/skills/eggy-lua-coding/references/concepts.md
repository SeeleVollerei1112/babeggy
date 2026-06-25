# 蛋仔派对游戏概念

## 单位与类型

单位是游戏运行时对游戏中对象的抽象，包括障碍物、机关、物理区域和角色等。

使用 `LuaAPI.get_value_type(unit)` 或 `type(unit)` 获取类型（返回值带"L"前缀）。

### 常见单位类型

| 类型 | 描述 |
|-----|------|
| Obstacle | 碰撞体（墙、门等） |
| LifeEntity | 生命体（玩家角色、生物等） |
| Trigger | 触发器 |
| Character | 玩家角色 |
| Creature | 生物 |
| Equipment | 装备 |

### 类型继承关系
- Character 继承自 LifeEntity
- Creature 继承自 LifeEntity
- 单位可调用：自身类型API + 继承类型API + 包含部件(Comp)API

## 预设与组件

- **预设**: 游戏编辑期的单位模板，在预设编辑器中创建
- **组件**: 游戏编辑期摆放在场景中的物体，指明使用的预设和位置等属性

游戏开始时，组件实例化为单位，继承预设属性。

### 组件性能优化

开启后组件仅作为静态障碍物，不实例化为单位，无法通过Lua访问。

适用场景：纯景观/纯障碍物，可大幅提高性能。

## 坐标系统

- **左手坐标系**，Y轴竖直向上
- 坐标范围：(-1000.0, 1000.0)
- 坐标/缩放过大可能导致渲染闪烁或碰撞偏移

## 逻辑帧

游戏逻辑按每秒30帧执行，与设备画面帧率无关。

```lua
LuaAPI.set_tick_handler(pre_tick_handler, post_tick_handler)
```

**注意**: 频繁使用帧回调执行重度逻辑会导致性能问题，优先使用事件回调。

## 事件系统

事件是单位间通信和驱动游戏逻辑的主要手段。

### 监听事件
```lua
LuaAPI.unit_register_trigger_event(unit, { EVENT.xxx }, callback)
LuaAPI.global_register_trigger_event({ EVENT.xxx }, callback)
```

### 发送事件
```lua
LuaAPI.unit_send_custom_event(unit, eventData)
LuaAPI.global_send_custom_event(eventData)
```

### 典型事件
- 游戏初始化/结束
- 玩家操作（跳跃、前扑、滚动等）
- 单位进入/退出区域
- 单位被攻击

**注意**: 不要依赖同一帧内事件的执行顺序。建议先收集事件数据，然后延后统一处理。

## 物理系统

通过内置组件提供：

| 组件 | 功能 |
|-----|------|
| 普通组件 | 物理碰撞、反弹 |
| 关节 | 软约束（绳子、合页等） |
| 水体 | 浮力效果 |
| 载具 | 自定义物理形状的载具运动 |
| 重力场 | 区域性重力效果 |
