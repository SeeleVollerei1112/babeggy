# EUI 进度条预设参考

用于 `GameAPI.create_eui_progress_bar_at_position()` 的 `preset_id` 参数。

## 水平进度条 (推荐) ⭐

| ID | 名称 | 尺寸 | 说明 |
|----|------|------|------|
| 30000 | 进度条 | 475x26 | 标准进度条 |
| 30001 | 进度条 | 346x42 | 中等宽度 |
| 30002 | 进度条 | 222x24 | 紧凑型 |
| 30003 | 进度条(HP) | 506x40 | 血条专用 |
| 30004 | 进度条 | 506x40 | 宽型 |
| 30005 | 进度条 | 475x26 | 标准 |

## 环形进度条

| ID | 名称 | 尺寸 | 说明 |
|----|------|------|------|
| 20002 | 环形进度条 | 128x128 | 标准环形 |
| 20003 | 环形进度条 | 128x128 | |
| 20004 | 环形进度条 | 128x128 | |
| 20005 | 环形进度条 | 198x198 | 大号环形 |
| 20006 | 环形进度条 | 108x108 | 小号环形 |

## 使用示例

```lua
local tf = math.tofixed
local UINodes = require("Data.UINodes")
local canvas = UINodes["画布0"]

-- 创建水平进度条
local hpBar = GameAPI.create_eui_progress_bar_at_position(
    30003,  -- HP进度条
    canvas,
    tf(960), tf(600),
    tf(400), tf(32),
    "hp_bar"
)

-- 创建环形进度条（技能冷却等）
local cdBar = GameAPI.create_eui_progress_bar_at_position(
    20002,  -- 环形进度条
    canvas,
    tf(200), tf(200),
    tf(100), tf(100),
    "skill_cd"
)

-- 设置进度值 (0.0 ~ 1.0)
Role.set_progress_bar_value(hpBar, 0.75)  -- 75%
Role.set_progress_bar_value(cdBar, 0.5)   -- 50%
```

## 场景推荐

| 用途 | 推荐ID | 类型 |
|------|--------|------|
| 血条/HP | 30003 | 水平 |
| 经验条 | 30000 | 水平 |
| 加载进度 | 30001 | 水平 |
| 技能冷却 | 20002 | 环形 |
| 倒计时 | 20005 | 环形(大) |
| 小型CD | 20006 | 环形(小) |

## 注意事项

1. 进度条值范围为 `0.0` 到 `1.0`
2. 使用 `Role.set_progress_bar_value(bar, value)` 更新进度
3. 环形进度条适合表示技能CD、倒计时等场景
4. 水平进度条适合表示HP、经验值、加载进度等
