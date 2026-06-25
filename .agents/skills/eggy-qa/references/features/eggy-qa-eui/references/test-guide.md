# 测试编写指南

> 构建测试阶段的完整参考。涵盖 testspec 检测、代码分析、Name 注入、testspec 生成、基础检查、功能场景设计、测试代码编写。

---

## 一、Testspec 检测与读取

检查 `test/testspec_{模块名}.md` 是否存在：

- **存在** → 读取 5 章（模块信息、节点清单、交互逻辑、关键常量、设计意图），跳过第二~四节，直接进入第五节（基础检查）
- **不存在** → 执行完整流程（代码分析 → Name 注入 → 生成 Testspec → 基础检查 → 编写测试）

---

## 二、代码分析（无 testspec 路径）

读取被测 UI 代码，理解：

- **节点列表**：`GameAPI.create_eui_*` 的变量名、控件类型、父子层级、name 参数
- **事件绑定**：`LuaAPI.global_register_trigger_event` 绑定的事件类型和回调逻辑
- **定时器**：`LuaAPI.set_tick_handler` 或自定义帧计数器的逻辑
- **状态变量**：控制 UI 行为的 local 变量
- **常量定义**：数值型常量（如 `local CD_DURATION = 5`）

---

## 三、自动注入 Name（无 testspec 路径）

节点没有 name 参数时，测试无法通过 `TF.findNode(name)` 定位。扫描所有 `GameAPI.create_eui_*` 调用：有 name 参数 → 记录；无 name 参数 → 自动生成并追加。

### Name 前缀映射

| API 方法 | 前缀 | API 方法 | 前缀 |
|---------|------|---------|------|
| `create_eui_button_at_position` | `btn_` | `create_eui_progress_at_position` | `bar_` |
| `create_eui_image_at_position` | `img_` | `create_eui_input_at_position` | `input_` |
| `create_eui_label_at_position` | `label_` | `create_eui_clip_at_position` | `clip_` |
| `create_eui_layout_at_position` | `panel_`/`mask_` | `create_eui_list_at_position` | `list_` |
| `create_eui_particle_at_position` | `fx_` | | |

> Layout 特殊处理：全屏尺寸（≈1920x1080）→ `mask_` 前缀；否则 → `panel_`。
> 功能名从变量名推断（去掉类型后缀），冲突时追加 `_2`、`_3`。

### 注入格式

```lua
-- 注入前
local closeBtn = GameAPI.create_eui_button_at_position(
    11002, popup,
    tf(560), tf(80),
    tf(200), tf(80)
)

-- 注入后
local closeBtn = GameAPI.create_eui_button_at_position(
    11002, popup,
    tf(560), tf(80),
    tf(200), tf(80),
    "btn_close"  -- [auto-name]
)
```

在函数调用的最后一个参数后追加 name 参数。已有 name 参数不修改。

---

## 四、生成 Testspec（无 testspec 路径）

从已注入 Name 的代码反推生成 `test/testspec_{模块名}.md`。

### Testspec 格式

```markdown
# Testspec: {模块名}

## 1. 模块信息
- 文件路径: `xxx.lua`

## 2. 节点清单
| Name | 类型 | 父节点 | 说明 |
|------|------|--------|------|
| btn_xxx | Button | panel_main | ... |

## 3. 交互逻辑
| 触发条件 | 动作 | 目标节点 | 说明 |
|---------|------|---------|------|
| 点击 btn_xxx | set_node_visible | panel_detail | 显示详情面板 |

## 4. 关键常量
| 常量名 | 值 | 用途 |
|--------|---|------|
| CD_DURATION | 5 | 冷却时间（秒） |

## 5. 设计意图
描述"代码做了什么"（从行为推断），不是"开发者想要什么"。
```

**约束：**
- 不含 Lua 代码片段、测试步骤、UI 资源 ID、像素值
- 属性变化写明具体属性名和值；定时器参数与代码一致；常量为字面量
- 设计意图描述"代码做了什么"（从行为推断），不是"开发者想要什么"

---

## 五、基础检查

对被测代码逐项检查，发现问题立即修复。API 类检查须用 `grep_search` 在 `EggyAPI.lua` 中实际验证，不可跳过。

| 分类 | 检查项 | 修复方式 |
|------|--------|---------|
| 语法 | 非 UTF-8 / Emoji | 删除非法字符 |
| 语法 | 未定义变量引用 | 补充声明或删除 |
| 语法 | nil 传入数值构造 | 替换为默认值 |
| API | 使用了 EggyAPI.lua 中不存在的方法 | `grep_search` 验证后替换为正确方法或删除 |
| API | 错误地 require 全局对象（GameAPI/LuaAPI/EVENT/math） | 删除 require，直接使用 |
| 类型 | Fixed 参数未使用 `math.tofixed()` | 包裹 `tf()` / `math.tofixed()` |
| 类型 | Integer 参数误用了 `tofixed`（预设ID、不透明度等） | 去掉 `tofixed`，直接传整数 |
| 资源 | 预设ID未从文档确认（如 0、99999） | 查阅 `.codemaker/skills/eggy-eui-dev/references/presets/` 替换为真实ID |

> 测试代码自身也执行同样的基础检查。

---

## 六、功能场景设计

功能场景 = 用户视角的完整检查流程：场景名 → 前置条件 → 检查 → 验证（断言 + 截图）。

**第一个场景永远是"初始状态检查"**：检查节点存在 → 验证层级关系。

**后续场景从 testspec 节点清单推导：**

| testspec 内容 | 功能场景 |
|---|---|
| 多层嵌套层级 | 层级关系验证：逐层检查父子包含关系 |
| 独立功能区域（面板、弹窗） | 区域完整性检查：验证该区域所有节点存在 |

> **帧同步限制**：由于无模拟点击 API，无法验证点击→弹窗等交互流程。交互逻辑记录在 testspec 中作为文档，由截图视觉分析辅助验证初始 UI 状态。

### 截图视觉验证

截图由外部流程在测试完成后执行（`EditorAPI.take_screenshot()`），不在测试代码中调用。截图分析覆盖以下内容：

- UI 元素是否按预期布局显示（位置、大小、层级）
- 是否有明显的视觉异常（重叠、错位、空白区域、裁切）
- 文字是否可读、颜色是否正确
- 整体 UI 风格是否符合预期

---

## 七、测试代码编写

### 框架 API 速查

```lua
local TF = require("test.test_framework")
local runner = TF.createRunner("模块名")

-- 节点查找
TF.findNode(name)                                    -- 从画布递归查找节点（by Name）
TF.findNodeUnder(parent, name)                       -- 从指定父节点递归查找

-- 断言
runner:assert(name, condition, detail)               -- 基础断言
runner:assertNotNil(name, value)                     -- 非 nil 断言（节点存在性）
runner:assertEqual(name, actual, expected, detail)   -- 相等断言（子节点数量）
runner:assertChildExists(name, parent, childName)    -- 层级包含断言

-- 步骤执行器
TF.runSteps(runner, steps)                           -- 异步步骤执行（基于 tick 帧计数）
```

> **注意**：帧同步版没有 `TF.clickNode`、`TF.safeClick`、`TF.screenshot`、`runner:assertVisible`、`runner:assertText` 等 SE 版特有方法。

### 结构骨架

```lua
local TF = require("test.test_framework")

local steps = {
    -- 场景1: 初始状态检查
    {
        name  = "canvas_exists",
        delay = 0.1,
        fn = function(r)
            r:assertNotNil("canvas_exists", TF.canvas)
        end,
    },
    -- 关键节点存在检查（为每个 create_eui_* 的 name 参数生成一条）
    {
        name  = "node_{name}_exists",
        delay = 0.5,
        fn = function(r)
            local node = TF.findNode("{name}")
            r:assertNotNil("{name}_exists", node)
        end,
    },
    -- 层级关系检查（为每对父子关系生成一条）
    {
        name  = "hierarchy_{parent}_{child}",
        delay = 0.1,
        fn = function(r)
            local parent = TF.findNode("{parent_name}")
            r:assertChildExists("{child}_under_{parent}", parent, "{child_name}")
        end,
    },
}

local runner = TF.createRunner("{module_name}")
TF.runSteps(runner, steps)
```

### 超时计算

```
超时 = 所有步骤 delay 之和 + 30 秒安全余量
```

将结果作为 AI 轮询的超时上限。

### 等待时间规则

| 规则 | 等待时间 |
|------|---------|
| 节点存在检查（首个） | 0.5 秒 |
| 后续节点检查 | 0.1 秒 |
| 模块加载 | 0.5 秒 |
| 不确定时长 | 默认 1 秒 |

> 帧同步版因无交互测试，步骤间等待时间通常较短。
