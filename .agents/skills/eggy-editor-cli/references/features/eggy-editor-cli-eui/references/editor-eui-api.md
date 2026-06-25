# EditorAPI EUI 接口参考

> 编辑器模式下操作 EUI 节点的完整 API 列表。
> 所有接口通过 `EditorAPI.xxx()` 调用，支持撤销/重做。
>
> ⚠️ **CLI 调用无直接返回值**：需通过 `print` 输出到 `log.txt` 查看。
> ⚠️ **Fixed 类型参数**：标注为 **Fixed** 的参数，处理方式取决于编辑器类型：
> - **SE 编辑器**（状态同步）：**必须传浮点数（float）**（如 `100.0`、`0.5`），传整数（如 `100`）会报 `type mismatch, expected: <type 'float'>, got <type 'int'>` 错误
> - **帧同步编辑器**：**必须用 `math.tofixed()` 包裹**（如 `math.tofixed(100)`）

---

## 一、查询类 API

### EditorAPI.get_all_eui_node_ids()
- **描述**: 获取场景中所有 EUI 节点的 ID 列表（含普通节点和 3D Layer 节点）
- **参数**: 无
- **返回**: `list[str]` 节点 ID 列表；UI 编辑器未打开时返回 `[]`

### EditorAPI.get_eui_node_ids_by_name(name)
- **描述**: 按名称查找 EUI 节点，返回所有同名节点的 ID 列表
- **参数**: `name`(Str) 节点名称
- **返回**: `list[str]` 匹配节点 ID 列表；无匹配时返回 `[]`

### EditorAPI.get_eui_node_children(node_id)
- **描述**: 获取指定节点的直接子节点 ID 列表，顺序与编辑器层级面板一致
- **参数**: `node_id`(Str) 节点 ID
- **返回**: `list[str]` 子节点 ID 列表；节点不存在返回 `nil`；无子节点返回 `[]`

### EditorAPI.get_eui_node_parent(node_id)
- **描述**: 获取指定节点的父节点 ID
- **参数**: `node_id`(Str) 节点 ID
- **返回**: `str` 父节点 ID；根节点或节点不存在返回 `nil`

### EditorAPI.get_eui_node_type(node_id)
- **描述**: 获取指定节点的控件类型名称
- **参数**: `node_id`(Str) 节点 ID
- **返回**: `str` 类型名称（如 `"EUIImage"` `"EUIButton"`）；节点不存在返回 `nil`

### EditorAPI.get_eui_node_attr(node_id, attr_name)
- **描述**: 获取指定节点的属性值
- **参数**: `node_id`(Str) 节点 ID，`attr_name`(Str) 属性名
- **返回**: 属性值；节点不存在或属性名不合法返回 `nil`
- **常用属性名**: `pos` `size` `name` `opacity` `editor_visible` `visible` `touch_enabled`

---

## 二、创建类 API

### EditorAPI.create_eui_node(node_type, name, parent_id)
- **描述**: 通用创建接口，按类型字符串创建节点
- **参数**:
  - `node_type`(Str) 控件类型，如 `"EUIImage"` `"EUIButton"` `"EUITextLabel"`
  - `name`(Str|nil) 名称，nil 自动命名
  - `parent_id`(Str) **必填**，父节点 ID，必须为已存在的有效节点
- **返回**: `str` 新节点 ID；parent_id 无效或失败返回 `nil`

### EditorAPI.create_eui_image_node(preset_id, parent_id, x, y, width, height, name)
- **描述**: 创建图片（NormalImage）节点
- **参数**:
  - `preset_id`(Int) 图片预设 ID
  - `parent_id`(Str) **必填**，父节点 ID
  - `x`(**Fixed** ⚠️) X 坐标，默认 0
  - `y`(**Fixed** ⚠️) Y 坐标，默认 0
  - `width`(**Fixed** ⚠️) 宽度，默认 100
  - `height`(**Fixed** ⚠️) 高度，默认 100
  - `name`(Str|nil) 名称
- **返回**: `str` 新节点 ID；失败返回 `nil`

### EditorAPI.create_eui_label_node(parent_id, x, y, width, height, name, text)
- **描述**: 创建文本（NormalLabel）节点
- **参数**:
  - `parent_id`(Str) **必填**，父节点 ID
  - `x`(**Fixed** ⚠️) X 坐标，默认 0
  - `y`(**Fixed** ⚠️) Y 坐标，默认 0
  - `width`(**Fixed** ⚠️) 宽度，默认 100
  - `height`(**Fixed** ⚠️) 高度，默认 40
  - `name`(Str|nil) 名称
  - `text`(Str) 初始文本，默认空
- **返回**: `str` 新节点 ID；失败返回 `nil`

### EditorAPI.create_eui_button_node(preset_id, parent_id, x, y, width, height, name)
- **描述**: 创建按钮（NormalButton）节点
- **参数**:
  - `preset_id`(Int) 按钮预设 ID
  - `parent_id`(Str) **必填**，父节点 ID
  - `x`(**Fixed** ⚠️) X 坐标，默认 0
  - `y`(**Fixed** ⚠️) Y 坐标，默认 0
  - `width`(**Fixed** ⚠️) 宽度，默认 100
  - `height`(**Fixed** ⚠️) 高度，默认 60
  - `name`(Str|nil) 名称
- **返回**: `str` 新节点 ID；失败返回 `nil`

### EditorAPI.create_eui_progressbar_node(preset_id, parent_id, x, y, width, height, name)
- **描述**: 创建进度条（ProgressBar）节点
- **参数**:
  - `preset_id`(Int) 进度条预设 ID
  - `parent_id`(Str) **必填**，父节点 ID
  - `x`(**Fixed** ⚠️) X 坐标，默认 0
  - `y`(**Fixed** ⚠️) Y 坐标，默认 0
  - `width`(**Fixed** ⚠️) 宽度，默认 200
  - `height`(**Fixed** ⚠️) 高度，默认 30
  - `name`(Str|nil) 名称
- **返回**: `str` 新节点 ID；失败返回 `nil`

### EditorAPI.create_eui_input_node(parent_id, x, y, width, height, name, text)
- **描述**: 创建输入框（InputField）节点
- **参数**:
  - `parent_id`(Str) **必填**，父节点 ID
  - `x`(**Fixed** ⚠️) X 坐标，默认 0
  - `y`(**Fixed** ⚠️) Y 坐标，默认 0
  - `width`(**Fixed** ⚠️) 宽度，默认 200
  - `height`(**Fixed** ⚠️) 高度，默认 50
  - `name`(Str|nil) 名称
  - `text`(Str) 默认文本，默认空
- **返回**: `str` 新节点 ID；失败返回 `nil`

### EditorAPI.create_eui_listview_node(parent_id, x, y, width, height, name)
- **描述**: 创建列表（ListView）节点
- **参数**:
  - `parent_id`(Str) **必填**，父节点 ID
  - `x`(**Fixed** ⚠️) X 坐标，默认 0
  - `y`(**Fixed** ⚠️) Y 坐标，默认 0
  - `width`(**Fixed** ⚠️) 宽度，默认 200
  - `height`(**Fixed** ⚠️) 高度，默认 300
  - `name`(Str|nil) 名称
- **返回**: `str` 新节点 ID；失败返回 `nil`

### EditorAPI.create_eui_clipping_node(parent_id, x, y, width, height, name, clipping_id)
- **描述**: 创建遮罩（ClippingNode）节点
- **参数**:
  - `parent_id`(Str) **必填**，父节点 ID
  - `x`(**Fixed** ⚠️) X 坐标，默认 0
  - `y`(**Fixed** ⚠️) Y 坐标，默认 0
  - `width`(**Fixed** ⚠️) 宽度，默认 100
  - `height`(**Fixed** ⚠️) 高度，默认 100
  - `name`(Str|nil) 名称
  - `clipping_id`(Int|nil) 蒙版图片 ID
- **返回**: `str` 新节点 ID；失败返回 `nil`

### EditorAPI.create_eui_animation_node(preset_id, parent_id, x, y, width, height, name)
- **描述**: 创建动效（AnimationNode）节点
- **参数**:
  - `preset_id`(Int) 动效预设 ID
  - `parent_id`(Str) **必填**，父节点 ID
  - `x`(**Fixed** ⚠️) X 坐标，默认 0
  - `y`(**Fixed** ⚠️) Y 坐标，默认 0
  - `width`(**Fixed** ⚠️) 宽度，默认 100
  - `height`(**Fixed** ⚠️) 高度，默认 100
  - `name`(Str|nil) 名称
- **返回**: `str` 新节点 ID；失败返回 `nil`

### EditorAPI.create_eui_canvas_layer_node(name, parent_id)
- **描述**: 创建画布层（CanvasLayer）节点
- **参数**:
  - `name`(Str|nil) 名称
  - `parent_id`(Str) **必填**，父节点 ID
- **返回**: `str` 新节点 ID；失败返回 `nil`

### EditorAPI.create_eui_node_from_prefab(prefab_id, parent_id)
- **描述**: 通过预设 ID 实例化 EUI 节点树
- **参数**:
  - `prefab_id`(Int) EUI 预设 ID
  - `parent_id`(Str) **必填**，父节点 ID
- **返回**: `str` 根节点 ID；失败返回 `nil`

### EditorAPI.create_eui_3d_layer_node(parent_id)
- **描述**: 创建 EUI 3D Layer 节点（自动生成绑定的 prefab 数据）
- **参数**: `parent_id`(Str) **必填**，父节点 ID
- **返回**: `str` 新节点 ID；失败返回 `nil`

---

## 三、修改类 API

### EditorAPI.set_eui_node_attr(node_id, attr_name, value)
- **描述**: 设置节点单个属性（支持撤销/重做）
- **参数**: `node_id`(Str)，`attr_name`(Str)，`value`(Any)
- **返回**: `true` 成功；`false` 失败

### EditorAPI.set_eui_node_attrs(node_id, attr_dict)
- **描述**: 批量设置节点多个属性（支持撤销/重做）
- **参数**: `node_id`(Str)，`attr_dict`(Dict) `{attr_name=value, ...}`
- **返回**: `true` 成功；`false` 失败

### 语义化通用属性方法

| 方法 | 参数 | 说明 |
|------|------|------|
| `set_eui_node_pos(node_id, x, y)` | x,y: **Fixed** ⚠️ | 设置位置 |
| `set_eui_node_size(node_id, w, h)` | w,h: **Fixed** ⚠️ | 设置尺寸 |
| `set_eui_node_name(node_id, name)` | name: Str | 设置名称 |
| `set_eui_node_visible(node_id, visible)` | visible: Bool | 编辑器可见性 |
| `set_eui_node_opacity(node_id, opacity)` | opacity: **Fixed**(0~1) ⚠️ SE直接传数字 | 设置透明度 |
| `set_eui_node_touch_enabled(node_id, enabled)` | enabled: Bool | 交互开关 |
| `set_eui_node_canvas_visible(node_id, visible)` | visible: Bool | 运行时可见性 |

### 图片节点属性方法

| 方法 | 参数 | 说明 |
|------|------|------|
| `set_eui_image_color(node_id, r, g, b, a)` | RGBA: Int(0~255) | 颜色叠加 |

### 文本节点属性方法

| 方法 | 参数 | 说明 |
|------|------|------|
| `set_eui_label_text(node_id, text)` | text: Str | 文本内容 |
| `set_eui_label_font_size(node_id, size)` | size: Int | 字号 |
| `set_eui_label_color(node_id, r, g, b, a)` | RGBA: Int(0~255) | 文字颜色 |
| `set_eui_label_font(node_id, font_key)` | font_key: Str | 字体路径 |
| `set_eui_label_background_color(node_id, r, g, b, a)` | RGBA: Int(0~255) | 背景颜色 |
| `set_eui_label_background_opacity(node_id, opacity)` | opacity: **Fixed**(0~1) ⚠️ | 背景不透明度 |
| `set_eui_label_outline_enabled(node_id, enabled)` | enabled: Bool | 描边开关 |
| `set_eui_label_outline_color(node_id, r, g, b, a)` | RGBA: Int(0~255) | 描边颜色 |
| `set_eui_label_outline_width(node_id, width)` | width: **Fixed** ⚠️ | 描边宽度 |
| `set_eui_label_outline_opacity(node_id, opacity)` | opacity: **Fixed**(0~1) ⚠️ | 描边不透明度 |
| `set_eui_label_shadow_enabled(node_id, enabled)` | enabled: Bool | 阴影开关 |
| `set_eui_label_shadow_color(node_id, r, g, b, a)` | RGBA: Int(0~255) | 阴影颜色 |
| `set_eui_label_shadow_x_offset(node_id, x_offset)` | x_offset: **Fixed** ⚠️ | 阴影X偏移 |
| `set_eui_label_shadow_y_offset(node_id, y_offset)` | y_offset: **Fixed** ⚠️ | 阴影Y偏移 |

### 按钮节点属性方法

| 方法 | 参数 | 说明 |
|------|------|------|
| `set_eui_button_text(node_id, text)` | text: Str | 按钮文字 |
| `set_eui_button_normal_image(node_id, path)` | path: Str | 常态图片 |
| `set_eui_button_pressed_image(node_id, path)` | path: Str | 按下图片 |
| `set_eui_button_text_color(node_id, r, g, b, a)` | RGBA: Int(0~255) | 文字颜色 |
| `set_eui_button_font_size(node_id, size)` | size: Int | 文字字号 |

### 进度条节点属性方法

| 方法 | 参数 | 说明 |
|------|------|------|
| `set_eui_progressbar_value(node_id, value)` | value: Int | 当前进度 |
| `set_eui_progressbar_max(node_id, max_value)` | max_value: Int | 最大值 |
| `set_eui_progressbar_min(node_id, min_value)` | min_value: Int | 最小值 |
| `set_eui_progressbar_transition(node_id, value)` | value: Int | 设置进度（等同 set_eui_progressbar_value） |

### 输入框节点属性方法

| 方法 | 参数 | 说明 |
|------|------|------|
| `set_eui_input_field_text(node_id, text)` | text: Str | 输入内容 |
| `set_eui_input_field_placeholder(node_id, placeholder)` | placeholder: Str | 占位提示文字 |

---

## 四、层级管理 API

### EditorAPI.set_eui_node_parent(node_id, new_parent_id)
- **描述**: 移动节点到另一个父节点下（支持撤销/重做）
- **参数**: `node_id`(Str)，`new_parent_id`(Str|nil) nil=移至根层级（top_layer 下）
- **返回**: `true` 成功；`false` 节点不存在/目标为后代节点/失败
- **注意**: 自动检测循环层级，防止父节点移到子节点下

### EditorAPI.set_eui_node_sibling_index(node_id, index)
- **描述**: 调整节点在同级中的顺序（影响渲染层级），支持撤销/重做
- **参数**: `node_id`(Str)，`index`(Int) 目标索引（从 0 开始），超范围自动 clamp
- **返回**: `true` 成功；`false` 失败

### EditorAPI.destroy_eui_node(node_id)
- **描述**: 删除节点及所有子节点（支持撤销/重做）
- **参数**: `node_id`(Str) 节点 ID
- **返回**: `true` 成功；`false` 节点不存在/失败
- **注意**: 3D Layer 节点会同步删除对应 prefab 数据

---

## 五、3D Layer 操作 API

### EditorAPI.modify_eui_3d_layer_prefab(node_id, key, value)
- **描述**: 修改 3D Layer 预设根节点数据
- **参数**: `node_id`(Str)，`key`(Str) 属性名，`value`(Any) 属性值
- **返回**: `true` 成功；`false` 失败

### EditorAPI.sync_eui_3d_layer_child(layer_node_id, child_node_id)
- **描述**: 同步子节点状态到 3D Layer 预设数据
- **参数**: `layer_node_id`(Str)，`child_node_id`(Str)
- **返回**: `true` 成功；`false` 失败

### EditorAPI.get_eui_3d_layer_prefab_data(node_id)
- **描述**: 获取 3D Layer 完整预设数据字典
- **参数**: `node_id`(Str)
- **返回**: `dict` 预设数据；非 3D Layer 返回 `nil`

---

## 六、编辑器状态管理 API

### EditorAPI.open_eui_editor()
- **描述**: 打开 EUI 编辑器（若已打开不重复操作）
- **返回**: `true` 成功/已打开；`false` 失败

### EditorAPI.is_in_eui_edit_mode()
- **描述**: 判断当前是否处于 UI 编辑模式
- **返回**: `true`/`false`

### EditorAPI.switch_to_3d_layer_edit_mode(layer_id)
- **描述**: 切换到 3D Layer 预设编辑模式
- **参数**: `layer_id`(Str) 3D Layer 节点 ID
- **返回**: `true` 成功；`false` 失败

### EditorAPI.switch_to_normal_canvas_edit_mode()
- **描述**: 从 3D Layer 模式切回普通画布编辑模式
- **返回**: `true` 成功；`false` 非 3D 模式/失败

### EditorAPI.is_in_3d_layer_edit_mode()
- **描述**: 判断当前是否处于 3D Layer 编辑模式
- **返回**: `true`/`false`

---

## 七、截图 API

### EditorAPI.take_screenshot()
- **描述**: 截取当前编辑器屏幕画面并保存为 PNG 图片。截图保存在 `doc_dir/res/editor_screenshots/` 目录下，文件名包含时间戳。截图完成后会在日志中输出保存路径。
- **参数**: 无
- **返回**: `str` 截图保存的绝对路径（如 `C:/.../res/editor_screenshots/screenshot_1710920000000.png`）
- **注意**: 截图是异步保存的，调用后需等待片刻再读取文件。建议调用后延迟 1~2 秒再读取图片。

### EditorAPI.take_screenshot_with_size(width, height)
- **描述**: 截取当前编辑器屏幕画面并保存为**指定尺寸**的 PNG 图片。用于需要特定分辨率截图的场景。
- **参数**:
  - `width`(Int) 截图宽度（像素）
  - `height`(Int) 截图高度（像素）
- **返回**: `str` 截图保存的绝对路径（如 `C:/.../res/editor_screenshots/screenshot_1920x1080_1710920000000.png`）
- **注意**: 同 `take_screenshot()`，截图异步保存，调用后需等待片刻再读取文件。
