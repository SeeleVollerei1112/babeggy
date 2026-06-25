# EUI 界面编辑指南

> ⚠️ **安全前置**：所有 EUI **写入操作**（创建/修改/删除节点）必须在 `editor_status == idle` 时执行。
> 读取操作（查询节点、获取属性）任何状态均可。

## 状态前置检查

```batch
# 执行 EUI 写入操作前，先确认处于编辑时
%CLI% status
# editor_status 必须为 idle，否则提示：
# 「EUI 编辑操作只能在编辑时（idle）执行，请先停止试玩」
```

---

## 节点查询速查表

| 操作 | CLI 命令 | 返回 |
|------|---------|------|
| 查询所有节点 | `EditorAPI.get_all_eui_node_ids()` | 节点ID列表 |
| 按名称查节点 | `EditorAPI.get_eui_node_ids_by_name('名称')` | 匹配ID列表 |
| 获取子节点列表 | `EditorAPI.get_eui_node_children(node_id)` | 子节点ID列表 |
| 获取父节点 | `EditorAPI.get_eui_node_parent(node_id)` | 父节点ID |
| 获取节点类型 | `EditorAPI.get_eui_node_type(node_id)` | 类型字符串 |
| 获取节点属性 | `EditorAPI.get_eui_node_attr(node_id, 'attr_name')` | 属性值 |

示例：
```batch
# 按名称查找得分文本节点
%CLI% exec "EditorAPI.get_eui_node_ids_by_name('ScoreLabel')"

# 获取节点类型
%CLI% exec "EditorAPI.get_eui_node_type(node_id)"
```

---

## 节点创建速查表

所有创建操作必须在 `idle` 状态执行，返回新节点的 ID。

### 创建文本节点（ELabel）

```batch
EditorAPI.create_eui_label_node(parent_id, x, y, width, height, 'NodeName', '初始文本')
```

| 参数 | 类型 | 说明 |
|------|------|------|
| parent_id | **Str** | 父节点ID，**必须是字符串**，通常是画布节点 ID |
| x, y | **Fixed** | 位置坐标（像素），**必须是浮点数**，如 `225.0` |
| width, height | **Fixed** | 节点尺寸（像素），**必须是浮点数**，如 `300.0` |
| NodeName | Str | 节点名称（如 `'ScoreLabel'`） |
| 初始文本 | Str | 显示的文字内容 |

> ⚠️ **父节点 ID 必须是字符串**：画布 ID 形如 `'1405255247'`，不能传整数 `0`。
> ⚠️ **坐标和尺寸必须是浮点数**：传整数会报 `type mismatch, expected Fix32`。
> ⚠️ **如何获取画布 ID**：先用 `EditorAPI.get_all_eui_node_ids()` 查询所有节点，根节点即为画布。

```batch
# ✅ 正确示例（父节点字符串，坐标浮点）
%CLI% exec "EditorAPI.create_eui_label_node('1405255247', 225.0, 60.0, 300.0, 80.0, 'ScoreLabel', 'Score: 0')"

# ❌ 错误：父节点传整数 0，创建失败
%CLI% exec "EditorAPI.create_eui_label_node(0, 225, 60, 300, 80, 'ScoreLabel', 'Score: 0')"
```

### 创建图片节点（EImage）

```batch
EditorAPI.create_eui_image_node(preset_id, parent_id, x, y, width, height, 'NodeName')
```

| 参数 | 类型 | 说明 |
|------|------|------|
| preset_id | Int | 图片预设ID（0 = 空白） |
| parent_id | **Str** | 父节点ID，必须是字符串 |

### 创建按钮节点（EButton）

```batch
EditorAPI.create_eui_button_node(preset_id, parent_id, x, y, width, height, 'NodeName')
```

| 参数 | 类型 | 说明 |
|------|------|------|
| preset_id | Int | 按钮样式预设ID |
| parent_id | **Str** | 父节点ID，必须是字符串 |

### 创建进度条节点（EProgressbar）

```batch
EditorAPI.create_eui_progressbar_node(preset_id, parent_id, x, y, width, height, 'NodeName')
```

### 删除节点

```batch
EditorAPI.destroy_eui_node(node_id)  -- 返回 Bool
```

---

## 节点属性修改速查表

### 通用布局属性

| 操作 | CLI 命令 |
|------|---------|
| 设置位置 | `EditorAPI.set_eui_node_pos(node_id, x, y)` |
| 设置尺寸 | `EditorAPI.set_eui_node_size(node_id, width, height)` |
| 设置可见性 | `EditorAPI.set_eui_node_visible(node_id, true/false)` |
| 设置透明度 | `EditorAPI.set_eui_node_opacity(node_id, 0.0~1.0)` |
| 设置名称 | `EditorAPI.set_eui_node_name(node_id, 'NewName')` |
| 批量设置属性 | `EditorAPI.set_eui_node_attrs(node_id, attr_dict)` |
| 设置父节点 | `EditorAPI.set_eui_node_parent(node_id, new_parent_id)` |
| 设置层级顺序 | `EditorAPI.set_eui_node_sibling_index(node_id, index)` |
| 设置交互开关 | `EditorAPI.set_eui_node_touch_enabled(node_id, true/false)` |

### 文本节点（ELabel）专有属性

> ⚠️ **类型规则（实测确认）**：
> - `set_eui_label_font_size` 的 `size` 参数类型为 **int**，传浮点数（如 `48.0`）会报 `type mismatch, expected int, got Fix32`
> - `set_eui_label_color` 的 `r, g, b, a` 参数类型均为 **int**，传浮点数同样报错
> - 正确写法：`set_eui_label_font_size('id', 48)`、`set_eui_label_color('id', 255, 0, 0, 255)`

| 操作 | CLI 命令 | 参数类型 |
|------|---------|---------|
| 设置文本内容 | `EditorAPI.set_eui_label_text(node_id, '文字')` | Str |
| 设置字号 | `EditorAPI.set_eui_label_font_size(node_id, 24)` | **int**（不能加 `.0`） |
| 设置文字颜色 | `EditorAPI.set_eui_label_color(node_id, r, g, b, a)` | **int × 4**（不能加 `.0`） |
| 设置字体 | `EditorAPI.set_eui_label_font(node_id, 'font_path')` |
| 设置描边开关 | `EditorAPI.set_eui_label_outline_enabled(node_id, true)` |
| 设置描边颜色 | `EditorAPI.set_eui_label_outline_color(node_id, r, g, b, a)` |
| 设置描边宽度 | `EditorAPI.set_eui_label_outline_width(node_id, 2.0)` |

> ⚠️ **描边必须两步同时启用才生效**：仅调用 `set_eui_label_outline_enabled(true)` 或仅调用 `set_eui_label_outline_color` 均无效，两条命令必须都执行：
> ```batch
> EditorAPI.set_eui_label_outline_enabled('node_id', true)
> EditorAPI.set_eui_label_outline_color('node_id', 255, 255, 255, 255)
> ```
| 设置阴影开关 | `EditorAPI.set_eui_label_shadow_enabled(node_id, true)` |
| 设置阴影颜色 | `EditorAPI.set_eui_label_shadow_color(node_id, r, g, b, a)` |
| 设置背景颜色 | `EditorAPI.set_eui_label_background_color(node_id, r, g, b, a)` |

### 按钮节点（EButton）专有属性

| 操作 | CLI 命令 |
|------|---------|
| 设置按钮文字 | `EditorAPI.set_eui_button_text(node_id, '按钮文字')` |
| 设置文字颜色 | `EditorAPI.set_eui_button_text_color(node_id, r, g, b, a)` |
| 设置文字字号 | `EditorAPI.set_eui_button_font_size(node_id, 20)` |
| 设置常态图片 | `EditorAPI.set_eui_button_normal_image(node_id, 'texture_path')` |
| 设置按下图片 | `EditorAPI.set_eui_button_pressed_image(node_id, 'texture_path')` |

### 图片节点（EImage）专有属性

| 操作 | CLI 命令 |
|------|---------|
| 设置图片颜色 | `EditorAPI.set_eui_image_color(node_id, r, g, b, a)` |

### 进度条节点（EProgressbar）专有属性

| 操作 | CLI 命令 |
|------|---------|
| 设置当前值 | `EditorAPI.set_eui_progressbar_value(node_id, value)` |
| 设置最大值 | `EditorAPI.set_eui_progressbar_max(node_id, max_value)` |
| 设置最小值 | `EditorAPI.set_eui_progressbar_min(node_id, min_value)` |
| 过渡动画 | `EditorAPI.set_eui_progressbar_transition(node_id, value, duration)` |

---

## 完整示例：创建倒计时文本节点

**场景**：在 Canvas 根节点下创建一个显示「30」的倒计时文本，白色描边，居中显示。

```batch
# 步骤 1：确认处于编辑时
%CLI% status
# → editor_status 必须为 idle

# 步骤 2：查找画布根节点 ID（get_all_eui_node_ids 返回的第一个即为画布）
%CLI% exec "print(EditorAPI.get_all_eui_node_ids())"
# → 记录画布节点 ID 字符串，如 "1405255247"

# 步骤 3：创建文本节点（屏幕中上方，坐标和尺寸必须是浮点数）
%CLI% exec "EditorAPI.create_eui_label_node('1405255247', 225.0, 60.0, 300.0, 80.0, 'CountdownLabel', '30')"
# → 返回新节点 ID 字符串，如 "label_001"

# 步骤 4：设置字号为 48
%CLI% exec "EditorAPI.set_eui_label_font_size('label_001', 48)"

# 步骤 5：设置文字颜色为黄色
%CLI% exec "EditorAPI.set_eui_label_color('label_001', 255, 220, 0, 255)"

# 步骤 6：开启白色描边
%CLI% exec "EditorAPI.set_eui_label_outline_enabled('label_001', true)"
%CLI% exec "EditorAPI.set_eui_label_outline_color('label_001', 255, 255, 255, 255)"
%CLI% exec "EditorAPI.set_eui_label_outline_width('label_001', 2.0)"
```

---

## UI 编辑模式切换

```batch
# 打开 UI 编辑器
%CLI% exec "EditorAPI.open_eui_editor()"

# 查询是否处于 UI 编辑模式
%CLI% exec "EditorAPI.is_in_eui_edit_mode()"

# 切回普通画布编辑模式
%CLI% exec "EditorAPI.switch_to_normal_canvas_edit_mode()"
```
