---
name: eggy-editor-cli-eui
description: |
  蛋仔编辑器 EUI 编辑时操作技能。通过 editor-cli.exe 调用 EditorAPI 的 EUI 接口，在编辑器中直接创建、修改、管理 UI 节点。

  使用场景：
  - 需要在编辑器中创建/删除/修改 EUI 节点时
  - 需要查询 EUI 节点树结构、属性时
  - 需要调整 EUI 节点层级、位置、尺寸时
  - 需要打开/切换 UI 编辑模式时
  - 用户提到"编辑器里加个UI"、"在编辑器创建按钮"、"编辑时操作EUI"、"EditorAPI EUI"等关键词时
---

# 编辑器 EUI 操作指南

## 概述

通过 `editor-cli.exe` 调用 `EditorAPI` 的 EUI 系列接口，在**编辑模式**下直接操控 EUI 节点。
与运行时 EUI 开发（在 Lua 脚本中调用 `GameAPI`/`Role`）不同，本技能用于**编辑器内**直接操作场景中的 UI 节点。

- **CLI 路径**: `.codemaker\editor-cli.exe`
- **固定端口**: `19836`
- **命令格式**: `.codemaker\editor-cli.exe --port 19836 exec "<Lua表达式>"`

## ⚠️ 编辑器类型区分：SE 编辑器 vs 帧同步编辑器

本技能同时适用于 **SE（状态同步）编辑器** 和 **帧同步编辑器**，但两者在数值参数传递上有关键区别：

| 编辑器类型 | Fixed 类型参数处理方式 | 示例（设置坐标 100, 200） |
|-----------|----------------------|--------------------------|
| **SE 编辑器**（状态同步） | **必须传浮点数（float）**，整数会报类型错误 | `EditorAPI.set_eui_node_pos('id', 100.0, 200.0)` |
| **帧同步编辑器** | **必须用 `math.tofixed()` 包裹** | `EditorAPI.set_eui_node_pos('id', math.tofixed(100), math.tofixed(200))` |

> **如何判断当前编辑器类型**：在前置条件中执行 `status` 命令时，同时查看返回结果中的 `is_se_mode` 字段即可，无需额外调用：
> - `is_se_mode  True` → **SE 编辑器**（状态同步），Fixed 参数必须传浮点数（如 `100.0`，不能传 `100`）
> - `is_se_mode  False` → **帧同步编辑器**，Fixed 参数必须用 `math.tofixed()` 包裹

以下文档中标注为 **Fixed** 的参数，均需按上述规则处理。文档示例默认以 **SE 编辑器** 为准（传浮点数），帧同步编辑器用户需自行将数值参数包裹 `math.tofixed()`。

## ⚠️ 前置条件

1. **编辑器已连接 & 确认编辑器类型**：用 `status` 检查连接状态，同时从返回结果中读取 `is_se_mode` 判断是 SE 编辑器还是帧同步编辑器
2. **UI 编辑器已打开**：需先调用 `EditorAPI.open_eui_editor()` 或手动打开
3. **确认处于 UI 编辑模式**：`EditorAPI.is_in_eui_edit_mode()` 返回 true

```bash
# 检查连接 & 确认编辑器类型（查看返回结果中的 is_se_mode 字段）
.codemaker\editor-cli.exe --port 19836 status

# 打开 UI 编辑器
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.open_eui_editor()"

# 确认处于 UI 编辑模式
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.is_in_eui_edit_mode()"
```

## ⚠️ 重要：CLI 调用无直接返回值

通过 `editor-cli.exe exec` 调用 `EditorAPI` **不会在终端直接输出返回值**。
需要查看返回结果时，必须将结果 `print` 到日志中，然后到 `log.txt` 查看。

```bash
# 查询并输出到日志的标准模式
.codemaker\editor-cli.exe --port 19836 exec "local ids = EditorAPI.get_all_eui_node_ids(); print('EUI_IDS:', table.concat(ids, ','))"

# 创建节点后获取 ID（SE 编辑器，必须传浮点数）
.codemaker\editor-cli.exe --port 19836 exec "local id = EditorAPI.create_eui_image_node(10011, 'parent_id', 0.0, 0.0, 100.0, 100.0, '图片'); print('NEW_NODE:', tostring(id))"

# 创建节点后获取 ID（帧同步编辑器，需要 math.tofixed）
.codemaker\editor-cli.exe --port 19836 exec "local id = EditorAPI.create_eui_image_node(10011, 'parent_id', math.tofixed(0), math.tofixed(0), math.tofixed(100), math.tofixed(100), '图片'); print('NEW_NODE:', tostring(id))"

# 然后读取 log.txt 查看结果
```

> **以下示例均以 SE 编辑器为准**（传浮点数，如 `100.0`）。帧同步编辑器用户请将所有 Fixed 参数包裹 `math.tofixed()`。
```

## ⚠️ 重要：Fixed 参数的处理方式（取决于编辑器类型）

`EditorAPI` 中参数类型为 `Fixed` 的参数（坐标、尺寸、偏移等）：
- **SE 编辑器**：**必须传浮点数（float）**（如 `100.0`、`0.5`），传整数（如 `100`）会报 `type mismatch, expected: <type 'float'>, got <type 'int'>` 错误
- **帧同步编辑器**：**必须用 `math.tofixed()` 包裹**（如 `math.tofixed(100)`、`math.tofixed(0.5)`）

不受编辑器类型影响的参数：`Int`（预设ID、字号等）、`Str`（节点ID、名称、文本等）、`Bool`——两种编辑器都直接传值。

## 工作流程

### 0. UI 设计规划（创建节点前必须完成）

> **核心原则**：像游戏 UI 设计师一样先规划，再像程序员一样执行。禁止跳过规划直接调用创建 API。

在执行任何创建/修改操作之前，必须先完成以下规划并输出方案：

#### 0.1 分析需求，确定界面结构

- 这个界面的功能是什么？（主界面、弹窗、HUD、设置面板……）
- 屏幕如何分区？（标题区占上方多少、内容区占中间多少、按钮区占下方多少）
- 节点层级怎么组织？（背景 → 面板/遮罩 → 子元素，哪些是父子关系）

#### 0.2 样式决策（颜色、对齐、字体）

**背景与前景是一起决策的**，不能选完背景再凑前景颜色：
- 背景偏亮/白色 → 标题用深色文字 + 浅色描边（如深蓝+白描边）
- 背景偏暗/深色 → 标题用亮色文字 + 深色描边（如白色+黑描边）
- 背景色彩丰富 → 在前景元素下垫半透明深色底板，保证对比度

**文本对齐是基本功**——标题、居中提示必须设水平居中对齐：
- `Text_content-text_h_alignment` = 1（居中）
- `Text_content-text_v_alignment` = 1（垂直居中）
- 不要用调 x 坐标的方式"凑"居中效果

**按钮文字**也要考虑字号与按钮尺寸的匹配。

#### 0.3 输出完整创建计划

在动手前，列出所有要创建的节点清单，格式如下：

```
| # | 节点名 | 类型 | 预设ID | 父节点 | x | y | w | h | 关键属性 |
|---|--------|------|--------|--------|---|---|---|---|----------|
| 1 | bg | Image | 32007 | canvas | 960 | 540 | 1920 | 1080 | — |
| 2 | title | Label | — | canvas | 960 | 720 | 600 | 80 | 居中对齐, 字号60, 白色+黑描边 |
| 3 | btn1 | Button | 11001 | canvas | 960 | 520 | 300 | 90 | 文字"开始" |
```

**确认计划完整无遗漏后，再进入下面的执行步骤。**

---

### 1. 查询节点

```bash
# 获取所有 EUI 节点 ID（需 print 到日志查看结果）
.codemaker\editor-cli.exe --port 19836 exec "local ids = EditorAPI.get_all_eui_node_ids(); print('EUI_IDS:', table.concat(ids, ','))"

# 按名称查找节点
.codemaker\editor-cli.exe --port 19836 exec "local ids = EditorAPI.get_eui_node_ids_by_name('按钮1'); print('FOUND:', table.concat(ids, ','))"

# 获取节点类型
.codemaker\editor-cli.exe --port 19836 exec "print('TYPE:', tostring(EditorAPI.get_eui_node_type('node_id_here')))"

# 获取节点子节点
.codemaker\editor-cli.exe --port 19836 exec "local ids = EditorAPI.get_eui_node_children('node_id_here'); print('CHILDREN:', table.concat(ids or {}, ','))"

# 获取节点父节点
.codemaker\editor-cli.exe --port 19836 exec "print('PARENT:', tostring(EditorAPI.get_eui_node_parent('node_id_here')))"

# 获取节点属性
.codemaker\editor-cli.exe --port 19836 exec "print('ATTR:', tostring(EditorAPI.get_eui_node_attr('node_id', 'pos')))"
```

### 2. 创建节点

> **⚠️ parent_id 是必填参数**：所有创建接口的 `parent_id` 必须显式传入一个有效的节点 ID，不能传 `nil`。
> **⚠️ Fixed 参数按编辑器类型处理**：SE 编辑器直接传数字，帧同步编辑器需用 `math.tofixed()` 包裹。
> 需先通过查询 API（如 `get_all_eui_node_ids()`）获取画布层或目标父节点的 ID。

```bash
# 先查询画布层 ID 作为 parent_id（结果在 log.txt 中查看）
.codemaker\editor-cli.exe --port 19836 exec "local ids = EditorAPI.get_all_eui_node_ids(); print('EUI_IDS:', table.concat(ids, ','))"
# 假设从 log 中看到画布层 ID 为 'canvas_001'

# 通用创建（指定类型字符串）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.create_eui_node('EUIImage', '图片1', 'canvas_001')"

# 创建图片节点（x,y,w,h 是 Fixed 参数，SE 编辑器必须传浮点数）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.create_eui_image_node(10011, 'canvas_001', 0.0, 0.0, 100.0, 100.0, '关闭图标')"

# 创建文本节点
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.create_eui_label_node('canvas_001', 0.0, 0.0, 200.0, 40.0, '标题', '你好世界')"

# 创建按钮节点
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.create_eui_button_node(11001, 'canvas_001', 0.0, 0.0, 274.0, 122.0, '确认按钮')"

# 创建进度条节点
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.create_eui_progressbar_node(30000, 'canvas_001', 0.0, 0.0, 475.0, 26.0, '血条')"

# 创建输入框节点
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.create_eui_input_node('canvas_001', 0.0, 0.0, 200.0, 50.0, '输入框', '请输入')"

# 创建列表节点
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.create_eui_listview_node('canvas_001', 0.0, 0.0, 200.0, 300.0, '列表')"

# 创建画布层（无 Fixed 参数）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.create_eui_canvas_layer_node('新画布', 'canvas_001')"

# 通过预设实例化节点树（无 Fixed 参数）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.create_eui_node_from_prefab(12345, 'canvas_001')"
```

### 3. 修改节点属性

```bash
# 设置单个属性
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_attr('node_id', 'name', '新名称')"

# 批量设置属性
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_attrs('node_id', {name='新名称', opacity=128})"

# 语义化快捷方法（pos/size 的参数是 Fixed，SE 编辑器必须传浮点数）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_pos('node_id', 100.0, 200.0)"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_size('node_id', 300.0, 150.0)"

# Str/Int/Bool 参数，两种编辑器都直接传值
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_name('node_id', '新名称')"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_visible('node_id', true)"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_opacity('node_id', 0.8)"

# 图片节点
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_image_texture('node_id', 'path/to/img')"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_image_color('node_id', 255, 0, 0, 255)"

# 文本节点
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_label_text('node_id', '新文本')"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_label_font_size('node_id', 24)"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_label_color('node_id', 255, 255, 0, 255)"

# 文本节点描边/阴影（width/opacity/offset 是 Fixed，SE 编辑器必须传浮点数）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_label_outline_width('node_id', 2.0)"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_label_outline_opacity('node_id', 0.8)"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_label_shadow_x_offset('node_id', 3.0)"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_label_shadow_y_offset('node_id', -3.0)"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_label_background_opacity('node_id', 0.5)"

# 按钮节点
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_button_text('node_id', '点击我')"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_button_enabled('node_id', true)"

# 进度条节点
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_progressbar_value('node_id', 50)"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_progressbar_max('node_id', 100)"

# 进度条过渡（duration 是 Fixed，SE 编辑器直接传数字）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_progressbar_transition('node_id', 80, 0.5)"
```

### 4. 层级管理

```bash
# 移动节点到新父节点下
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_parent('node_id', 'new_parent_id')"

# 调整同级排序
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_sibling_index('node_id', 0)"

# 删除节点
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.destroy_eui_node('node_id')"
```

### 5. 编辑模式切换

```bash
# 打开 UI 编辑器
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.open_eui_editor()"

# 检查是否在 UI 编辑模式
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.is_in_eui_edit_mode()"

# 切换到 3D Layer 编辑模式
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.switch_to_3d_layer_edit_mode('layer_id')"

# 切换回普通画布编辑模式
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.switch_to_normal_canvas_edit_mode()"

# 检查是否在 3D Layer 编辑模式
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.is_in_3d_layer_edit_mode()"
```

## 6. 截图验证与视觉调整

> **核心原则**：EUI 界面搭建完成后，**必须通过截图进行视觉检查**，根据截图内容分析各控件的实际显示效果，对大小、位置、间距、对齐等进行调整，直到界面符合预期。

### 6.1 截图验证流程

```
搭建界面完成 → 截图 → 读取截图图片 → 分析布局问题 → 调整控件属性 → 再次截图验证 → 确认通过
```

### 6.2 截图命令

```bash
# 截取当前编辑器屏幕（默认窗口尺寸）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.take_screenshot()"

# 截取指定尺寸的截图（如 1920x1080）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.take_screenshot_with_size(1920, 1080)"
```

**截图保存位置**：`doc_dir/res/editor_screenshots/screenshot_<timestamp>.png`
**获取保存路径**：截图路径会通过 `print` 输出到 `log.txt`，格式为 `[Screenshot] saved: <绝对路径>`

### 6.3 完整操作步骤

```bash
# 1. 搭建界面（假设已完成创建节点的步骤）

# 2. 截取当前界面
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.take_screenshot()"

# 3. 等待截图保存完成（约 1~2 秒）
# 4. 从 log.txt 中获取截图路径
# 5. 读取截图图片文件，分析各控件的视觉表现

# 6. 根据截图分析结果，调整控件的位置和大小
# 例：发现按钮偏左，将其右移 50 像素（SE 编辑器必须传浮点数）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_pos('btn_id', 510.0, 200.0)"

# 例：发现标题文字太小，增大尺寸
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_node_size('title_id', 400.0, 60.0)"
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.set_eui_label_font_size('title_id', 32)"

# 7. 调整完毕后再次截图验证
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.take_screenshot()"

# 8. 重复步骤 5~7 直到界面符合预期
```

### 6.4 截图分析：发现问题 → 正确行动

> **截图验证的目的是确认规划方案执行正确，不是用来代替规划。** 如果截图暴露的是规划阶段的遗漏（如忘了设对齐、颜色方案不对），应该回到根因修复，而不是反复微调坐标。

| 发现的问题 | ❌ 错误做法 | ✅ 正确做法 |
|-----------|-----------|-----------|
| 文本没有居中 | 反复调 x 坐标试图对齐 | 检查是否设了 `text_h_alignment=1`，没设就补上 |
| 文字与背景颜色冲突 | 在同色系微调 RGB | 换对比色方案，或在文字下方加半透明深色底板 |
| 按钮间距不均匀 | 逐个微调每个按钮的 y | 重新用公式计算所有按钮的 y 坐标，一次性全部修正 |
| 元素超出屏幕 | 只调这一个元素的位置 | 检查整体布局计算是否有误，可能需要调整分区比例 |
| 控件太小/太大 | 只调 size | 同时考虑字号、间距、整体比例是否协调 |

**关键原则：不要在同一个错误方向上反复微调超过 2 次。如果调了 2 次还不对，说明方案本身有问题，应该换方案。**

### 6.5 注意事项

1. **截图是异步的**：调用 `take_screenshot()` 后需等待 1~2 秒再读取图片文件，否则可能读到空文件
2. **截图路径在 log.txt 中**：查找 `[Screenshot] saved:` 关键字获取路径
3. **截图参数无需 math.tofixed**：`take_screenshot_with_size` 的 width/height 是 Int 类型
4. **多次迭代**：复杂界面可能需要 2~3 轮截图-调整循环才能达到理想效果
5. **结合节点查询**：调整前先用 `get_eui_node_attr(node_id, 'pos')` 和 `get_eui_node_attr(node_id, 'size')` 查询当前值，便于精确计算调整量

## 创建节点时的参数约定

| 参数 | 类型 | SE 编辑器 | 帧同步编辑器 | 说明 |
|------|------|----------|------------|------|
| `node_type` | Str | 直接传 | 直接传 | EUI 节点类型字符串 |
| `preset_id` | Int | 直接传 | 直接传 | 预设 ID（图片/按钮/进度条需要） |
| `parent_id` | Str | 直接传 | 直接传 | **必填**，父节点 ID |
| `x, y` | **Fixed** | ✅ 必须传浮点数（如 `0.0`） | ⚠️ `math.tofixed()` | 位置坐标 |
| `width, height` | **Fixed** | ✅ 必须传浮点数（如 `100.0`） | ⚠️ `math.tofixed()` | 尺寸 |
| `name` | Str | 直接传 | 直接传 | 节点名称；`nil` 时自动命名 |

> **注意**：
> - **SE 编辑器**：Fixed 类型参数必须传浮点数（如 `100.0`、`0.5`），不能传整数（如 `100`），否则报类型错误。
> - **帧同步编辑器**：Fixed 类型参数必须使用 `math.tofixed()` 转换。
> - 创建节点前必须先查询出有效的父节点 ID（画布层/已有节点），不能传 `nil`。
> - CLI 调用不会直接返回结果，需用 `print` 输出到 `log.txt` 查看。

## 常用预设速查

**图片预设：**

| ID | 名称 | 尺寸 |
|-----|------|------|
| 10011 | 关闭-常态 | 105x85 |
| 14588 | 渐变半透背景 | 104x174 |
| 16347 | 蛋仔确认弹窗 | 1477x580 |
| 16348 | 蛋仔圆角弹窗遮罩 | 1578x682 |
| 11084 | 纯色圆形底图 | 100x100 |

**按钮预设：**

| ID | 名称 | 尺寸 |
|-----|------|------|
| 10005 | 关闭 | 105x85 |
| 11001 | 金色按钮0 | 274x122 |
| 11002 | 蓝色按钮0 | 274x122 |

**进度条预设：**

| ID | 名称 | 尺寸 |
|-----|------|------|
| 30000 | 水平进度条 | 475x26 |
| 30003 | 进度条(HP) | 506x40 |
| 20002 | 环形进度条 | 128x128 |

> 完整预设列表参见 `.codemaker/skills/eggy-eui-dev/references/presets/` 目录。

## 注意事项

1. **先打开 UI 编辑器**：所有 EUI 操作前必须确保 UI 编辑器已打开
2. **node_id 是字符串**：从查询 API 返回的 ID 直接使用
3. **parent_id 必填**：所有创建接口的 parent_id 必须传有效的节点 ID，传 nil 会返回 nil 失败
4. **Fixed 参数按编辑器类型处理**：SE 编辑器必须传浮点数（如 `100.0`，不能传 `100`），帧同步编辑器必须用 `math.tofixed()` 转换。涉及的参数包括 x/y/width/height/opacity(0~1)/offset/duration 等
5. **CLI 无直接返回值**：需用 `print` 输出到 `log.txt` 查看结果
6. **所有写操作支持撤销**：编辑器命令系统保证 Undo/Redo
7. **字符串参数用单引号**：CLI exec 外层双引号，内层单引号
8. **创建后查验**：通过 `print` 输出到 log 确认创建成功

## 参考文档

- [CLI 工具编辑模式相关 API 参考](references/editor-eui-api.md)
- [编辑模式 UI 界面编辑指南](references/eui-editing.md)
- [EUI 节点属性参考](references/eui-node-attrs.md)