# EUI API 速查表

## 全局对象（无需 require）

| 对象 | 说明 |
|------|------|
| `GameAPI` | 游戏核心 API（创建节点等） |
| `LuaAPI` | Lua 扩展 API（事件注册等） |
| `EVENT` | 事件类型常量 |
| `math` | 数学库（含 `math.tofixed`） |

> ⚠️ **`Role` 不是全局变量！** 必须从事件回调的 `data.role` 参数获取 Role 实例后，才能调用 `role.set_node_visible()`、`role.set_label_text()` 等方法。
> ```lua
> -- ✅ 正确：从事件回调中获取 role
> LuaAPI.global_register_trigger_event(
>     {EVENT.EUI_NODE_TOUCH_EVENT, btn, 1},
>     function(event_name, actor, data)
>         local role = data.role
>         role.set_label_text(label, "新文本")
>     end
> )
>
> -- ❌ 错误：Role 不是全局变量，直接调用会报 nil
> Role.set_label_text(label, "新文本")
> ```

## 创建节点

```lua
-- 创建图片节点
GameAPI.create_eui_image_at_position(
    preset_id,  -- 图片预设ID（使用 -1 表示透明/无图片）
    parent,     -- 父节点 (ECanvas/ENode)
    x, y,       -- 位置 (Fix32)
    width, height,  -- 尺寸 (Fix32)
    name        -- 节点名称
) -> EImage

-- 创建按钮节点
GameAPI.create_eui_button_at_position(
    preset_id,  -- 按钮预设ID
    parent,
    x, y,
    width, height,
    name
) -> ENode

-- 创建文本节点
GameAPI.create_eui_label_at_position(
    preset_id,  -- 文本预设ID
    parent,
    x, y,
    width, height,
    name,
    text        -- 初始文本
) -> ENode

-- 创建输入框节点
GameAPI.create_eui_input_at_position(
    preset_id,  -- 输入框预设ID
    parent,
    x, y,
    width, height,
    name,
    default_text -- 默认文本
) -> ENode

-- 创建条形进度条节点
GameAPI.create_eui_progress_at_position(
    preset_id,  -- 条形进度条预设ID
    parent,
    x, y,
    width, height,
    name
) -> ENode

-- 创建环形进度条节点
GameAPI.create_eui_progresstimer_at_position(
    preset_id,  -- 环形进度条预设ID
    parent,
    x, y,
    width, height,
    name
) -> ENode

-- 创建动效节点
GameAPI.create_eui_effect_at_position(
    preset_id,  -- 动效预设ID
    parent,
    x, y,
    width, height,
    is_loop,    -- 是否循环播放 (Bool)
    name
) -> EEffectNode

-- 创建物品格控件
GameAPI.create_eui_bagslot_at_position(
    parent,
    x, y,
    width, height,
    preset_id,  -- 物品格样式预设ID
    name
) -> EBagSlot

-- 创建技能控件
GameAPI.create_eui_ability_at_position(
    preset_id,      -- 技能预设ID
    parent,
    x, y,
    width, height,
    show_unlinked,  -- 未关联技能时是否显示 (Bool)
    show_name,      -- 是否显示技能名称 (Bool)
    name
) -> EButton

-- 创建效果控件
GameAPI.create_eui_buff_at_position(
    parent,
    x, y,
    width, height,
    name
) -> EModifierList

-- 创建列表节点
GameAPI.create_eui_listview_at_position(
    parent,
    x, y,
    width, height,
    name
) -> ENode

-- 创建遮罩节点
GameAPI.create_eui_clipping_at_position(
    parent,
    x, y,
    width, height,
    name,
    mask_image  -- 蒙版图片预设ID
) -> ENode

```

## 预设 Key 类型参考

创建节点时的预设参数均为整数编号，对应不同控件的样式预设。以下列出各预设 Key 的 Lua 类型名及数据来源：

| Lua 类型名 | 对应控件 | 数据来源表 | 说明 |
|-----------|---------|-----------|------|
| `ImageKey` | 图片 | `ui_editor_img_style` | 包含自定义图片，支持分类文件夹 |
| `BtnStyleKey` | 按钮 | `ui_editor_btn_style` | 按钮外观样式 |
| `LabelStyleKey` | 文本 | `ui_editor_text_style` (Type=12001) | 文本控件样式 |
| `InputStyleKey` | 输入框 | `ui_editor_text_style` (Type=12002/12005) | 输入框控件样式 |
| `ProgressBarStyleKey` | 条形进度条 | `ui_editor_progress_bar_style` (Type=ProgressBar/ProgressBarNew) | 条形进度条样式 |
| `ProgressTimerStyleKey` | 环形进度条 | `ui_editor_progress_bar_style` (Type=ProgressTimer) | 环形进度条样式 |
| `AnimationStyleKey` | 动效 | `ui_editor_animation_node_style` | 动效节点样式 |
| `BagSlotStyleKey` | 物品格 | `ui_editor_logic_node_style` (Type=BagSlot) | 物品格控件样式 |
| `AbilityStyleKey` | 技能 | `ui_editor_logic_node_style` (Type=AbilitySlot) | 技能控件样式 |

> **注意**：预设编号的值来自上述配置表中 `IsOpen=True` 的条目，不是固定常量。在 Lua 蛋码中通过触发器编辑器的下拉列表选择，运行时传入的是整数 ID。
> 遮罩节点的 `mask_image` 参数复用 `ImageKey` 类型。
> 效果控件（Buff）、列表节点、遮罩节点无预设参数。

## 节点操作

```lua
-- 获取子节点
GameAPI.get_eui_child_by_name(node, name) -> ENode
GameAPI.get_eui_child_by_index(node, index) -> ENode
GameAPI.get_eui_children(node) -> ENode[]
```

## 属性设置（通过 Role 实例调用）

> Role 实例必须从事件回调的 `data.role` 获取，不是全局变量。

```lua
-- 从事件回调获取 role 实例后调用：
local role = data.role

-- 可见性
role.set_node_visible(node, visible)

-- 文本
role.set_label_text(label, text)
role.set_button_text(button, text)
```

## 事件注册

```lua
-- 触摸事件类型
local TOUCH_CLICK = 1
local TOUCH_DOWN = 2
local TOUCH_UP = 3

-- 注册节点触摸事件
LuaAPI.global_register_trigger_event(
    {EVENT.EUI_NODE_TOUCH_EVENT, node, TOUCH_CLICK},
    function(event_name, actor, data)
        -- 处理点击
    end
)

-- 游戏初始化事件
LuaAPI.global_register_trigger_event({EVENT.GAME_INIT}, function()
    -- 初始化 UI
end)
```

## 类型转换

```lua
-- 所有数值必须使用 math.tofixed 转换
local tf = math.tofixed
local x = tf(100)
local width = tf(200)
```

## 画布获取

```lua
-- 从 UINodes 直接获取画布对象
local UINodes = require("Data.UINodes")
local canvas = UINodes["画布0"]  -- 直接是 ECanvas 对象
```

## 常用布局计算

```lua
local tf = math.tofixed

-- 屏幕中心
local centerX = tf(960)
local centerY = tf(540)

-- 网格布局
local startX = tf(400)
local startY = tf(500)
local gap = tf(20)
local itemSize = tf(80)

for i = 1, 7 do
    local x = startX + tf(i-1) * (gap + itemSize)
    local y = startY
    -- 创建节点...
end
```