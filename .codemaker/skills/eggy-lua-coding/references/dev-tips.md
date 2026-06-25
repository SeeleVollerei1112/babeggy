# 蛋仔派对开发技巧

## Lua编码优化

### 优先使用局部变量
```lua
local Vector3 = math.Vector3
local RegEvent = LuaAPI.global_register_trigger_event
```

### 优先使用整数循环
```lua
for i = 1, 10 do
    foo(tab[i])
end
```

### 避免频繁取表长度
```lua
local length = #tab
for i = 1, length do
    foo(tab[i])
end
```

### 优化大量数据存储

将对象数组转为多个基础类型数组：
```lua
-- 原始方式
local all_data = {{ name="foo", pos={x=1,y=2}, size=5 }, ...}

-- 优化方式
local all_names = { "foo", ... }
local all_pos = { 1.0, 2.0, ... }
local all_size = { 5.0, ... }
```

Vector3展开存储：
```lua
-- 原始
local positions = { math.Vector3(1,2,3), math.Vector3(11,22,33) }

-- 优化
local positions = { 1.0, 2.0, 3.0, 11.0, 22.0, 33.0 }
```

### 调试技巧
- `print(table)` - 直接打印表内容
- `traceback()` - 获取调用栈信息

## 游戏逻辑技巧

### 分帧执行重度逻辑

避免一帧内执行过多逻辑导致卡顿：
```lua
LuaAPI.call_delay_frame(1, function()
    -- 延迟到下一帧执行
end)
```

### 缓存已创建的对象

维护对象池复用单位/特效，避免频繁创建：
```lua
local objectPool = {}

function getFromPool(key)
    if #objectPool[key] > 0 then
        return table.remove(objectPool[key])
    end
    return createNew(key)
end

function returnToPool(key, obj)
    obj:hide()
    table.insert(objectPool[key], obj)
end
```

### 使用触发器代替Tick轮询

避免每帧检查物体是否进入范围：
```lua
-- ❌ 不推荐：每帧轮询
local function onPreTick()
    for _, unit in ipairs(allUnits) do
        if isInRange(unit, center, range) then
            applyEffect(unit)
        end
    end
end

-- ✅ 推荐：使用触发器事件
LuaAPI.unit_register_trigger_event(triggerArea, { EVENT.ON_ENTER }, function(_, actor, data)
    applyEffect(data.enter_unit)
end)
```

### 延迟统一处理事件

避免事件回调中的冲突：
```lua
local pendingEvents = {}

LuaAPI.unit_register_trigger_event(unit, { EVENT.ON_HIT }, function(_, _, data)
    table.insert(pendingEvents, data)
end)

local function onPreTick()
    for _, event in ipairs(pendingEvents) do
        processEvent(event)
    end
    pendingEvents = {}
end
```

### 定时器管理

```lua
-- 单次定时器
local timerId = LuaAPI.global_register_trigger_event({ EVENT.TIMEOUT, 5.0 }, function()
    -- 5秒后执行一次
end)

-- 重复定时器
local timerId = LuaAPI.global_register_trigger_event({ EVENT.REPEAT_TIMEOUT, 1.0 }, function()
    -- 每秒执行
end)

-- 取消定时器
LuaAPI.global_unregister_trigger_event(timerId)
```
