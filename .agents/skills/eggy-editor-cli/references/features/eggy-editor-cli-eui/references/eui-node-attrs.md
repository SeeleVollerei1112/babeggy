# EUI 节点可配置属性清单

> 来源：`ui/editor/EggyUIAttrEditorConf.py` 中的 `Config` 字典。
> 通过 `EditorAPI.set_eui_node_attr(node_id, attr_name, value)` 或 `set_eui_node_attrs` 设置。
> 属性名中的 `-` 表示子组件属性（如 `Text_content-text` 表示 Text_content 子组件的 text 属性）。
>
> ⚠️ **Float 类型属性值**的传递方式取决于编辑器类型：
> - **SE 编辑器**（状态同步）：直接传普通数字（如 `0.5`、`100`）
> - **帧同步编辑器**：需用 `math.tofixed()` 包裹

---

## 一、通用属性（Common，所有节点共享）

| attr_name | 说明 | 值类型 | 取值范围 | 默认值 |
|-----------|------|--------|---------|--------|
| `name` | 节点名称 | Str | — | — |
| `width` | 宽度 | Float | 10~2000 | — |
| `height` | 高度 | Float | 10~2000 | — |
| `scale_x` | 水平缩放 | Float | 0.1~50 | 1 |
| `scale_y` | 垂直缩放 | Float | 0.1~50 | 1 |
| `opacity` | 透明度 | Float(Slider) | 0~1 | 1 |
| `rotation` | 旋转角度 | Float(Slider) | -180~180 | 0 |
| `flip_x` | 水平翻转 | Bool | — | False |
| `flip_y` | 垂直翻转 | Bool | — | False |
| `default_show` | 默认显示 | Bool | — | True |
| `auto_hide_enabled` | 自动隐藏开关 | Bool | — | False |
| `auto_hide_time` | 自动隐藏时间(秒) | Float | 0.01~9999 | — |
| `default_show_by_player_enabled` | 按玩家显示开关 | Bool | — | False |
| `default_show_by_player` | 按玩家显示列表 | List[Int] | 1~16 | [1..16] |
| `click_auto_hide` | 点击自动隐藏 | Bool | — | False |
| `touch_drag_enabled` | 触摸拖拽开关 | Bool | — | False |
| `take_photo_hide` | 拍照时隐藏 | Bool | — | True |
| `spectate_hide` | 观战时隐藏 | Bool | — | True |
| `auto_adaption` | 自适应布局 | 特殊格式 | — | — |

---

## 二、事件属性（Event，所有支持交互的节点共享）

| attr_name | 说明 | 值类型 |
|-----------|------|--------|
| `touch_enabled` | 触摸交互开关 | Bool |
| `local_ui_event` | 本地UI事件 | Bool |
| `touch_begin_event` | 触摸开始事件 | Str(事件名) |
| `touch_click_event` | 触摸点击事件 | Str(事件名) |
| `touch_end_event` | 触摸结束事件 | Str(事件名) |
| `long_touch_event` | 长按事件 | Str(事件名) |
| `long_touch_time` | 长按触发时间 | Float(Slider), 0.5~2.0 |
| `show_event` | 显示事件(入) | Str(事件名) |
| `hide_event` | 隐藏事件(入) | Str(事件名) |
| `reset_anim_event` | 重置动画事件(入) | Str(事件名) |
| `touch_begin_audio` | 触摸开始音效 | 音效资源 |
| `touch_end_audio` | 触摸结束音效 | 音效资源 |
| `touch_click_audio` | 点击音效 | 音效资源 |

---

## 三、图片节点（NormalImage）

| attr_name | 说明 | 值类型 |
|-----------|------|--------|
| `image_color` | 图片颜色叠加 | Color [R,G,B,A] 各 0~255 |
| `stretch_area` | 九宫格拉伸 | 特殊格式(预设) |

---

## 四、按钮节点（NormalButton）

| attr_name | 说明 | 值类型 |
|-----------|------|--------|
| `image_normal` | 常态图片预设 | Int(预设ID) |
| `image_press` | 按下图片预设 | Int(预设ID) |
| `image_disable` | 禁用图片预设 | Int(预设ID) |
| `button_press_color` | 按下颜色 | Color [R,G,B,A] |
| `button_normal_color` | 常态颜色 | Color [R,G,B,A] |
| `button_disable_color` | 禁用颜色 | Color [R,G,B,A] |
| `button_disable_event` | 禁用事件(入) | Str(事件名) |
| `button_enable_event` | 启用事件(入) | Str(事件名) |
| `text-text` | 按钮文字 | Str |
| `text-text_color` | 按钮文字颜色 | Color [R,G,B,A] |
| `text-font_size` | 按钮文字字号 | Int, 12~120 |
| `text-font_path` | 按钮文字字体 | Str(字体路径) |
| `stretch_area` | 九宫格拉伸 | 特殊格式(预设) |

---

## 五、文本节点（NormalLabel）

### 基本属性

| attr_name | 说明 | 值类型 | 取值范围 |
|-----------|------|--------|---------|
| `type_writer_enabled` | 打字机效果开关 | Bool | — |
| `type_writer_speed` | 打字速度 | Int(Slider) | 1~20 |
| `Text_content-text` | 文本内容 | Str | — |
| `Text_content-font_path` | 字体路径 | Str(枚举) | — |
| `Text_content-font_size` | 字号 | Int(Slider) | 12~120 |
| `Text_content-text_color` | 文字颜色 | Color [R,G,B,A] | — |
| `Text_content-text_h_alignment` | 水平对齐 | Int(枚举) | TextHAlignment |
| `Text_content-text_v_alignment` | 垂直对齐 | Int(枚举) | TextVAlignment |
| `Text_content-enable_italic` | 斜体开关 | Bool | — |
| `num_auto_scroll_enabled` | 数字滚动效果 | Bool | — |
| `rich_mode` | 富文本模式 | Bool | 默认True |
| `reset_size_policy` | 尺寸重置策略 | Int(枚举) | 0=无,1=宽度,2=高度 |

### 描边属性

| attr_name | 说明 | 值类型 | 取值范围 |
|-----------|------|--------|---------|
| `Text_content-enable_outline` | 描边开关 | Bool | — |
| `Text_content-outline_color` | 描边颜色 | Color [R,G,B,A] | — |
| `Text_content-outline_width` | 描边宽度 | Int(Slider) | 1~10 |
| `Text_content-outline_opacity` | 描边不透明度 | Float(Slider) | 0.01~1 |

### 阴影属性

| attr_name | 说明 | 值类型 | 取值范围 |
|-----------|------|--------|---------|
| `Text_content-enable_shadow` | 阴影开关 | Bool | — |
| `Text_content-shadow_posx` | 阴影X偏移 | Int(Slider) | -10~10 |
| `Text_content-shadow_posy` | 阴影Y偏移 | Int(Slider) | -10~10 |
| `Text_content-shadow_color` | 阴影颜色 | Color [R,G,B,A] | — |

### 背景属性

| attr_name | 说明 | 值类型 | 取值范围 |
|-----------|------|--------|---------|
| `Panel_bg-background_color` | 背景颜色 | Color [R,G,B,A] | — |
| `Panel_bg-background_opacity` | 背景不透明度 | Float(Slider) | 0~1 |

### 富文本扩展属性（依赖 `rich_mode=True`）

| attr_name | 说明 | 值类型 | 取值范围 |
|-----------|------|--------|---------|
| `RichTextEx-overflow_strategy` | 溢出策略 | Int(枚举) | OverflowStrategy |
| `RichTextEx-enable_auto_size` | 自动字号 | Bool | — |
| `RichTextEx-min_font_size` | 最小字号 | Int | 12~120 |
| `RichTextEx-text_spacing` | 字间距 | Float | -100~100 |
| `RichTextEx-line_spacing` | 行间距 | Float | -100~100 |
| `RichTextEx-gradient_enabled` | 渐变开关 | Bool | — |
| `RichTextEx-gradient_degree` | 渐变角度 | Int(Slider) | 0~360 |
| `RichTextEx-gradient_colors` | 渐变颜色 | 特殊格式 | — |

### 绑定属性

| attr_name | 说明 | 值类型 |
|-----------|------|--------|
| `label_bind_attr_type` | 绑定类型 | Int(枚举): 0=无,1=角色,2=玩家,3=商店,4=商品 |
| `label_bind_attr_sub_type` | 绑定子类型 | Int(枚举) |
| `label_bind_attr` | 绑定属性名 | Int(枚举) |
| `label_bind_attr_related_player_role_id` | 关联玩家ID | Int(枚举) |
| `label_bind_attr_related_creature_id` | 关联生物ID | 特殊格式 |
| `label_equipment_bind_attr` | 装备绑定属性 | Str |

---

## 六、输入框节点（InputField）

| attr_name | 说明 | 值类型 | 取值范围 |
|-----------|------|--------|---------|
| `TextField-text` | 占位提示文字 | Str | — |
| `TextField-text_color` | 占位文字颜色 | Color [R,G,B,A] | — |
| `Text_content-text` | 输入文本内容 | Str | — |
| `Text_content-font_path` | 字体路径 | Str(枚举) | — |
| `Text_content-font_size` | 字号 | Int(Slider) | 12~120 |
| `Text_content-text_color` | 文字颜色 | Color [R,G,B,A] | — |
| `Text_content-text_h_alignment` | 水平对齐 | Int(枚举) | TextHAlignment |
| `Text_content-text_v_alignment` | 垂直对齐 | Int(枚举) | TextVAlignment |
| `Text_content-enable_outline` | 描边开关 | Bool | — |
| `Text_content-outline_color` | 描边颜色 | Color [R,G,B,A] | — |
| `Text_content-outline_width` | 描边宽度 | Int(Slider) | 1~10 |
| `Text_content-outline_opacity` | 描边不透明度 | Float(Slider) | 0.01~1 |
| `Text_content-enable_shadow` | 阴影开关 | Bool | — |
| `Text_content-shadow_posx` | 阴影X偏移 | Int(Slider) | -10~10 |
| `Text_content-shadow_posy` | 阴影Y偏移 | Int(Slider) | -10~10 |
| `Text_content-shadow_color` | 阴影颜色 | Color [R,G,B,A] | — |
| `Text_content-enable_italic` | 斜体开关 | Bool | — |
| `Panel_bg-background_color` | 背景颜色 | Color [R,G,B,A] | — |
| `Panel_bg-background_opacity` | 背景不透明度 | Float(Slider) | 0~1 |
| `text_field_detach_event` | 输入完成事件(出) | Str(事件名) | — |

---

## 七、进度条节点（ProgressBar / ProgressBarNew）

| attr_name | 说明 | 值类型 | 取值范围 | 默认值 |
|-----------|------|--------|---------|--------|
| `text_show_type` | 文字显示样式 | Int(枚举) | ProgressBarTextStyle | — |
| `start` | 起始值 | Int | 0~9999 | 0 |
| `end` | 终止值 | Int | 0~9999 | 100 |
| `current` | 当前值 | Int | 0~9999 | 80 |
| `image_pic_id` | 背景图片预设 | Int(预设ID) | — | — |
| `Image_pic-image_color` | 背景图片颜色 | Color [R,G,B,A] | — | — |
| `loading_bar_pic_id` | 进度条图片预设 | Int(预设ID) | — | — |
| `LoadingBar-direction` | 填充方向 | Int(枚举) | ProgressBarDirection | — |
| `LoadingBar-image_color` | 进度条颜色 | Color [R,G,B,A] | — | — |
| `RText_num-font_path` | 文字字体 | Str(枚举) | — | — |
| `RText_num-text_color` | 文字颜色 | Color [R,G,B,A] | — | — |
| `RText_num-font_size` | 文字字号 | Int | 12~120 | — |
| `progress_increase_event` | 增加事件(入) | Str(事件名) | — | — |
| `progress_decrease_event` | 减少事件(入) | Str(事件名) | — | — |

> **ProgressBarNew** 额外属性：`progress_direction`(填充方向)、`Image_pic2-image_color`(进度条颜色)

---

## 八、环形进度条（ProgressTimer）

| attr_name | 说明 | 值类型 | 取值范围 |
|-----------|------|--------|---------|
| `start` | 起始值 | Int | 0~9999 |
| `end` | 终止值 | Int | 0~9999 |
| `current` | 当前值 | Int | 0~9999 |
| `image_pic_id` | 背景图片预设 | Int(预设ID) |
| `Sprite_pic-image_color` | 背景颜色 | Color [R,G,B,A] |
| `loading_bar_pic_id` | 进度条图片预设 | Int(预设ID) |
| `ProgressTimer-direction` | 填充方向 | Int(枚举) |
| `ProgressTimer-image_color` | 进度条颜色 | Color [R,G,B,A] |

---

## 九、几何图形节点（Polygon）

| attr_name | 说明 | 值类型 | 取值范围 |
|-----------|------|--------|---------|
| `polygon_type` | 图形类型 | Int(枚举) | 1=椭圆,2=矩形,3=正多边形 |
| `line_width` | 描边宽度 | Int(Slider) | 0~100 |
| `line_color` | 描边颜色 | Color [R,G,B,A] | — |
| `fill_color` | 填充颜色 | Color [R,G,B,A] | — |
| `line_count` | 边数(正多边形) | Int | 3~30 |
| `corner_radius` | 圆角半径(矩形) | Int(Slider) | 0~100 |

---

## 十、摇杆节点（JoystickNode）

| attr_name | 说明 | 值类型 |
|-----------|------|--------|
| `visible` | 默认显示 | Bool |
| `show_joystick_event` | 显示事件(入) | Str(事件名) |
| `hide_joystick_event` | 隐藏事件(入) | Str(事件名) |
| `default_show_by_player_enabled` | 按玩家显示开关 | Bool |
| `default_show_by_player` | 按玩家显示列表 | List[Int] |

---

## 十一、触摸板节点（TouchPad）

| attr_name | 说明 | 值类型 |
|-----------|------|--------|
| `slide_up_event` | 上滑事件 | Str(事件名) |
| `slide_down_event` | 下滑事件 | Str(事件名) |
| `slide_left_event` | 左滑事件 | Str(事件名) |
| `slide_right_event` | 右滑事件 | Str(事件名) |
| `slide_up_right_event` | 右上滑事件 | Str(事件名) |
| `slide_down_right_event` | 右下滑事件 | Str(事件名) |
| `slide_down_left_event` | 左下滑事件 | Str(事件名) |
| `slide_up_left_event` | 左上滑事件 | Str(事件名) |
| `simple_direction_event_enabled` | 简化方向事件 | Bool |
| `touchpad_image_preview_runtime` | 运行时预览图片 | Bool |

---

## 十二、小地图节点（MapView）

| attr_name | 说明 | 值类型 |
|-----------|------|--------|
| `show_friend` | 显示友方 | Bool |
| `show_enemy` | 显示敌方 | Bool |
| `show_creature` | 显示生物 | Bool |

---

## 属性命名规则

### 子组件属性格式
`子组件名-属性名`，用 `-` 分隔。

常见子组件前缀：
| 前缀 | 所属控件 | 说明 |
|------|---------|------|
| `Text_content-` | NormalLabel / InputField | 文本内容组件 |
| `Panel_bg-` | NormalLabel / InputField | 背景面板组件 |
| `RichTextEx-` | NormalLabel | 富文本扩展组件 |
| `TextField-` | InputField | 输入框占位文字组件 |
| `text-` | NormalButton | 按钮文字组件 |
| `LoadingBar-` | ProgressBar | 进度条填充组件 |
| `ProgressTimer-` | ProgressTimer | 环形进度条组件 |
| `Image_pic-` | ProgressBar | 背景图片组件 |
| `RText_num-` | ProgressBar | 进度数字组件 |
| `Sprite_pic-` | ProgressTimer | 背景精灵组件 |
| `Image_bg-` | BagSlot | 背包格背景组件 |
| `Image_border-` | BagSlot | 背包格边框组件 |
| `Image_default-` | BagSlot | 背包格默认图组件 |

### Color 格式
颜色值统一为 `[R, G, B, A]` 列表，每个分量 0~255：
```lua
EditorAPI.set_eui_node_attr('node_id', 'image_color', {255, 0, 0, 255})
```

### 枚举类型速查

**TextHAlignment**（水平对齐）：0=左对齐, 1=居中, 2=右对齐

**TextVAlignment**（垂直对齐）：0=顶部, 1=居中, 2=底部

**ProgressBarDirection**（进度条方向）：1=从左到右, 2=从右到左, 3=从下到上, 4=从上到下

**ProgressBarTextStyle**（进度条文字）：0=不显示, 1=百分比, 2=数值
