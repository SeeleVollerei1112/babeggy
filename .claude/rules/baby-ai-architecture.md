# 宝宝 AI 架构规约（BabyStorm）

> 本文件是 BabyStorm 模块 AI 架构的**验收标准**。所有改动以此为准；与此冲突的旧写法一律视为待修。
> 适用范围：`BabyStorm/Domain/**`、`BabyStorm/Services/**`、`BabyStorm/Coordinators/**`、`BabyStorm/Core/**`、`BabyStorm/View/**` 中与宝宝个体行为相关的代码。

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

物品需求可加 `playable = true`（玩具）：宝宝无需求也会随手捡起把玩，**豁免 reject**
（捡到不想要的玩具不 Upset），玩完原地放下且不销毁（`keep_item`，与食物的 `consume` 相对）。
捡到玩具的所有路径统一汇到 `BabyAgent:begin_toy_play`。

### BehaviorFSM（行为状态，描述目的）
| 状态 | 目的 | 触发来源 |
|------|------|----------|
| Idle | 空闲驻留 + 扫描就近目标 + 展示需求倒计时；站够了起身漫游 | 初始 / 满足后 / 放下无目标 |
| Wandering | 漫游一段再回 Idle（走走停停）。继承 IdleState，只覆写 `apply_move_intent` / `schedule_next`；**起身那一刻掷一次骰**决定要不要顺路捡玩具 | Idle 站够 `idle_rest_*` 秒 |
| Carried | 被玩家举着 | `on_lifted_begin` |
| SeekingItem | 走向并捡起目标物品（含 reject 分支） | 匹配到地面物品 |
| PlayingToy | 把玩玩具（原地或拿着走），玩完原地放下 | 捡到 `playable` 物品（随手捡 / 玩具型需求共用） |
| InteractingFacility | 在设施处交互；按 `facility_kind` 装载 Interaction 子状态（Seat/Swing/Vehicle/PlayerBound/Catapult/Crib），子状态可持 Driver | 抱着放到设施处 |
| PlayRps | 猜拳小游戏（配对→抛骰→顶撞→判分），内部 phase 推进 | RpsCoordinator 扫描配对 |
| BallRally | 顶球小游戏（发球→顶回→回合循环），内部 phase 推进 | BallRallyCoordinator 扫描配对 |
| Satisfied | 满足后的开心表现 + 结算事件 | 捡到对的物品 / 设施完成 / 小游戏收尾 |
| Upset | 错误物品的不满表现 | reject 完成 / 捡取失败 / 交互被打断 |
| Cry（原 Timeout） | 需求超时哭闹 + 补救窗口 + 概率拒绝抱起 | 需求倒计时归零 |

### MovementSystem（移动模式）
`Stop` / `Wander`（巡逻随机点）/ `MoveToTarget`（物品或设施）/ `Carried`（被举起，引擎驱动，逻辑不主动移动）。

### AnimationSystem
- `anim_base`：`Idle` / `Locomotion` / `Pickup` / `Cry` / `Happy` / `CarriedPose` / `Ride`。
- `anim_overlay`：情绪叠加（疑惑/嫌弃/开心气泡等），与 base 解耦。
- 禁止**行为层**"每秒重发同一个全身动作"的续命 hack。引擎确实会用待机顶掉全身动作（`play_body_anim` 约 1s 后被顶），"持续播放"语义由 AnimationSystem 内部的续命 Timer 持有，对行为层透明；设施坐姿/骑行/躺床走 `force_play(param, reason)` 外部强制层（优先于意图层，`release(reason)` 配对退场）。

### Presentation
沿用 `BabySceneView` + `BabyViewModel`（气泡）。情绪/状态文案只经 ViewModel 流出。
场景 UI（婴儿床进度条/柜子）在 `View/CribCareView`——`Data.UINodes` 只允许 View 层与表现层控制器 require。

### 结构补充（重构后落地的目录职责）
- `Core/Timer`：唯一定时器入口（once/every/every_frame），owner 必填。
- `Core/Drivers/*`：连续运动驱动（Flight/Follow/SwingPump/Patrol），start/stop 成对，只管位移不管物理开关。
- `Domain/Interaction/*`：设施交互子状态，生命周期严格嵌在 `InteractingFacilityState` 内（get_intent/enter/update/handle_event/exit/is_timed）。
- `Domain/Minigame/*`：小游戏一级行为状态（PlayRps / BallRally）。
- `Coordinators/*`：薄协调器——扫描配对、引擎事件订阅与转发（转 `agent:handle_event`）、跨玩家资源（UI 路由/手持道具/床级歪扶）。不持流程状态、不写意图。
- `Services/Props/*`：道具能力层（骰子/沙滩球）——道具引擎接口与物理开关的唯一入口，无行为决策。

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

## 5. ActionLock 规范（单一锁，reason 引用计数）

全部移动锁统一为 `action_lock`。**reason 只允许两个**：`behavior`（行为状态经 `set_intent{ action_lock = true }` 声明，StateBase:exit 自动释放）与 `hold`（放下冻结，BabyAgent 内部）。服务 / Coordinator / Prop 一律不得 acquire/release。

- 进入锁：停移动 + 幂等地 `add_state(BUFF_FORBID_MOVE)`（计数型 buff，必须幂等，避免只移除一次后永久禁动）；边沿控制——只在"空集 → 非空"时加 buff。
- 解锁：幂等 `remove_state(BUFF_FORBID_MOVE)` + 恢复 move_speed；只在"非空 → 空"时执行。
- 锁定期间 MovementSystem 强制 Stop，不发任何移动指令；确需在锁定期发指令（松手/跳跃/顶撞走位）经 `MovementSystem:perform(action)`——它内部先开 AI 再发，规避「stop_ai 后 ai_command_* 静默失效」的引擎坑。
- 锁的生命周期跟随**当前行为状态**，状态 exit 必须解锁（StateBase 统一做）——不允许跨状态泄漏。

## 6. 并发模型：事件 + 有主定时器 + Driver

禁止散落的 `call_delay_time + token 守卫` 惯用法。三分法：

1. **事件优先**：引擎事件（举放/碰撞/UI）由 Coordinator / Prop 启动时订阅一次，转发 `agent:handle_event(ev)`，由当前状态决定后果——**事件只报时机，逻辑层决定结果**（是否满足需求/是否切状态/是否消耗物品）。
2. **有主定时器**：一切延时/周期走 `Core/Timer`（once/every/every_frame），owner 必填；owner 销毁（`destroyed == true`）或 `Timer.cancel_all(owner)`（状态 exit 由 StateBase 统一做）即失效，回调无需 token 过期守卫。
3. **Driver 隔离**：连续位移（跟随/巡游/飞行/泵力）由 `Core/Drivers` 承担，start/stop 成对，持有方 exit 必须 stop。

保留一个 0.1s 全局节拍（BabyAgentManager 经 `Timer.every` 驱动），**只派发** `active_state:update(dt)`——供确需 dt 累计的行为 phase 使用（扫描间隔、飞行传感、暂停/续跑型倒计时）。Movement/Animation 没有 tick 兜底：意图变更即 `invalidate()` 立即对齐，周期性动作（巡逻换点、动画续命）由各系统内部挂 Timer。

## 7. 验收 Checklist

- [ ] `start_move_*` / `play_body_anim_*` / `ai_command_*` / `stop_ai|start_ai` 直调仅 MovementSystem / AnimationSystem / Core/Drivers 命中。
- [ ] 服务 / Coordinator / Prop 层不写 `agent.move_mode` 等意图字段、不碰 `action_lock`。
- [ ] 每个行为状态（含 Interaction 子状态的 `get_intent`）进入时四个意图字段全部赋值。
- [ ] 非移动 `anim_base` 对应 `move_mode == "Stop"`（Driver 接管位移时用 `Scripted`）。
- [ ] 不存在 `disable AI → anim → enable AI` 模式；不存在行为层的续命重发；不存在无主 `call_delay_time` 与 token 过期守卫。
- [ ] 锁 reason 仅 `behavior` / `hold`；每个状态 exit 自动解锁（StateBase 统一做）。
- [ ] 行为状态不直接订阅引擎事件；订阅在 Coordinator / Prop，经 `agent:handle_event` 转发。
- [ ] `Data.UINodes` 仅 View 层与表现层控制器 require。
- [ ] 随机数仅经 `Util/Rand` 一个入口、一个源（帧同步确定性）。
- [ ] pcall 仅三类豁免且带理由注释：引擎事件回调最外层、可能已销毁单位（球/骰被丢出界、玩家断线）、destroy 兜底；方法存在性检查（`if x.foo then`）不作为防御手段。
- [ ] 试玩验证历史两个症状消失：①躺/哭/坐时不再漂移；②抱起/放下不再触发需求刷新或倒计时归零。
