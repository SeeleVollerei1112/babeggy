# 事件处理模式

## 事件注册基础

### 全局事件
```lua
-- 注册
local triggerId = LuaAPI.global_register_trigger_event({ EVENT.xxx, ...params }, 
    function(eventName, actor, data)
        -- 回调处理
    end
)

-- 取消注册
LuaAPI.global_unregister_trigger_event(triggerId)
```

### 单位事件
```lua
-- 注册
local triggerId = LuaAPI.unit_register_trigger_event(unit, { EVENT.xxx }, 
    function(eventName, actor, data)
        -- actor 是触发事件的单位
        -- data 包含事件相关数据
    end
)

-- 取消注册
LuaAPI.unit_unregister_trigger_event(triggerId)
```

## 常用事件类型

### 游戏生命周期
```lua
-- 游戏初始化
LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    -- 初始化逻辑
end)

-- 游戏结束
LuaAPI.global_register_trigger_event({ EVENT.GAME_END }, function()
    -- 清理逻辑
end)
```

### 定时器事件
```lua
-- 单次定时器（5秒后执行一次）
LuaAPI.global_register_trigger_event({ EVENT.TIMEOUT, 5.0 }, function()
    print("5秒到了")
end)

-- 重复定时器（每秒执行）
local timerId = LuaAPI.global_register_trigger_event({ EVENT.REPEAT_TIMEOUT, 1.0 }, 
    function(eventName, actor, data)
        print("每秒执行")
    end
)

-- 停止重复定时器
LuaAPI.global_unregister_trigger_event(timerId)
```

### 单位死亡
```lua
LuaAPI.unit_register_trigger_event(unit, { EVENT.ON_DEAD }, function(eventName, actor, data)
    local deadUnit = actor
    local killer = data.damage_source  -- 伤害来源
    print("单位死亡")
end)
```

### 区域触发
```lua
-- 进入区域
LuaAPI.unit_register_trigger_event(triggerArea, { EVENT.ON_ENTER }, function(_, actor, data)
    local enteringUnit = data.enter_unit
    print("单位进入区域")
end)

-- 离开区域
LuaAPI.unit_register_trigger_event(triggerArea, { EVENT.ON_LEAVE }, function(_, actor, data)
    local leavingUnit = data.leave_unit
    print("单位离开区域")
end)
```

### 碰撞事件
```lua
LuaAPI.unit_register_trigger_event(unit, { EVENT.ON_COLLISION }, function(_, actor, data)
    local otherUnit = data.other_unit
    print("发生碰撞")
end)
```

## 事件处理模式

### 模式1：回调中直接处理
适用于简单逻辑，无状态冲突风险。

```lua
LuaAPI.unit_register_trigger_event(unit, { EVENT.ON_HIT }, function(_, actor, data)
    actor.modify_attr("hp", -data.damage)
end)
```

### 模式2：收集后统一处理
避免同帧事件冲突，适用于复杂逻辑。

```lua
local pendingHits = {}

LuaAPI.unit_register_trigger_event(unit, { EVENT.ON_HIT }, function(_, actor, data)
    table.insert(pendingHits, {
        target = actor,
        damage = data.damage,
        source = data.source
    })
end)

local function onPreTick()
    for _, hit in ipairs(pendingHits) do
        processHit(hit)
    end
    pendingHits = {}
end
```

### 模式3：状态机驱动
适用于复杂的多阶段逻辑。

```lua
local gameState = "waiting"

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    gameState = "playing"
    startGame()
end)

LuaAPI.global_register_trigger_event({ EVENT.REPEAT_TIMEOUT, 1.0 }, function()
    if gameState == "playing" then
        updateGame()
    elseif gameState == "paused" then
        -- 暂停状态不更新
    end
end)

function pauseGame()
    gameState = "paused"
end

function resumeGame()
    gameState = "playing"
end
```

### 模式4：事件转发
将单位事件转发给管理器处理。

```lua
function MonsterManager:createMonster(data, pos, rot)
    local creature = GameAPI.create_creature(data.prefabID, pos, rot)
    
    -- 注册死亡事件，转发给管理器
    LuaAPI.unit_register_trigger_event(creature, { EVENT.ON_DEAD }, function(_, actor, eventData)
        self:onMonsterDead(creature, eventData.damage_source)
    end)
    
    table.insert(self.monsters, creature)
    return creature
end

function MonsterManager:onMonsterDead(monster, killer)
    -- 统一处理怪物死亡
    self:removeMonster(monster)
    self:giveReward(killer)
    self:checkWaveComplete()
end
```

## 自定义事件

### 发送自定义事件
```lua
-- 发送给单位
LuaAPI.unit_send_custom_event(unit, {
    event_name = "MY_CUSTOM_EVENT",
    data1 = value1,
    data2 = value2
})

-- 全局发送
LuaAPI.global_send_custom_event({
    event_name = "GAME_PHASE_CHANGE",
    phase = 2
})
```

### 接收自定义事件
```lua
LuaAPI.unit_register_trigger_event(unit, { EVENT.CUSTOM_EVENT }, function(_, actor, data)
    if data.event_name == "MY_CUSTOM_EVENT" then
        handleCustomEvent(data)
    end
end)
```

## 注意事项

1. **不要依赖同帧事件顺序** - 同一帧内多个事件的执行顺序不确定
2. **避免在回调中修改其他单位** - 可能与其他事件冲突，建议延后处理
3. **及时取消注册** - 单位销毁前应取消注册的事件，避免内存泄漏
4. **定时器性能** - 大量定时器会影响性能，考虑合并或使用帧回调
