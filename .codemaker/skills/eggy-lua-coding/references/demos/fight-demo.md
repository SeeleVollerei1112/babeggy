# 战斗/怪物系统Demo

完整的战斗玩法参考，包含怪物AI、波次刷怪、英雄等级系统。

## 项目结构

```
LuaSource_fight/
├── main.lua           # 入口，初始化管理器
├── Monster.lua        # 怪物类，含AI逻辑
├── MonsterManager.lua # 怪物管理器，波次刷怪
├── Hero.lua          # 英雄类，等级经验
├── HeroManager.lua   # 英雄管理器
├── GM.lua            # GM命令
├── Data/
│   ├── MonsterData.lua       # 怪物配置
│   ├── MonsterSpawnWaveData.lua # 波次配置
│   ├── HeroLevelData.lua     # 等级配置
│   ├── ItemData.lua          # 物品配置
│   └── ...
└── Utils/
    ├── ClassUtils.lua
    ├── MathUtils.lua
    ├── FrameLoader.lua
    └── PrefabFactory.lua
```

## 主入口 (main.lua)

```lua
local FrameLoader = require("Utils.FrameLoader")
local PrefabFactory = require("Utils.PrefabFactory")
local MonsterManager = require("MonsterManager")
local HeroManager = require("HeroManager")
local ItemData = require("Data.ItemData")

G = {}

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    -- 初始化角色装备
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        local character = role.get_ctrl_unit()
        character.set_reborn_in_place(true, false)
        
        -- 装备武器
        local sword = GameAPI.create_equipment(ItemData.Sword.prefabID, character.get_position())
        character.swap_equipment_slot(sword, Enums.EquipmentSlotType.EQUIPPED, 1)
    end

    -- 初始化管理器
    G.prefabFactory = PrefabFactory.new()
    G.frameLoader = FrameLoader.new(1, 1)
    G.monsterManager = MonsterManager.new()
    G.heroManager = HeroManager.new()
    
    G.tickables = { G.frameLoader }
    
    function G.addTickable(obj)
        table.insert(G.tickables, obj)
    end
    
    function G.removeTickable(obj)
        for i, v in ipairs(G.tickables) do
            if v == obj then
                table.remove(G.tickables, i)
                break
            end
        end
    end
    
    LuaAPI.set_tick_handler(function()
        for _, v in ipairs(G.tickables) do
            v:update()
        end
    end, function() end)
    
    G.monsterManager:startSpawn()
end)
```

## 怪物类 (Monster.lua)

核心设计：
- 创建时注册AI定时器和死亡事件
- AI逻辑：索敌、移动、攻击
- 支持卡住检测和处理

```lua
local class = require("Utils.ClassUtils").class

---@class Monster
local Monster = class("Monster")

function Monster:ctor(monsterConf, position, rotation, deadCallback)
    self.monsterConf = monsterConf
    self.aiConf = monsterConf.ai
    self.deadDestroyCb = deadCallback
    self.bornPos = position
    self.target = nil
    self.aiEnable = true
    
    -- 异步创建单位
    G.prefabFactory:createPrefabWithCb(
        PrefabType.UNIT_CREATURE,
        monsterConf.prefabID,
        position, rotation, scale,
        function(unit)
            self.unit = unit
            self:onCreatureLoaded()
        end
    )
end

function Monster:onCreatureLoaded()
    G.addTickable(self)
    self.globalTriggerEvents = {}
    
    -- 注册AI定时更新
    table.insert(self.globalTriggerEvents,
        LuaAPI.global_register_trigger_event({ EVENT.REPEAT_TIMEOUT, 0.2 }, function()
            if self.aiEnable then
                self:tickAI()
            end
        end)
    )
    
    -- 注册死亡事件
    self.deadDestroyHandle = LuaAPI.unit_register_trigger_event(
        self.unit,
        { EVENT.SPEC_LIFEENTITY_DIE },
        function(_, _, data)
            if self.deadDestroyCb then
                self.deadDestroyCb(self, data.dmg_unit)
            end
            self:onDeadDestroy()
        end
    )
end

function Monster:tickAI()
    -- 搜索目标
    if not self.target then
        self.target = self:searchClosestTarget()
    end
    
    if self.target then
        self:moveToAttack(self.target)
    else
        self:patrol()
    end
end

function Monster:searchClosestTarget()
    local nearest = nil
    local nearestDist = self.aiConf.searchTargetDist
    local unitPos = self.unit.get_position()
    
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        local target = role.get_ctrl_unit()
        if target.get_hp() > 0 then
            local dist = (target.get_position() - unitPos):length()
            if dist < nearestDist then
                nearest = target
                nearestDist = dist
            end
        end
    end
    return nearest
end

function Monster:moveToAttack(target)
    local unitPos = self.unit.get_position()
    local targetPos = target.get_position()
    local direction = targetPos - unitPos
    local distance = direction:length()
    
    if distance <= self.aiConf.attackDist then
        self.unit.force_stop_move()
        self.unit.cast_ability_by_ability_slot_and_direction(direction, 5, 0.0)
    else
        self.unit.force_start_move(direction, 1.0)
    end
end

function Monster:patrol()
    local direction = self.patrolPos - self.unit.get_position()
    self.unit.force_start_move(direction, 1.0)
end

function Monster:_onDestroy()
    G.removeTickable(self)
    for _, event in ipairs(self.globalTriggerEvents) do
        LuaAPI.global_unregister_trigger_event(event)
    end
    self.unit = nil
end
```

## 英雄类 (Hero.lua)

```lua
local class = require("Utils.ClassUtils").class
local UINodes = require("Data.UINodes")
local LevelData = require("Data.HeroLevelData")

---@class Hero
local Hero = class("Hero")

function Hero:ctor(character)
    self.character = character
    self.level = 1
    self.exp = 0
    self:setLevel(self.level)
end

function Hero:getLevelUpExp()
    return LevelData[self.level + 1].exp
end

function Hero:setLevel(level)
    local levelData = LevelData[level]
    if not levelData then return end
    
    self.level = level
    
    -- 设置属性
    self.character.set_attr_by_type(Enums.ValueType.Fixed, "hp_max", levelData.hpMax)
    self.character.set_attr_ratio_fixed("move_speed", levelData.moveSpd - 1.0)
    
    -- 更新UI
    local role = GameAPI.get_role(self.character.get_role_id())
    role.set_label_text(UINodes["等级"], "当前等级：" .. self.level)
    
    local nextLevelData = LevelData[self.level + 1]
    if nextLevelData then
        role.set_progressbar_max(UINodes["经验值"], nextLevelData.exp)
    end
end

function Hero:addExp(delta)
    self.exp = self.exp + delta
    local nextLevelData = LevelData[self.level + 1]
    
    if nextLevelData and self.exp >= nextLevelData.exp then
        self.exp = self.exp - nextLevelData.exp
        self:setLevel(self.level + 1)
    end
    
    local role = GameAPI.get_role(self.character.get_role_id())
    role.set_progressbar_current(UINodes["经验值"], self.exp)
end
```

## 怪物配置示例 (Data/MonsterData.lua)

```lua
local Prefab = require("Data.Prefab")

local MonsterData = {
    Slime = {
        key = "Slime",
        prefabID = Prefab.Slime,
        scale = 1.0,
        exp = 10,
        ai = {
            searchTargetDist = 15.0,
            targetGiveupDist = 20.0,
            careTargetRange = 25.0,
            attackDist = 2.0,
            attackHeight = 2.0,
            attackCosMin = 0.5,
            patrolRange = 5.0,
            isShoot = false,
        },
    },
    Archer = {
        key = "Archer",
        prefabID = Prefab.Archer,
        scale = 1.0,
        exp = 20,
        ai = {
            searchTargetDist = 20.0,
            targetGiveupDist = 25.0,
            careTargetRange = 30.0,
            attackDist = 15.0,
            attackHeight = 3.0,
            attackCosMin = 0.3,
            patrolRange = 8.0,
            isShoot = true,
            shootScatter = 0.1,
        },
    },
}

return MonsterData
```

## 波次配置示例 (Data/MonsterSpawnWaveData.lua)

```lua
local MonsterData = require("Data.MonsterData")

local MonsterSpawnWaveData = {
    -- 第1波
    {
        spawnInterval = 2.0,
        maxNum = 5,
        maxNumOnce = 2,
        monsters = {
            { data = MonsterData.Slime, count = 10, weight = 1, range = {5, 15} },
        },
    },
    -- 第2波
    {
        spawnInterval = 1.5,
        maxNum = 8,
        maxNumOnce = 3,
        monsters = {
            { data = MonsterData.Slime, count = 15, weight = 2, range = {5, 15} },
            { data = MonsterData.Archer, count = 5, weight = 1, range = {10, 20} },
        },
    },
}

return MonsterSpawnWaveData
```

## 关键API

### 角色属性
```lua
character.get_hp()
character.get_hp_max()
character.change_hp(delta)
character.set_attr_by_type(Enums.ValueType.Fixed, "hp_max", value)
character.set_attr_ratio_fixed("move_speed", ratio)
character.get_kv_by_type(Enums.ValueType.Int, "key")
```

### 生物控制
```lua
creature.force_start_move(direction, duration)
creature.force_stop_move()
creature.jump()
creature.cast_ability_by_ability_slot_and_direction(direction, slot, delay)
```

### 玩家/角色
```lua
GameAPI.get_all_valid_roles()
role.get_ctrl_unit()
role.get_role_id()
GameAPI.get_role(roleId)
```
