# 宝宝 AI 架构规约（BabyStorm）

> 本文件是 BabyStorm 模块 AI 重构的**验收标准**。所有改动以此为准；与此冲突的旧写法一律视为待修。
> 适用范围：`BabyStorm/Domain/**`、`BabyStorm/Services/**` 中与宝宝个体行为相关的代码。

## 0. 一句话主旨

把混在一起的五层职责拆开，并规定它们之间**单向**的数据流：

```
需求(数据) → 行为(选流程) → 移动(执行位移) → 动画(表现) → 表现层(气泡/音效)
```

口诀：**需求不是行为，行为不是移动，移动不是动画，动画不是逻辑。**

## 1. 五层职责与单向数据流

| 层 | 职责 | 只能做 | 绝不能做 |
|----|------|--------|----------|
| NeedSystem | 产生/持有需求数据 | 生成 `current_need`、推进需求生命周期 | 直接改位置/播动画 |
| BehaviorFSM | 选择解决当前需求的流程 | **输出意图**：`move_mode / anim_base / anim_overlay / action_lock` | 直接 `start_move_*` / `play_*_anim` |
| MovementSystem | 执行位移 | 真正调用引擎移动 API、加/解 `BUFF_FORBID_MOVE` | 决定"该不该走"（那是行为层的事） |
| AnimationSystem | 播放表现 | 真正调用 `play_body_anim_*` / 停动画 | 反过来驱动行为切换 |
| Presentation | 气泡/表情/音效/UI | 监听 ViewModel 渲染 | 持有游戏逻辑 |

**硬约束**：
- **只有 MovementSystem 真正改位置**；**只有 AnimationSystem 真正播动画**。其它任何文件出现 `start_move_to_pos_*` / `play_body_anim_*` / `ai_command_*` 直接调用，即为违规。
- 行为状态**只写意图字段**，由 Movement/Animation 在每帧末尾统一 reconcile。

## 2. 五条红线（不可违反）

1. **需求是数据，不是状态**。用 `current_need = { type, ... }`，不要为每种需求建独立状态类。所有需求复用同一套生命周期。
2. **行为状态描述"目的"**（SeekItem / DeliverToFacility / Cry / WaitForPlayer），不是抽象的 Move / Action / Idle。
3. **每个行为状态必须显式声明** `move_mode / anim_base / anim_overlay / action_lock`（见 §4），缺一不可。
4. **非移动动画必须停移动**。`anim_base ∈ {Cry, Pickup, Happy, Sit/Ride, Idle}` 时 `move_mode` 必须是 `Stop`。出现「躺/哭/坐 动画 + 位置仍在变」即 bug。
5. **绝不关闭整个状态机**。不要 `disable AI → play anim → enable AI`。改用 `action_lock`：锁住当前动作、停移动、等动画结束发 `ActionFinished`、当前状态自己推进。停 AI 会导致状态重新 Enter / 计时器归零 / 需求重判——这是历史 bug 根因。

## 3. 本游戏的层映射（落地枚举）

### NeedSystem
沿用现有 `NeedService` / `NeedResolver`。需求分两类：
- `item` —— 玩家把目标物品送到宝宝身边 / 宝宝去捡。
- `facility` —— 玩家抱宝宝到设施处放下触发（含玩家绑定型，如滑板）。

### BehaviorFSM（行为状态，描述目的）
| 状态 | 目的 | 触发来源 |
|------|------|----------|
| Idle | 空闲巡逻 + 扫描就近目标 + 展示需求倒计时 | 初始 / 满足后 / 放下无目标 |
| Carried | 被玩家举着 | `on_lifted_begin` |
| SeekItem | 走向并捡起目标物品（含 reject 分支） | 匹配到地面物品 |
| DeliverToFacility | 在设施处交互（含玩家绑定等待） | 抱着放到设施处 |
| Satisfied | 满足后的开心表现 + 结算事件 | 捡到对的物品 / 设施完成 |
| Upset | 错误物品的不满表现 | reject 完成 / 捡取失败 |
| Cry（原 Timeout） | 需求超时哭闹 + 补救窗口 + 概率拒绝抱起 | 需求倒计时归零 |

### MovementSystem（移动模式）
`Stop` / `Wander`（巡逻随机点）/ `MoveToTarget`（物品或设施）/ `Carried`（被举起，引擎驱动，逻辑不主动移动）。

### AnimationSystem
- `anim_base`：`Idle` / `Locomotion` / `Pickup` / `Cry` / `Happy` / `CarriedPose` / `Ride`。
- `anim_overlay`：情绪叠加（疑惑/嫌弃/开心气泡等），与 base 解耦。
- 动画**事件驱动**：用 `OnAnimFinished(name)` 推进，禁止"每秒重发同一个全身动作"的续命 hack（现 `_refresh_timeout_anim`）。若引擎确实会被待机顶掉，由 AnimationSystem 内部持有"持续播放"语义，而非散落在行为层。

### Presentation
沿用 `BabySceneView` + `BabyViewModel`（气泡）。情绪/状态文案只经 ViewModel 流出。

## 4. 行为状态契约

每个行为状态进入时**必须**给 agent 写全四个意图字段（用默认值兜底，不允许"沿用上一个状态的残留值"）：

```lua
---@class BabyBehaviorIntent
---@field move_mode    "Stop"|"Wander"|"MoveToTarget"|"Carried"
---@field anim_base    string   -- Idle / Locomotion / Pickup / Cry / Happy / CarriedPose / Ride
---@field anim_overlay string|nil
---@field action_lock  boolean  -- true = 当前为不可打断动作，停移动、等 ActionFinished
```

示例（声明式，而非命令式戳 unit）：

```lua
Cry = { move_mode = "Stop",        anim_base = "Cry",     anim_overlay = "Angry", action_lock = true  },
SeekItem = { move_mode = "MoveToTarget", anim_base = "Locomotion", anim_overlay = nil,  action_lock = false },
Carried  = { move_mode = "Carried",      anim_base = "CarriedPose", anim_overlay = nil,  action_lock = false },
```

有多步流程的状态用**内部 phase**推进（Start → WaitingAnimation → Finish），**不要靠关 AI 等动画**。

## 5. ActionLock 规范（合并三套锁）

现有 `timeout_move_locked` / `ride_move_locked` / `movement_hold_locked` 三套各带 token 的锁**合并为一个** `action_lock`（带 reason 便于调试）：

- 进入锁：`Stop movement` + 幂等地 `add_state(BUFF_FORBID_MOVE)`（计数型 buff，必须幂等，避免只移除一次后永久禁动）。
- 解锁：幂等 `remove_state(BUFF_FORBID_MOVE)` + 恢复 move_speed。
- `action_lock = true` 期间：当前状态保持、不切行为、不推进普通移动；只等 `ActionFinished` 或显式事件（抱起/放下/匹配到目标）。
- 锁的生命周期跟随**当前行为状态**，状态 exit 必须解锁——不允许跨状态泄漏。

## 6. 每帧 Update 顺序

引入定频 tick（替代散落的 `call_delay_time + token`，计时器统一由 NeedSystem/状态 phase 持有）：

```
1. NeedSystem:update(dt)          -- 倒计时、超时 → 产出需求事件
2. BehaviorFSM:update(dt)         -- 按 phase 推进；输出 move_mode/anim_base/anim_overlay/action_lock
3. MovementSystem:reconcile()     -- 唯一改位置处；action_lock 时强制 Stop
4. AnimationSystem:reconcile()    -- 唯一播动画处
5. Presentation                   -- ViewModel 已变更则刷新气泡
```

事件（`on_lifted_begin/end`、`AnimFinished`、匹配到目标）走 `BehaviorFSM:handle_event(ev)`，由当前状态决定后果——**动画事件只报时机，逻辑层决定结果**（是否满足需求/是否切状态/是否消耗物品）。

## 7. 验收 Checklist

- [ ] 全文搜索：行为状态/Need 层内无 `start_move_*` / `play_body_anim_*` / `ai_command_*` 直接调用。
- [ ] 三套移动锁已合并为单一 `action_lock`，且每个 exit 都解锁。
- [ ] 每个行为状态进入时四个意图字段全部赋值。
- [ ] 不存在 `disable AI → anim → enable AI` 模式；不存在每秒重发同一全身动作的续命逻辑。
- [ ] 非移动 `anim_base` 对应 `move_mode == "Stop"`。
- [ ] 试玩验证历史两个症状消失：①躺/哭/坐时不再漂移；②抱起/放下不再触发需求刷新或倒计时归零。
