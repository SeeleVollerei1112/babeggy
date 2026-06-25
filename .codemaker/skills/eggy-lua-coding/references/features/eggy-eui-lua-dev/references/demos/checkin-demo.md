# 每日签到界面 Demo

一个完整的每日签到 UI 示例，展示帧同步 UI 的标准实现模式。

## 效果预览

- 蛋仔风格弹窗背景
- 7 天签到格子布局
- 可交互的签到按钮
- 进度条显示

## 完整代码

```lua
-- main.lua
local tf = math.tofixed
local UINodes = require("Data.UINodes")

LuaAPI.global_register_trigger_event({EVENT.GAME_INIT}, function()
    local canvas = UINodes["画布0"]

    -- ===== 布局参数 =====
    local centerX = tf(960)
    local centerY = tf(540)

    -- 主弹窗尺寸
    local popupW = tf(740)
    local popupH = tf(290)

    -- 格子参数
    local slotSize = tf(80)
    local slotGap = tf(12)
    local totalSlots = 7

    -- 计算格子起始位置（居中排列）
    local totalWidth = slotSize * tf(totalSlots) + slotGap * tf(totalSlots - 1)
    local startX = centerX - totalWidth / tf(2) + slotSize / tf(2)
    local gridY = centerY + tf(30)

    -- ===== 创建主背景 =====
    local bg = GameAPI.create_eui_image_at_position(
        16347,  -- 蛋仔确认弹窗
        canvas,
        centerX, centerY,
        popupW, popupH,
        "main_bg"
    )

    -- ===== 创建标题 =====
    local title = GameAPI.create_eui_label_at_position(
        canvas,
        centerX, centerY + tf(100),
        tf(300), tf(50),
        "title",
        "每日签到"
    )

    -- ===== 创建 7 天签到格子 =====
    local slots = {}
    local icons = {}

    for i = 1, totalSlots do
        local slotX = startX + tf(i - 1) * (slotGap + slotSize)

        -- 格子背景
        slots[i] = GameAPI.create_eui_image_at_position(
            11084,  -- 圆形物品格底图
            canvas,
            slotX, gridY,
            slotSize, slotSize,
            "slot_" .. i
        )

        -- 奖励图标（使用蛋仔角色头像）
        local iconPresets = {11097, 11098, 11102, 11103, 11104, 11105, 11106}
        icons[i] = GameAPI.create_eui_image_at_position(
            iconPresets[i],  -- 不同蛋仔头像
            canvas,
            slotX, gridY,
            tf(60), tf(60),
            "icon_" .. i
        )

        -- 天数标签
        GameAPI.create_eui_label_at_position(
            canvas,
            slotX, gridY - tf(50),
            tf(60), tf(24),
            "day_" .. i,
            "第" .. i .. "天"
        )
    end

    -- ===== 创建签到按钮 =====
    local btnConfirm = GameAPI.create_eui_button_at_position(
        11001,  -- 金色按钮
        canvas,
        centerX, centerY - tf(80),
        tf(180), tf(70),
        "btn_checkin"
    )
    Role.set_button_text(btnConfirm, "签到")

    -- ===== 创建进度条 =====
    local progressBar = GameAPI.create_eui_progress_bar_at_position(
        30000,  -- 标准进度条
        canvas,
        centerX, centerY - tf(130),
        tf(400), tf(20),
        "progress"
    )
    Role.set_progress_bar_value(progressBar, 0.43)  -- 3/7 = 43%

    -- ===== 注册按钮点击事件 =====
    local TOUCH_CLICK = 1
    LuaAPI.global_register_trigger_event(
        {EVENT.EUI_NODE_TOUCH_EVENT, btnConfirm, TOUCH_CLICK},
        function()
            print("签到按钮被点击!")
            -- TODO: 实现签到逻辑
        end
    )
end)
```

## 关键模式说明

### 1. Fix32 类型转换
所有数值必须通过 `math.tofixed()` 转换：
```lua
local tf = math.tofixed
local x = tf(100)  -- ✅ 正确
-- local x = 100   -- ❌ 错误：int 不是 Fix32
```

### 2. 画布获取
从 `Data.UINodes` 直接获取，不调用任何 API：
```lua
local UINodes = require("Data.UINodes")
local canvas = UINodes["画布0"]  -- 直接就是 ECanvas 对象
```

### 3. 居中布局计算
```lua
local centerX = tf(960)  -- 1920/2
local centerY = tf(540)  -- 1080/2

-- 计算元素组居中
local totalWidth = itemSize * tf(count) + gap * tf(count - 1)
local startX = centerX - totalWidth / tf(2) + itemSize / tf(2)
```

### 4. 循环创建多个元素
```lua
for i = 1, 7 do
    local x = startX + tf(i - 1) * (gap + size)
    GameAPI.create_eui_image_at_position(preset, canvas, x, y, size, size, "item_" .. i)
end
```

### 5. 事件绑定
```lua
local TOUCH_CLICK = 1
LuaAPI.global_register_trigger_event(
    {EVENT.EUI_NODE_TOUCH_EVENT, button, TOUCH_CLICK},
    function()
        -- 处理点击
    end
)
```

## 常用预设 ID

| 用途 | ID | 说明 |
|------|-----|------|
| 弹窗背景 | 16347 | 蛋仔确认弹窗 |
| 格子底图 | 11084 | 圆形物品格 |
| 确认按钮 | 11001 | 金色按钮 |
| 取消按钮 | 11002 | 蓝色按钮 |
| 进度条 | 30000 | 标准水平进度条 |
| 蛋仔头像 | 11097-11196 | 各种蛋仔角色 |
