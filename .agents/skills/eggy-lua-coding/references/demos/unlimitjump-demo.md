# 无尽跳跃/成就系统Demo

展示场景边界设置、成就系统、游戏结束存档保存的实现模式。

## 核心概念

### 场景边界
- 设置生命实体和单位的活动范围
- 超出边界的单位会被系统自动处理
- 用于大地图性能优化和防止玩家走出游戏区域

### 成就系统
- 使用 `get_achievement_progress` 查询玩家成就进度
- 使用 `set_achievement_progress` 更新成就完成度
- 成就ID需在编辑器中预先配置

### 游戏生命周期
- `EVENT.GAME_INIT`: 游戏初始化（设置场景、创建管理器）
- `EVENT.GAME_END`: 游戏结束（保存存档）

## main.lua 完整示例

```lua
local StepManager = require("StepManager")
local AchievementManager = require("AchievementManager")
local RoleManager = require("RoleManager")

--- 唯一全局变量
G = {}

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    -- 设置场景边界（重要：防止单位跑出地图）
    local boundaryHorizontal = 1000.0  -- X/Z方向边界
    local boundaryVertical = 1000.0    -- Y方向边界（高度）
    GameAPI.set_life_entity_survival_scene_boundary(
        boundaryHorizontal, boundaryVertical, boundaryHorizontal
    )
    GameAPI.set_unit_survival_scene_boundary(
        boundaryHorizontal, boundaryVertical, boundaryHorizontal
    )
    
    -- 初始化各个管理器
    G.stepManager = StepManager.new()
    G.achievementManager = AchievementManager.new()
    G.roleManager = RoleManager.new()

    -- 注册可更新的对象
    G.tickables = {
        G.stepManager,
        G.roleManager,
    }

    -- 每帧更新
    local function onPreTick()
        for _, v in ipairs(G.tickables) do
            v:update()
        end
    end

    LuaAPI.set_tick_handler(onPreTick, nil)
end)

-- 游戏结束时保存存档
LuaAPI.global_register_trigger_event({ EVENT.GAME_END }, function()
    G.roleManager:savePlayArchive()
end)
```

## 成就管理器

```lua
local class = require("Utils.ClassUtils").class
local AchvData = require("Data.AchievementData")

---@class AchievementManager 成就管理
local AchievementManager = class("AchievementManager")

-- 成就配置：{ 触发条件数值, 成就名称 }
local STEP_ACHVS = {
    { 20, "爬塔至第20层" },
    { 50, "爬塔至第50层" },
    { 100, "爬塔至第100层" },
    { 200, "爬塔至第200层" },
}

function AchievementManager:ctor()
    -- 记录所有玩家未完成的成就
    self._char2StepAchvs = {}
    
    -- 遍历所有玩家，初始化成就状态
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        local achvs = {}
        self._char2StepAchvs[role.get_roleid()] = achvs
        
        for _, value in ipairs(STEP_ACHVS) do
            local achvInfo = AchvData[value[2]]
            
            -- 检查成就是否已完成
            if role.get_achievement_progress(achvInfo.id) < achvInfo.count then
                -- 未完成，添加到待检查列表
                table.insert(achvs, { value[1], value[2], false })
            end
        end
    end
end

-- 检测台阶数是否触发成就
function AchievementManager:checkStepAchv(role, stepCount)
    -- 快速过滤
    if stepCount < STEP_ACHVS[1][1] or stepCount > STEP_ACHVS[#STEP_ACHVS][1] then
        return
    end
    
    local achvs = self._char2StepAchvs[role.get_roleid()]
    if achvs == nil then
        return
    end
    
    -- 检查并更新成就
    for _, value in ipairs(achvs) do
        if stepCount >= value[1] and not value[3] then
            self:updateRolesAchv(role.get_roleid(), AchvData[value[2]].id, 1)
            value[3] = true  -- 标记为已完成
        end
    end
end

-- 更新成就进度
function AchievementManager:updateRolesAchv(roleId, achvId, count)
    local role = GameAPI.get_role(roleId)
    role.set_achievement_progress(achvId, count)
end

return AchievementManager
```

## 成就配置文件 (Data/AchievementData.lua)

```lua
-- 成就数据：名称 -> { id = 编辑器中配置的成就ID, count = 完成所需次数 }
local AchievementData = {
    ["爬塔至第20层"] = { id = 1001, count = 1 },
    ["爬塔至第50层"] = { id = 1002, count = 1 },
    ["爬塔至第100层"] = { id = 1003, count = 1 },
    ["爬塔至第200层"] = { id = 1004, count = 1 },
}
return AchievementData
```

## 关键API

### 场景边界
```lua
-- 设置生命实体活动边界
-- 参数: X方向半径, Y方向高度, Z方向半径
GameAPI.set_life_entity_survival_scene_boundary(xBound, yBound, zBound)

-- 设置普通单位活动边界
GameAPI.set_unit_survival_scene_boundary(xBound, yBound, zBound)
```

### 成就系统
```lua
-- 获取玩家成就进度
local progress = role.get_achievement_progress(achievementId)

-- 设置玩家成就进度
role.set_achievement_progress(achievementId, progressCount)
```

### 玩家查询
```lua
-- 获取所有有效玩家列表
local roles = GameAPI.get_all_valid_roles()

-- 遍历玩家
for _, role in ipairs(roles) do
    local roleId = role.get_roleid()
    -- ...
end

-- 根据ID获取玩家
local role = GameAPI.get_role(roleId)
```

### 游戏事件
```lua
-- 游戏初始化
LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    -- 初始化逻辑
end)

-- 游戏结束
LuaAPI.global_register_trigger_event({ EVENT.GAME_END }, function()
    -- 保存存档等清理逻辑
end)
```

## 设计模式

### Tickable 模式
将需要每帧更新的管理器统一注册到 tickables 列表：
```lua
G.tickables = { manager1, manager2, manager3 }

LuaAPI.set_tick_handler(function()
    for _, v in ipairs(G.tickables) do
        v:update()
    end
end, nil)
```

### 成就检查优化
- 只在数值变化时检查成就（不要每帧检查）
- 使用快速过滤跳过不可能触发的检查
- 标记已完成成就避免重复处理
