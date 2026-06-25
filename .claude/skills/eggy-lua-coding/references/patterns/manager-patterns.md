# 管理器模式

## 帧更新管理器

集中管理所有需要每帧更新的对象。

```lua
-- main.lua
G = {}

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    -- 可更新对象列表
    G.tickables = {}

    -- 添加可更新对象
    function G.addTickable(obj)
        assert(obj.update, "对象必须有update方法")
        table.insert(G.tickables, obj)
    end

    -- 移除可更新对象
    function G.removeTickable(obj)
        for i, v in ipairs(G.tickables) do
            if v == obj then
                table.remove(G.tickables, i)
                break
            end
        end
    end

    -- 帧更新
    local function onPreTick(deltaTime)
        for _, v in ipairs(G.tickables) do
            v:update(deltaTime)
        end
    end

    local function onPostTick() end

    LuaAPI.set_tick_handler(onPreTick, onPostTick)
end)
```

### 使用示例
```lua
local Monster = class("Monster")

function Monster:ctor()
    self.isActive = true
    G.addTickable(self)  -- 注册帧更新
end

function Monster:update(dt)
    if not self.isActive then return end
    -- 更新逻辑
end

function Monster:destroy()
    self.isActive = false
    G.removeTickable(self)  -- 取消帧更新
end
```

## 对象池模式

复用对象避免频繁创建/销毁。

```lua
local class = require("Utils.ClassUtils").class

---@class PrefabFactory
local PrefabFactory = class("PrefabFactory")

function PrefabFactory:ctor()
    self.pools = {}  -- { prefabID -> { instances } }
end

function PrefabFactory:get(prefabID, pos, rot)
    local pool = self.pools[prefabID]
    
    if pool and #pool > 0 then
        -- 从池中取出
        local instance = table.remove(pool)
        instance.set_position(pos)
        instance.set_rotation(rot)
        instance.set_visible(true)
        return instance
    end
    
    -- 池为空，创建新实例
    return GameAPI.create_obstacle(prefabID, pos, rot)
end

function PrefabFactory:release(instance, prefabID)
    instance.set_visible(false)
    -- 移到安全位置
    instance.set_position(math.Vector3(0, -100, 0))
    
    local pool = self.pools[prefabID]
    if not pool then
        pool = {}
        self.pools[prefabID] = pool
    end
    table.insert(pool, instance)
end

function PrefabFactory:preload(prefabID, count)
    for i = 1, count do
        local instance = GameAPI.create_obstacle(prefabID, math.Vector3(0, -100, 0))
        self:release(instance, prefabID)
    end
end

return PrefabFactory
```

## 分帧加载器

避免一帧内创建大量对象导致卡顿。

```lua
local class = require("Utils.ClassUtils").class
local Deque = require("Utils.Deque")

---@class FrameLoader
local FrameLoader = class("FrameLoader")

function FrameLoader:ctor(maxPerFrame, frameInterval)
    self.tasks = Deque.new()
    self.maxPerFrame = maxPerFrame or 1
    self.frameInterval = frameInterval or 1
    self.frameCount = 0
end

function FrameLoader:addTask(task)
    self.tasks:pushRight(task)
end

function FrameLoader:update()
    self.frameCount = self.frameCount + 1
    if self.frameCount % self.frameInterval ~= 0 then
        return
    end

    local processed = 0
    while processed < self.maxPerFrame and not self.tasks:isEmpty() do
        local task = self.tasks:popLeft()
        task()  -- 执行任务
        processed = processed + 1
    end
end

return FrameLoader
```

### 使用示例
```lua
local frameLoader = FrameLoader.new(3, 1)  -- 每帧最多处理3个任务
G.addTickable(frameLoader)

-- 添加批量创建任务
for i = 1, 100 do
    frameLoader:addTask(function()
        createMonster(i)
    end)
end
```

## 波次刷怪管理器

```lua
local class = require("Utils.ClassUtils").class

---@class SpawnWave
local SpawnWave = class("SpawnWave")

function SpawnWave:ctor(waveData, onComplete)
    self.monsters = {}  -- 待刷怪物池
    self.spawnedMonsters = {}  -- 已刷出的怪物
    self.onComplete = onComplete
    self.timerId = nil
    
    -- 初始化待刷怪物
    for _, spawnData in ipairs(waveData.monsters) do
        for i = 1, spawnData.count do
            table.insert(self.monsters, spawnData)
        end
    end
end

function SpawnWave:start(interval)
    self.timerId = LuaAPI.global_register_trigger_event(
        { EVENT.REPEAT_TIMEOUT, interval },
        function() self:spawnOne() end
    )
end

function SpawnWave:spawnOne()
    if #self.monsters == 0 then return end
    
    local spawnData = table.remove(self.monsters, 1)
    local pos = self:randomPosition()
    local monster = GameAPI.create_creature(spawnData.prefabID, pos)
    
    -- 监听死亡
    LuaAPI.unit_register_trigger_event(monster, { EVENT.ON_DEAD }, function()
        self:onMonsterDead(monster)
    end)
    
    table.insert(self.spawnedMonsters, monster)
end

function SpawnWave:onMonsterDead(monster)
    for i, m in ipairs(self.spawnedMonsters) do
        if m == monster then
            table.remove(self.spawnedMonsters, i)
            break
        end
    end
    
    -- 检查是否波次完成
    if #self.monsters == 0 and #self.spawnedMonsters == 0 then
        self:complete()
    end
end

function SpawnWave:complete()
    if self.timerId then
        LuaAPI.global_unregister_trigger_event(self.timerId)
    end
    if self.onComplete then
        self.onComplete()
    end
end

function SpawnWave:randomPosition()
    -- 在范围内随机位置
    local x = LuaAPI.rand() * 20 - 10
    local z = LuaAPI.rand() * 20 - 10
    return math.Vector3(x, 0, z)
end

return SpawnWave
```

## 玩家/英雄管理器

```lua
local class = require("Utils.ClassUtils").class

---@class HeroManager
local HeroManager = class("HeroManager")

function HeroManager:ctor()
    self.heroes = {}  -- roleId -> Hero
end

function HeroManager:initAllPlayers()
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        local roleId = role.get_role_id()
        self.heroes[roleId] = Hero.new(roleId)
    end
end

function HeroManager:getHero(roleId)
    return self.heroes[roleId]
end

function HeroManager:getHeroByUnit(unit)
    if unit.get_role_id then
        return self.heroes[unit.get_role_id()]
    end
    return nil
end

function HeroManager:forEachHero(callback)
    for roleId, hero in pairs(self.heroes) do
        callback(hero, roleId)
    end
end

return HeroManager
```

## 双端队列工具

用于任务队列、消息缓冲等。

```lua
local Deque = {}
Deque.__index = Deque

function Deque.new()
    return setmetatable({ first = 0, last = -1 }, Deque)
end

function Deque:pushLeft(value)
    self.first = self.first - 1
    self[self.first] = value
end

function Deque:pushRight(value)
    self.last = self.last + 1
    self[self.last] = value
end

function Deque:popLeft()
    if self:isEmpty() then return nil end
    local value = self[self.first]
    self[self.first] = nil
    self.first = self.first + 1
    return value
end

function Deque:popRight()
    if self:isEmpty() then return nil end
    local value = self[self.last]
    self[self.last] = nil
    self.last = self.last - 1
    return value
end

function Deque:isEmpty()
    return self.first > self.last
end

function Deque:size()
    return self.last - self.first + 1
end

return Deque
```
