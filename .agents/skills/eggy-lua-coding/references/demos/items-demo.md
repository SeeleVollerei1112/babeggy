# 物品/背包/商店系统Demo

完整的物品交易玩法参考，包含背包管理、商店购买、物品出售。

## 项目结构

```
LuaSource_items/
├── main.lua           # 入口，初始化商城事件
├── Shop.lua          # 商店逻辑（购买、进入区域触发）
├── Backpack.lua      # 背包逻辑（添加、丢弃出售）
├── PlayerManager.lua # 玩家数据管理
├── CanvasUI.lua      # UI交互
├── SellHandle.lua    # 出售区域处理
├── Data/
│   ├── ItemData.lua      # 物品配置
│   ├── GoodsData.lua     # 商品（充值）配置
│   └── UINodes.lua       # UI节点映射
```

## 主入口 (main.lua)

```lua
local GoodData = require("Data.GoodsData")
local UINodes = require("Data.UINodes")
local CanvasUI = require("CanvasUI")
local SellHandle = require("SellHandle")
local Shop = require("Shop")
local PlayerManager = require("PlayerManager")

CanvasUI.Init()
SellHandle.Init()
Shop.Init()

-- 游戏开始事件
LuaAPI.global_register_trigger_event({ EVENT.GAME_INIT }, function()
    for _, role in ipairs(GameAPI.get_all_valid_roles()) do
        PlayerManager.InitPlayer(role)
        
        -- 注册购买成功事件（真实付费商品）
        LuaAPI.global_register_trigger_event(
            { EVENT.SPEC_ROLE_PURCHASE_GOODS, role.get_roleid() },
            function(_, _, data)
                if data.goods_id == GoodData.loveGold.goodsId then
                    local playerData = PlayerManager.GetData(role)
                    playerData.gold = playerData.gold + 100
                    CanvasUI.UpdateGoldUI(role, playerData.gold)
                    role.show_tips("购买100金币成功", 2.0)
                end
            end
        )
    end
end)

-- 注册自定义UI事件
LuaAPI.global_register_custom_event("点击爱心金币购买按钮", function(_, _, data)
    local role = data.role
    -- 显示真实付费面板
    role.show_goods_purchase_panel(GoodData.loveGold.goodsId, 10.0)
end)
```

## 商店模块 (Shop.lua)

### 区域触发商店UI

```lua
local Shop = {}

Shop.Init = function()
    local weaponShop = LuaAPI.query_unit("武器商城")
    
    -- 进入区域显示商店UI
    LuaAPI.global_register_trigger_event(
        { EVENT.ANY_LIFEENTITY_TRIGGER_SPACE, Enums.TriggerSpaceEventType.ENTER, weaponShop.get_id() },
        function(name, actor, data)
            local character = data.event_unit
            local role = character.get_role()
            CanvasUI.ShowHideWeaponShop(role, true)
        end
    )
    
    -- 离开区域隐藏商店UI
    LuaAPI.global_register_trigger_event(
        { EVENT.ANY_LIFEENTITY_TRIGGER_SPACE, Enums.TriggerSpaceEventType.LEAVE, weaponShop.get_id() },
        function(name, actor, data)
            local character = data.event_unit
            local role = character.get_role()
            CanvasUI.ShowHideWeaponShop(role, false)
        end
    )
end
```

### 购买物品逻辑

```lua
Shop.BuyItem = function(player, itemId)
    local data = PlayerManager.GetData(player)
    local itemInfo = ItemData[tostring(itemId)]
    
    if data.gold < itemInfo.gold then
        player.show_tips("金币不足", 2.0)
        return
    end
    
    data.gold = data.gold - itemInfo.gold
    CanvasUI.UpdateGoldUI(player, data.gold)
    Backpack.AddItem(player, itemInfo.id)
end

-- 注册购买按钮事件
LuaAPI.global_register_custom_event("Buy_Item", function(_, _, data)
    local role = data.role
    if data.eui_node_id == UINodes["霰弹枪购买"] then
        Shop.BuyItem(role, 1073815620)
    end
end)
```

## 背包模块 (Backpack.lua)

```lua
local Backpack = {}

-- 添加物品到背包
Backpack.AddItem = function(role, itemPrefabId)
    local ch = role.get_ctrl_unit()
    local obj = ch.create_equipment_to_slot(itemPrefabId, Enums.EquipmentSlotType.BACKPACK)
    role.show_tips("添加道具成功", 2.0)
    
    -- 监听丢弃事件（用于出售）
    LuaAPI.unit_register_trigger_event(obj, { EVENT.SPEC_EQUIPMENT_LOST },
        function(event_name, actor, data)
            LuaAPI.call_delay_frame(5, function()
                local playerData = PlayerManager.GetData(role)
                if not playerData.canSell then return end
                
                -- 销毁装备并返还金币
                data.equipment.destroy_equipment()
                
                local itemInfo = ItemData[tostring(itemPrefabId)]
                local sellGold = math.floor(itemInfo.gold * 0.8)
                
                playerData.gold = playerData.gold + sellGold
                CanvasUI.UpdateGoldUI(role, playerData.gold)
                role.show_tips("出售获得" .. sellGold .. "金币", 2.0)
            end)
        end
    )
    
    return obj
end

return Backpack
```

## 玩家数据管理 (PlayerManager.lua)

```lua
local PlayerManager = {}

local playerDataMap = {}

PlayerManager.InitPlayer = function(role)
    playerDataMap[role.get_roleid()] = {
        gold = 100,      -- 初始金币
        canSell = false, -- 是否在可出售区域
    }
end

PlayerManager.GetData = function(role)
    return playerDataMap[role.get_roleid()]
end

return PlayerManager
```

## 物品配置示例 (Data/ItemData.lua)

```lua
local ItemData = {
    ["1073815620"] = {
        id = 1073815620,
        name = "霰弹枪",
        gold = 50,
        type = "weapon",
    },
    ["1073831993"] = {
        id = 1073831993,
        name = "长剑",
        gold = 30,
        type = "weapon",
    },
    ["1073819762"] = {
        id = 1073819762,
        name = "草莓奶昔",
        gold = 10,
        type = "food",
    },
}

return ItemData
```

## 商品配置示例（付费相关）

```lua
local GoodsData = {
    loveGold = {
        goodsId = "goods_love_gold",
        commodityId = "commodity_love_gold",
        price = 1,
    },
    passport = {
        goodsId = "goods_passport",
        commodityId = "commodity_passport",
        price = 10,
    },
}

return GoodsData
```

## 关键API

### 商品/付费系统
```lua
-- 显示付费购买面板
role.show_goods_purchase_panel(goodsId, timeout)
-- 获取商品数量（用于判断是否已购买）
role.get_commodity_count(commodityId)
-- 监听购买成功事件
LuaAPI.global_register_trigger_event({ EVENT.SPEC_ROLE_PURCHASE_GOODS, roleId }, callback)
```

### 装备/物品系统
```lua
-- 创建装备到槽位
character.create_equipment_to_slot(prefabId, Enums.EquipmentSlotType.BACKPACK)
-- 交换装备槽位
character.swap_equipment_slot(equipment, slotType, slotIndex)
-- 销毁装备
equipment.destroy_equipment()
-- 监听装备丢弃
LuaAPI.unit_register_trigger_event(equipment, { EVENT.SPEC_EQUIPMENT_LOST }, callback)
```

### UI相关
```lua
role.show_tips(message, duration)
role.set_label_text(nodeId, text)
role.set_button_text(nodeId, text)
role.set_node_visible(nodeId, visible)
```

### 区域触发
```lua
LuaAPI.query_unit("区域名称")
-- 区域事件类型
Enums.TriggerSpaceEventType.ENTER
Enums.TriggerSpaceEventType.LEAVE
-- 事件数据
data.event_unit  -- 触发的单位
```
