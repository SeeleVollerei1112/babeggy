# 开放世界/动态地块Demo

展示动态地块加载卸载和对象池回收模式，适用于无限地图或大世界玩法。

## 核心概念

### 动态加载策略
- **加载半径**: 玩家周围N格内的地块保持加载
- **卸载半径**: 超出M格的地块才卸载（M > N，避免频繁加载卸载）
- **对象池**: 卸载的地块不销毁，而是隐藏并回收，下次加载时复用

### 棋盘格布局
使用奇偶坐标判断地块类型，实现交替纹理效果：
```lua
local isType1 = (gridX + gridZ) % 2 == 0
```

## 完整实现

```lua
local UINodes = require("Data.UINodes")

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    -- 地块管理表
    local usedTiles = {}                          -- 当前使用中的地块
    local freeTiles = { tile1 = {}, tile2 = {} }  -- 回收池（按类型分开）
    
    -- 获取模板地块
    local tileUnit1 = LuaAPI.query_unit("地块1")
    local tileUnit2 = LuaAPI.query_unit("地块2")
    local tilePrefabId1 = tileUnit1.get_key()
    local tilePrefabId2 = tileUnit2.get_key()
    local groundSize = math.Vector3(4, 1, 4)      -- 地块尺寸
    
    -- 加载卸载半径配置
    local LOAD_RADIUS = 1      -- 加载周围1格（3x3范围）
    local UNLOAD_RADIUS = 3    -- 超出3格才卸载（7x7范围）
    
    -- 坐标转唯一键
    local function getKey(x, z)
        return (math.tointeger(x) + 4096) * 65536 + math.tointeger(z) + 4096
    end
    
    -- 初始地块注册
    usedTiles[getKey(0, 0)] = tileUnit1
    usedTiles[getKey(4, 0)] = tileUnit2
    
    -- 核心更新函数
    local function updateTiles()
        local allRoles = GameAPI.get_all_valid_roles()
        local inLoadRangeTiles = {}     -- 需要加载的地块
        local inUnloadRangeTiles = {}   -- 保护范围内的地块
        
        -- 遍历所有玩家，收集需要的地块
        for _, role in ipairs(allRoles) do
            local character = role.get_ctrl_unit()
            local position = character.get_position()
            
            -- 计算玩家所在格子坐标
            local gridX = math.tointeger(math.floor((position.x + groundSize.x * 0.5) / groundSize.x))
            local gridZ = math.tointeger(math.floor((position.z + groundSize.z * 0.5) / groundSize.z))
            
            -- 记录加载范围内的地块
            for i = gridX - LOAD_RADIUS, gridX + LOAD_RADIUS do
                for j = gridZ - LOAD_RADIUS, gridZ + LOAD_RADIUS do
                    local posX = i * groundSize.x
                    local posZ = j * groundSize.z
                    inLoadRangeTiles[getKey(posX, posZ)] = true
                end
            end
            
            -- 记录卸载保护范围
            for i = gridX - UNLOAD_RADIUS, gridX + UNLOAD_RADIUS do
                for j = gridZ - UNLOAD_RADIUS, gridZ + UNLOAD_RADIUS do
                    local posX = i * groundSize.x
                    local posZ = j * groundSize.z
                    inUnloadRangeTiles[getKey(posX, posZ)] = true
                end
            end
        end
        
        -- 加载新地块
        for gridKey in pairs(inLoadRangeTiles) do
            if not usedTiles[gridKey] then
                -- 从键值还原坐标
                local posX = math.floor(gridKey / 65536) - 4096
                local posZ = gridKey % 65536 - 4096
                
                -- 棋盘格判断类型
                local gridX = math.floor(posX / groundSize.x)
                local gridZ = math.floor(posZ / groundSize.z)
                local isType1 = (gridX + gridZ) % 2 == 0
                
                local freeList = isType1 and freeTiles.tile1 or freeTiles.tile2
                local prefabId = isType1 and tilePrefabId1 or tilePrefabId2
                local model = isType1 and tileUnit1 or tileUnit2
                
                -- 优先从回收池取
                local unit = table.remove(freeList)
                if unit then
                    -- 复用：设置位置并显示
                    unit.set_position(math.Vector3(posX, 0.0, posZ))
                    unit.set_model_visible(true)
                    unit.set_physics_active(true)
                else
                    -- 创建新地块
                    unit = GameAPI.create_obstacle(
                        prefabId,
                        math.Vector3(posX, 0.0, posZ),
                        math.Quaternion(0, 0, 0),
                        model.get_scale()
                    )
                end
                usedTiles[gridKey] = unit
            end
        end
        
        -- 卸载超出范围的地块
        for gridKey, unit in pairs(usedTiles) do
            if not inUnloadRangeTiles[gridKey] then
                -- 隐藏而非销毁
                unit.set_model_visible(false)
                unit.set_physics_active(false)
                
                -- 放入对应类型的回收池
                local unitId = unit.get_key()
                if unitId == tilePrefabId1 then
                    table.insert(freeTiles.tile1, unit)
                else
                    table.insert(freeTiles.tile2, unit)
                end
                
                usedTiles[gridKey] = nil
            end
        end
    end
    
    LuaAPI.set_tick_handler(function()
        updateTiles()
    end, nil)
end)
```

## 关键API

### 单位可见性/物理控制
```lua
-- 隐藏/显示模型（不销毁）
unit.set_model_visible(false)
unit.set_model_visible(true)

-- 禁用/启用物理碰撞
unit.set_physics_active(false)
unit.set_physics_active(true)

-- 设置位置
unit.set_position(math.Vector3(x, y, z))
```

### 单位查询和创建
```lua
-- 查询场景中的命名单位
local unit = LuaAPI.query_unit("单位名称")

-- 获取单位的预设ID
local prefabId = unit.get_key()

-- 创建障碍物
GameAPI.create_obstacle(prefabId, position, rotation, scale)
```

## 优化要点

1. **双半径策略**: 加载半径小于卸载半径，避免边界抖动导致频繁加载卸载
2. **分类对象池**: 不同类型的地块分开存储，确保复用时类型匹配
3. **批量处理**: 先收集所有需要的地块，再统一处理，避免遍历中修改
4. **隐藏代替销毁**: `set_model_visible(false)` + `set_physics_active(false)` 比销毁重建更高效
