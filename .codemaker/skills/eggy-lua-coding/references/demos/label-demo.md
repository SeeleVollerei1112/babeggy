# 存档/称号/3D UI Demo

展示存档系统、称号系统、3D场景UI绑定单位的完整实现。

## 核心概念

### 存档系统
- 使用 `role.get_archive_by_type` / `role.set_archive_by_type` 读写玩家存档
- 存档可跨游戏会话持久化
- 支持多种数据类型（Int, Bool, String等）

### 3D场景UI
- 将UI面板绑定到单位头顶（如血条、称号）
- 使用 `create_scene_ui_bind_unit` 创建
- 可控制每个玩家看到的可见性

## 存档系统

### 存档配置 (Data/ArchivesData.lua)
```lua
local ArchivesData = {
    ["潮流大师"] = { id = 1001, vType = Enums.ValueType.Bool },
    ["盲盒收藏家"] = { id = 1002, vType = Enums.ValueType.Bool },
    ["金牌蛋"] = { id = 1003, vType = Enums.ValueType.Bool },
    ["佩戴称号key"] = { id = 2001, vType = Enums.ValueType.Int },
}
return ArchivesData
```

### 存档读写
```lua
local ArchivesData = require("Data.ArchivesData")

-- 读取存档值
local function getArchiveValue(role, key)
    local archiveInfo = ArchivesData[key]
    return role.get_archive_by_type(archiveInfo.vType, archiveInfo.id)
end

-- 写入存档值
local function setArchiveValue(role, key, value)
    local archiveInfo = ArchivesData[key]
    role.set_archive_by_type(archiveInfo.vType, archiveInfo.id, value)
end

-- 使用示例
local owned = getArchiveValue(role, "潮流大师")  -- 读取布尔值
setArchiveValue(role, "佩戴称号key", 1001)        -- 写入整数值
```

## 3D场景UI绑定

### 创建绑定到单位的UI
```lua
local PrefabData = require("Data.Prefab")

-- 为角色创建头顶UI
local designation3DLayer = character.create_scene_ui_bind_unit(
    PrefabData.layout["3D称号界面"],  -- UI布局预设ID
    Enums.ModelSocket.socket_head,     -- 绑定点（头部）
    math.Vector3(0, 3, 0),             -- 偏移量
    -1.0,                               -- 缩放（-1表示使用默认）
    true,                               -- 是否面向摄像机
    true                                -- 是否随距离缩放
)
```

### 控制3D UI可见性（按玩家）
```lua
-- 设置某个玩家能否看到这个3D UI
GameAPI.set_scene_ui_visible(layer, role, visible)

-- 示例：根据距离显示/隐藏
local function update3DUILayerState()
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        local rolePos = role.get_ctrl_unit().get_position()
        
        for _, otherRole in ipairs(GameAPI.get_all_valid_roles()) do
            if role ~= otherRole then
                local otherPos = otherRole.get_ctrl_unit().get_position()
                local distance = (rolePos - otherPos):length()
                
                -- 距离小于10时显示称号
                local visible = distance < 10
                GameAPI.set_scene_ui_visible(
                    allRoleStatus[otherRole.get_roleid()].designation3DLayer,
                    role,
                    visible
                )
            end
        end
    end
end
```

### 操作3D UI中的节点
```lua
-- 获取3D UI中的节点引用
local iconNode = GameAPI.get_eui_node_at_scene_ui(layer, UINodes["3D称号背景"])
local nameNode = GameAPI.get_eui_node_at_scene_ui(layer, UINodes["3D称号文字"])

-- 对节点设置内容（需要指定观看者role）
for _, role in ipairs(GameAPI.get_all_valid_roles()) do
    role.set_image_texture_by_key_with_auto_resize(iconNode, imageKey, false)
    role.set_label_text(nameNode, "称号名称")
end
```

## 完整称号系统示例

```lua
local allRoleStatus = {}  -- 存储每个角色的状态

LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        -- 创建角色状态记录
        allRoleStatus[role.get_roleid()] = {
            selDesignationKey = "潮流大师",
            wearDesignationKey = designationIdToKey(getArchiveValue(role, "佩戴称号key")),
            designation3DLayer = role.get_ctrl_unit().create_scene_ui_bind_unit(
                PrefabData.layout["3D称号界面"],
                Enums.ModelSocket.socket_head,
                math.Vector3(0, 3, 0),
                -1.0, true, true
            ),
        }
        
        initDesignationUI(role)
    end
    
    -- 注册佩戴按钮事件
    LuaAPI.global_register_custom_event("UI_CLICK_DESIGNATION_WEAR", function(_, _, data)
        local roleStatus = allRoleStatus[data.role.get_roleid()]
        local designationKey = roleStatus.selDesignationKey
        
        local owned = getArchiveValue(data.role, designationKey)
        if owned then
            -- 保存到存档
            setArchiveValue(data.role, "佩戴称号key", DesignationData[designationKey].id)
            roleStatus.wearDesignationKey = designationKey
            
            -- 更新UI
            updateDesignationLayer(data.role, designationKey)
            data.role.show_tips("已佩戴")
        else
            data.role.show_tips("未获取")
        end
    end)
    
    -- 每帧更新3D UI可见性
    LuaAPI.set_tick_handler(function()
        update3DUILayerState()
    end, nil)
end)
```

## 关键API

### 存档系统
```lua
-- 读取存档
role.get_archive_by_type(Enums.ValueType.Bool, archiveId)
role.get_archive_by_type(Enums.ValueType.Int, archiveId)

-- 写入存档
role.set_archive_by_type(Enums.ValueType.Bool, archiveId, value)
role.set_archive_by_type(Enums.ValueType.Int, archiveId, value)
```

### 3D场景UI
```lua
-- 创建绑定到单位的UI
unit.create_scene_ui_bind_unit(layoutPrefabId, socket, offset, scale, billboard, scaleByDist)

-- 获取UI中的节点
GameAPI.get_eui_node_at_scene_ui(layer, nodeId)

-- 设置可见性（按观看者）
GameAPI.set_scene_ui_visible(layer, role, visible)
```

### 图片设置
```lua
-- 设置图片并自动调整大小
role.set_image_texture_by_key_with_auto_resize(nodeId, imageKey, keepAspect)

-- 设置标签颜色
role.set_label_color(nodeId, colorHex, alpha)
```

### 生物查询
```lua
-- 获取AABB范围内的所有生物
local creatures = GameAPI.get_creatures_in_aabb(center, halfX, halfY, halfZ)
```
