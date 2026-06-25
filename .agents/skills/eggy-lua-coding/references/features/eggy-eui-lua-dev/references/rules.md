# 蛋仔派对帧同步（FS）编辑器（Eggitor）UI (EUI) 开发规则 - 核心规范与强制要求

## 帧同步UI (EUI) 开发规范

> **说明**：本规则文件定义**必须遵守的核心规范**。详细的坐标系统、屏幕适配、UI交互等进阶内容请参考 `eggy-eui-dev` skill。

编写帧同步UI代码时**必须遵守**以下规则：

---

### 1. 参数类型规范 (核心要求!)

帧同步要求所有客户端计算结果一致，**必须严格按照 EggyAPI.lua 中的参数类型传递数据**：

#### 1.1 Fix32 定点数类型

**当 EggyAPI.lua 中参数类型标注为 `Fixed` 时**，必须使用 `math.tofixed()` 转换：

```lua
local tf = math.tofixed  -- 推荐简写

-- ✅ 正确：坐标、尺寸参数为 Fixed 类型
GameAPI.create_eui_image_at_position(10000, canvas, tf(0), tf(0), tf(100), tf(50), "img")

-- ❌ 错误：直接传整数会报 type mismatch
GameAPI.create_eui_image_at_position(10000, canvas, 0, 0, 100, 50, "img")
```

#### 1.2 Integer 整数类型

**当 EggyAPI.lua 中参数类型标注为 `Int` 或 `Integer` 时**，直接传整数，**不需要**转换为 Fix32：

```lua
-- ✅ 正确：预设ID为 Integer 类型，直接传整数
local presetId = 10000  -- Integer 类型
GameAPI.create_eui_image_at_position(presetId, canvas, tf(0), tf(0), tf(100), tf(50), "img")

-- ✅ 正确：不透明度为 Integer (0-255)
role.set_ui_opacity(node, 128)  -- Integer 类型

-- ❌ 错误：不要对 Integer 类型使用 tofixed
role.set_ui_opacity(node, tf(128))  -- 错误！
```

**⚠️ 重要：数学运算结果的类型陷阱**

在 Eggy 环境中，涉及 Fix32 类型的数学运算结果也是 Fix32 类型。当需要传递 Integer 参数时，**必须使用 `math.tointeger()` 显式转换为整数**：

```lua
-- ❌ 错误：progress * 100 结果是 Fix32 类型
local progress = 0.5  -- 可能是 Fix32 类型
role.set_progressbar_current(bar, progress * 100)  -- 类型错误！

-- ✅ 正确：使用 math.tointeger() 转换为整数
local progress = 0.5
local progressInt = math.tointeger(progress * 100)  -- Fix32 → Integer
role.set_progressbar_current(bar, progressInt)  -- ✅
```

**常见需要转换的场景**：
- 进度条数值：`math.tointeger(progress * 100)`
- 百分比计算：`math.tointeger(value / total * 100)`
- 索引计算：`math.tointeger(position / cellSize)`

#### 1.3 判断依据

**查阅 EggyAPI.lua 中的参数类型标注**：

```lua
-- 示例：EggyAPI.lua 中的接口定义
---@param _preset Int 预设编号
---@param _parent ENode 父节点
---@param _x Fixed x坐标
---@param _y Fixed y坐标
---@param _w Fixed 宽度
---@param _h Fixed 高度
---@param _name Str 节点名称
function GameAPI.create_eui_image_at_position(_preset, _parent, _x, _y, _w, _h, _name) end
```

**类型对应表**：

| EggyAPI.lua 类型 | Lua 传参方式 | 示例 |
|-----------------|-------------|------|
| `Fixed` | `math.tofixed()` 转换 | `tf(100)` |
| `Int` / `Integer` | 直接传整数 | `100` |
| `Str` / `String` | 直接传字符串 | `"node_name"` |
| `Bool` / `Boolean` | 直接传布尔值 | `true` / `false` |

**常见 Fixed 类型参数**：坐标 (x, y)、尺寸 (width, height)、角度、速度、比例等

**常见 Integer 类型参数**：预设ID、不透明度 (0-255)、索引、数量等

---

### 2. 全局对象 (禁止 require)

以下是引擎全局对象，**不需要且禁止 require 导入**：

| 全局对象 | 用途 |
|---------|------|
| `GameAPI` | 游戏核心 API（创建UI、获取节点等） |
| `LuaAPI` | Lua 扩展 API（事件注册、延迟调用等） |
| `EVENT` | 事件常量 |
| `math` | 数学库（包含 `math.tofixed`） |

**⚠️ 注意**：`Role` **不是全局变量**！Role 实例必须从事件回调的 `data.role` 参数获取（参见 7.2 节）。

```lua
-- ✅ 正确：只 require 项目本地模块
local UINodes = require("Data.UINodes")

-- ❌ 错误：不要 require 全局对象
local GameAPI = require("GameAPI")  -- 错误! GameAPI 是全局的
local LuaAPI = require("LuaAPI")    -- 错误!
```

---

### 3. 画布节点获取 (从 UINodes)

编辑器中定义的节点存储在 `Data/UINodes.lua`，**直接就是 ECanvas/ENode 对象**：

```lua
local UINodes = require("Data.UINodes")
local canvas = UINodes["画布0"]  -- 直接就是 ECanvas 对象

-- ✅ 直接作为父节点使用
GameAPI.create_eui_image_at_position(10000, canvas, tf(0), tf(0), tf(100), tf(100), "bg")
```

**禁止臆断不存在的 API**：

```lua
-- ❌ 以下 API 不存在，不要臆断！
GameAPI.get_eui_node_by_id(canvasId)      -- 不存在!
GameAPI.find_eui_node(root, "Canvas")     -- 不存在!
GameAPI.get_canvas_by_name("画布0")        -- 不存在!
```

---

### 4. 坐标系统规则

- 坐标是**相对于父节点**的局部坐标
- 原点在父节点锚点位置（通常为左下角或中心）
- x 向右为正，y 向上为正
- **屏幕中心参考值**：1920x1080 分辨率下为 `(960, 540)`

```lua
local tf = math.tofixed
local centerX, centerY = tf(960), tf(540)  -- 屏幕中心

-- 创建居中弹窗
GameAPI.create_eui_image_at_position(16347, canvas, centerX, centerY, tf(740), tf(290), "popup")
```

---

### 5. 预设ID必须查阅文档

**禁止凭空编造预设ID**，必须从预设文档中获取真实存在的ID。

**常用图片预设速查：**

| 用途 | ID | 名称 | 尺寸 |
|------|-----|------|------|
| 关闭按钮图标 | 10011 | 关闭-常态 | 105x85 |
| 渐变半透背景 | 14588 | 渐变半透背景 | 104x174 |
| 蛋仔确认弹窗 | 16347 | 蛋仔确认弹窗 | 1477x580 |
| 蛋仔圆角弹窗 | 16348 | 蛋仔圆角弹窗遮罩 | 1578x682 |
| 圆形物品底图 | 11084 | 纯色圆形底图 | 100x100 |
| 乐园币图标 | 15056 | 乐园币 | 156x156 |

**常用按钮预设速查：**

| ID | 名称 | 尺寸 | 用途 |
|-----|------|------|------|
| 10005 | 关闭 | 105x85 | 关闭按钮 |
| 11001 | 金色按钮0 | 274x122 | 确认主按钮 |
| 11002 | 蓝色按钮0 | 274x122 | 取消副按钮 |
| 10020 | 条纹金 | 300x118 | 确认按钮 |
| 10019 | 条纹蓝 | 300x118 | 取消按钮 |

**常用进度条预设速查：**

| ID | 名称 | 尺寸 |
|-----|------|------|
| 30000 | 水平进度条 | 475x26 |
| 30003 | 进度条(HP) | 506x40 |
| 20002 | 环形进度条 | 128x128 |

> **完整预设列表**：参阅 `.codemaker/skills/eggy-eui-dev/references/presets/` 目录下的分类文档

---

### 6. 核心 API 速查

**创建节点 (GameAPI)：**

| 方法 | 说明 |
|------|------|
| `create_eui_image_at_position(preset, parent, x, y, w, h, name)` | 创建图片节点 |
| `create_eui_button_at_position(preset, parent, x, y, w, h, name)` | 创建按钮节点 |
| `create_eui_label_at_position(parent, x, y, w, h, name, text)` | 创建文本标签 |
| `create_eui_progress_at_position(preset, parent, x, y, w, h, name)` | 创建进度条 |
| `get_eui_child_by_name(node, name)` | 按名称获取子节点 |
| `get_eui_child_by_index(node, index)` | 按索引获取子节点 |
| `get_eui_children(node)` | 获取所有子节点列表 |

**设置属性 (Role)：**

| 方法 | 说明 |
|------|------|
| `set_node_visible(node, visible)` | 设置节点可见性 |
| `set_label_text(label, text)` | 设置标签文本内容 |
| `set_button_text(btn, text)` | 设置按钮文本 |
| `set_button_enabled(btn, enabled)` | 设置按钮启用状态 |
| `set_ui_opacity(node, opacity)` | 设置节点不透明度 |
| `set_node_touch_enabled(node, enabled)` | 设置节点触摸交互开关 |

**事件注册 (LuaAPI)：**

| 方法 | 说明 |
|------|------|
| `global_register_trigger_event({EVENT.GAME_INIT}, cb)` | 游戏初始化事件 |
| `global_register_trigger_event({EVENT.EUI_NODE_TOUCH_EVENT, node, type}, cb)` | EUI触摸事件 |
| `global_unregister_trigger_event(id)` | 取消事件注册 |

---

### 7. 标准代码模式

#### 7.1 基础弹窗模板

```lua
local UINodes = require("Data.UINodes")
local tf = math.tofixed

LuaAPI.global_register_trigger_event({EVENT.GAME_INIT}, function()
    local canvas = UINodes["画布0"]
    local centerX, centerY = tf(960), tf(540)
    
    -- 创建弹窗背景
    local bg = GameAPI.create_eui_image_at_position(
        16347,              -- 预设ID: 蛋仔确认弹窗
        canvas,             -- 父节点
        centerX, centerY,   -- 位置 (屏幕中心)
        tf(740), tf(290),   -- 尺寸
        "popup_bg"          -- 节点名称
    )
    
    -- 创建确认按钮
    local btn = GameAPI.create_eui_button_at_position(
        11001,              -- 预设ID: 金色按钮
        canvas,
        centerX, centerY - tf(80),
        tf(200), tf(80),
        "btn_confirm"
    )
    
    -- 创建标题文本
    local title = GameAPI.create_eui_label_at_position(
        canvas,
        centerX, centerY + tf(50),
        tf(300), tf(40),
        "txt_title",
        "标题文本"
    )
end)
```

#### 7.2 按钮事件绑定 (重要!)

**必须严格参照 EggyAPI.lua 中事件定义的注释使用事件回调参数。**

`EUI_NODE_TOUCH_EVENT` 事件的回调参数定义（摘自 EggyAPI.lua）：
- `data.role` - 触发事件的玩家（Role 实例）
- `data.eui_node_id` - 触发事件的界面控件

**⚠️ 关键点**：`Role` 不是全局变量！必须从 `data.role` 获取玩家实例后，才能调用 `role.set_node_visible()` 等方法。

```lua
local TOUCH_CLICK = 1  -- 触摸类型：点击

LuaAPI.global_register_trigger_event(
    {EVENT.EUI_NODE_TOUCH_EVENT, btn, TOUCH_CLICK},
    function(event_name, actor, data)
        -- ✅ 正确：从 data.role 获取玩家实例
        local role = data.role
        if role then
            role.set_node_visible(someNode, false)
            role.set_label_text(someLabel, "新文本")
        end
    end
)
```

```lua
-- ❌ 错误写法：Role 不是全局变量，直接调用会报错
LuaAPI.global_register_trigger_event(
    {EVENT.EUI_NODE_TOUCH_EVENT, btn, TOUCH_CLICK},
    function(event_name, actor, data)
        Role.set_node_visible(someNode, false)  -- 错误! Role 未定义
    end
)
```

#### 7.3 动态网格布局

```lua
local function createGrid(parent, startX, startY, cols, rows, cellSize, gap)
    local tf = math.tofixed
    local items = {}
    
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local x = startX + tf(col) * (cellSize + gap)
            local y = startY - tf(row) * (cellSize + gap)
            local item = GameAPI.create_eui_image_at_position(
                11084, parent, x, y, cellSize, cellSize,
                "cell_" .. (row * cols + col)
            )
            table.insert(items, item)
        end
    end
    
    return items
end

-- 使用示例：创建7列1行的签到格子
local cells = createGrid(canvas, tf(300), tf(500), 7, 1, tf(80), tf(10))
```

---

### 8. 常见错误与避坑

#### 8.1 类型错误：未使用 tofixed

```lua
-- ❌ 报错：type mismatch, expected Fix32, got int/float
GameAPI.create_eui_image_at_position(10000, canvas, 100, 200, 300, 400, "img")

-- ✅ 正确
GameAPI.create_eui_image_at_position(10000, canvas, tf(100), tf(200), tf(300), tf(400), "img")
```

#### 8.2 API 不存在：臆断 API

```lua
-- ❌ attempt to call a nil value
local canvas = GameAPI.get_eui_node_by_id(123)  -- 此 API 不存在

-- ✅ 从 UINodes 获取
local UINodes = require("Data.UINodes")
local canvas = UINodes["画布0"]
```

#### 8.3 预设ID错误：编造ID

```lua
-- ❌ 使用不存在的预设ID，UI不显示或报错
GameAPI.create_eui_image_at_position(99999, canvas, ...)

-- ✅ 使用文档中确认存在的预设ID
GameAPI.create_eui_image_at_position(16347, canvas, ...)  -- 蛋仔确认弹窗
```

#### 8.4 位置偏移：未居中

```lua
-- ❌ 使用 (0, 0) 导致UI在左下角
GameAPI.create_eui_image_at_position(16347, canvas, tf(0), tf(0), ...)

-- ✅ 使用屏幕中心坐标
GameAPI.create_eui_image_at_position(16347, canvas, tf(960), tf(540), ...)
```

---

### 9. 预设资源查阅指南

当需要查找特定类型的UI预设时，参阅以下文档：

| 需求 | 文档路径 |
|-----|---------|
| 图片预设总览 | `.codemaker/skills/eggy-eui-dev/references/presets/image-presets.md` |
| 图片预设详细分类 | `.codemaker/skills/eggy-eui-dev/references/presets/eui_img_presets/` |
| 按钮预设 | `.codemaker/skills/eggy-eui-dev/references/presets/button-presets.md` |
| 进度条预设 | `.codemaker/skills/eggy-eui-dev/references/presets/progress-presets.md` |
| API速查表 | `.codemaker/skills/eggy-eui-dev/references/api-cheatsheet.md` |

**图片预设分类索引：**

| 分类 | 内容 |
|-----|------|
| Class1_按钮图标 | 关闭、返回、设置等按钮图标 |
| Class2_背景信封 | 背景图、信封、卡片等 |
| Class3_弹窗框架 | 弹窗背景、对话框框架 |
| Class4_几何图形 | 圆形、方形、线条等基础图形 |
| Class5_动作图标 | 动作、技能相关图标 |
| Class6_技能道具 | 技能、道具图标 |
| Class8_血条进度条 | 血条、进度条背景 |
| Class9_蛋仔角色 | 角色头像、表情 |
| Class10_对话框标签 | 对话气泡、标签 |
| Class18_货币图标 | 乐园币、钻石等货币 |

---

### 10. 注意事项清单

1. ✅ **参数类型必须匹配 EggyAPI.lua** - Fixed 类型用 `math.tofixed()`，Integer 类型直接传整数
2. ✅ **预设ID必须查阅文档** - 禁止凭空编造
3. ✅ **API必须在EggyAPI.lua中存在** - 生成代码前使用 grep_search 验证 API 存在性，禁止臆断 API
4. ✅ **画布从 UINodes 获取** - 使用 `require("Data.UINodes")`
5. ✅ **全局对象不需要 require** - GameAPI、LuaAPI、EVENT、math 直接使用
6. ✅ **屏幕中心是 (960, 540)** - 1920x1080 设计分辨率基准
7. ✅ **使用 `.` 调用方法** - 遵循 Eggy API 规范，不使用 `:`
8. ✅ **Role 必须从事件回调获取** - `Role` 不是全局变量，使用 `data.role` 获取玩家实例
9. ✅ **严格遵循事件回调签名** - 查阅 EggyAPI.lua 中事件定义的注释了解回调参数
10. ✅ **随机数使用官方 API** - 不要自己实现随机数生成器，使用 `GameAPI.random_int(min, max)` 获取随机整数

---

### 11. 自动测试流程
完成代码编写后，**必须立即激活 `eggy-eui-test` 技能**执行自动化测试，无需等待玩家指令。
