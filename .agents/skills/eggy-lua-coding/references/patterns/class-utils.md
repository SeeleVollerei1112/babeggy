# 类定义模式

## ClassUtils 工具

蛋仔项目中常用的面向对象模式，基于Lua的metatable实现。

### 类定义工具 (Utils/ClassUtils.lua)

```lua
local ClassUtils = {}

function ClassUtils.class(classname, super)
    local superType = type(super)
    assert(super == nil or type(super) == "table", superType)

    local cls
    if super then
        cls = {}
        setmetatable(cls, {__index = super})
        cls.super = super
    else
        cls = {}
    end

    cls.__cname = classname
    cls.__index = cls

    function cls.new(...)
        local instance = setmetatable({}, cls)

        -- 从基类到派生类依次调用构造函数
        local child = cls
        local classes = {cls}
        while child.super do
            table.insert(classes, child.super)
            child = child.super
        end

        for i=#classes,1,-1 do
            local ctor = rawget(classes[i], "ctor")
            if ctor then
                ctor(instance, ...)
            end
        end

        return instance
    end

    return cls
end

return ClassUtils
```

## 使用示例

### 基础类定义

```lua
local class = require("Utils.ClassUtils").class

---@class Monster
---@field new fun(data, pos, rot): Monster
local Monster = class("Monster")

function Monster:ctor(data, pos, rot)
    self.data = data
    self.position = pos
    self.rotation = rot
    self.hp = data.maxHp
end

function Monster:takeDamage(amount)
    self.hp = self.hp - amount
    if self.hp <= 0 then
        self:die()
    end
end

function Monster:die()
    -- 死亡逻辑
end

return Monster
```

### 继承

```lua
local class = require("Utils.ClassUtils").class
local Monster = require("Monster")

---@class Boss: Monster
local Boss = class("Boss", Monster)

function Boss:ctor(data, pos, rot)
    -- 父类ctor自动调用
    self.phase = 1
    self.enraged = false
end

function Boss:takeDamage(amount)
    -- 可以覆盖父类方法
    Monster.takeDamage(self, amount)  -- 调用父类方法
    
    if self.hp < self.data.maxHp * 0.5 and not self.enraged then
        self:enrage()
    end
end

function Boss:enrage()
    self.enraged = true
    self.attackPower = self.attackPower * 2
end

return Boss
```

### 管理器类

```lua
local class = require("Utils.ClassUtils").class

---@class MonsterManager
---@field new fun(): MonsterManager
local MonsterManager = class("MonsterManager")

function MonsterManager:ctor()
    self.monsters = {}
    self.deadCount = 0
end

function MonsterManager:createMonster(key, pos, rot)
    local data = MonsterData[key]
    local monster = Monster.new(data, pos, rot)
    table.insert(self.monsters, monster)
    return monster
end

function MonsterManager:removeMonster(monster)
    for i, m in ipairs(self.monsters) do
        if m == monster then
            table.remove(self.monsters, i)
            self.deadCount = self.deadCount + 1
            break
        end
    end
end

function MonsterManager:update()
    for _, monster in ipairs(self.monsters) do
        monster:update()
    end
end

return MonsterManager
```

### 使用类

```lua
local MonsterManager = require("MonsterManager")
local Monster = require("Monster")

-- 创建实例
local manager = MonsterManager.new()

-- 创建怪物
local monster = manager:createMonster("slime", pos, rot)

-- 调用方法
monster:takeDamage(10)
```

## LuaDoc 注解

使用 `---@class` 和 `---@field new` 注解可以获得IDE代码提示：

```lua
---@class Hero
---@field new fun(roleId: integer): Hero
---@field roleId integer
---@field level integer
---@field exp integer
local Hero = class("Hero")
```
