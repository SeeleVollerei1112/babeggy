# 开发计划:BabyStorm 全代码库重构

> 创建时间:2026-07-06 | 范围:系统级(全库重构) | 粒度:Phase 阶段
> 诊断依据:2026-07-06 会话全库通读(四大服务逐行 + Domain 全部 + 外层全部)

## 概述

把"状态机被服务架空"的结构病治掉:小游戏流程回归行为状态层(两层 HFSM),服务层退回无状态能力,
并发模型统一为「事件为主 + 有主定时器 + Driver 隔离」,替代现有的 全局tick / token递归 / 事件 三套并存。

**核心规则(重构全程有效):**

1. 逻辑代码基本是对的,坏的是结构——**运动学/物理/引擎 workaround 代码原样平移,不重写**。
2. 服务层不得写 `agent.move_mode` 等意图字段、不得碰 `action_lock`、不得直调 `ai_command_* / start_move_* / play_body_anim_*`。
3. 每个定时器必须有 owner,owner 销毁/状态 exit 即取消(消灭无主 `call_delay_time`)。
4. 行为状态不直接订阅引擎事件;道具/Coordinator 启动时订阅一次,转发给 `agent:handle_event()`。
5. `Data.UINodes` 只允许 View 层与表现层控制器 require。
6. 随机数只走 `Util/Rand` 一个入口、一个源(帧同步确定性)。
7. 防御规则:方法存在性检查全删;pcall 只留三处——引擎事件回调最外层、可能已销毁单位的调用、destroy 兜底。

**不动区(明确禁止顺手改):** `App/` 全部、`MVVM/` 全部、`ItemService`、`NeedService`、`NeedResolver`、
`ArenaService`(除随机数收编)、`RoundService`、`DifficultyService`、`Data/*`(自动导出)。

**保留区(来之不易的引擎经验,只许平移):**
- BallRally 运动学弧线(`_begin_kinematic_flight`/`_drive_ball_kinematic`,含"绝不给引擎初速度"注释)
- RPS 骰子读面(`_read_die_gesture` 轴→手势标定)、垂直抛掷、落地静止判定(逐骰射线地面参考)
- FacilityService 座位跟随/秋千泵力/载具运动学巡游的数学与注释
- AnimationSystem 的 force_play vs play_body_anim 顶掉规律、ActionLock 的 BUFF 幂等边沿逻辑

**已知逻辑 bug(修复归属见各 Phase):**

| Bug | 位置 | 修复 Phase |
|-----|------|-----------|
| 无主定时器完成旧设施交互 | `InteractingFacilityState.lua:58` | Phase 3 |
| 进度条硬编码"儿童单人床0"、多床共用 beds[1] | `CribService.lua:153` | Phase 5 |
| 随机数 5 处副本、双随机源混用 | Rps/BallRally/Arena/Facility | Phase 1 |
| 顶球只认第一个玩家(1P 跳跃/提示) | `BallRallyService._first_player` | Phase 4(至少记录,可选修) |
| CameraModeController 无 app 时裸注册不清理 | `CameraModeController.init` | Phase 6 |

---

## Phase 1:地基(纯新增 + 机械替换,行为零变化)

**目标**:并发原语与公共工具就位,五处随机数副本收编;不改任何流程。

**主要任务**:
- [x] 新建 `BabyStorm/Core/Timer.lua`:`Timer.once(owner, delay, fn)` / `Timer.every(owner, interval, fn)` / `Timer.cancel(handle)` / `Timer.cancel_all(owner)`;`every` 基于 `{ EVENT.REPEAT_TIMEOUT, interval }`(RoundService 已验证),`once` 基于 `call_delay_time` + owner 存活检查(另加 `every_frame`,仅供 Drivers)
- [x] 新建 `Util/Rand.lua`:`Rand.int(min,max)` / `Rand.fixed(min,max)` / `Rand.signed()` / `Rand.index(n)`,随机源统一为 GameAPI.random_int;`RandomBag` 改用它
- [x] 收编随机实现(实际七处):`RpsService._rand_signed/_random_range`、`BallRallyService.random_fixed`、`ArenaService.random_fixed`、`FacilityService._random_duration`、`BabyAgent._random_seconds`、`BabyAgent.should_reject_timeout_lift` 内联掷骰
- [x] 新建 `Util/MathX.lua`:`clamp` / `lerp` / `wrap_angle` / `approach_angle` / `ease_out_in` / `ease_out` / `to_vector3` / `to_quaternion`(从 BallRally/FacilityService 平移),原地替换调用点
- [x] 新建 `BabyStorm/Core/Drivers/`:`FlightDriver`(合并 BallRally 弧线 + RPS 垂直抛,参数化)、`FollowDriver`(合并 `_sync_seat` + `_snap_baby_to_rider`)、`SwingPumpDriver`、`PatrolDriver`(载具运动学巡游);均实现 `start/stop`,内部用 Timer,数学从原文件平移。**本阶段只建不接**,原调用路径不动

**验收标准**:
- WHEN 全文搜索 `random_fixed|_rand_signed|_random_range`,THEN 仅 `Util/Rand.lua` 命中
- WHEN 试玩跑一轮(喂食/秋千/滑板/猜拳/顶球/婴儿床各一次),THEN 行为与重构前一致、log 无报错
- Driver 单独可实例化,`stop()` 后不再产生任何定时器回调

---

## Phase 2:System 事件化(Movement/Animation/ActionLock)

**目标**:AI 开关所有权归一,`ensure_ai` 具备删除条件;意图词汇表补齐,反 reconcile 轮询。

**主要任务**:
- [x] MovementSystem:`Wander` 参数化(`{anchor, radius, speed_ratio, interval, threshold}`),覆盖原地驻留(speed=0)、配对小步挪动、give_up 闲逛三种用法(RPS 两处自驱移动循环已删,改写 Wander 意图)
- [x] MovementSystem:新增 `Scripted` 模式(仅枚举+空处理,Phase 3/4 接 Driver);暴露 `perform(action)` 语义接口(release_lift/jump/directional_move/stop_move),内部处理 AI 开关;ActionLock 停步改经 BabyAgent 注入的回调转发,start_ai/stop_ai 全库仅 MovementSystem
- [x] AnimationSystem:暴露 `force_play(param, reason)` / `release(reason)`(外部强制层,优先于意图层),续命定时器改 `Timer.every`(owner=system);FacilityService 坐姿/骑行 4 处动画直调收编
- [x] Movement/Animation 的 reconcile 改为 `invalidate()` 时立即执行 + 各自内部按需挂 Timer(Wander 换点、动画续命、取物速度重申);`BabyAgent:update` 中的每帧 reconcile 调用保留但变为空转兜底(Phase 6 删 tick 时一并摘除)
- [x] NeedRuntime 改 1s `Timer.every`(owner=runtime),产出 on_tick/on_timeout 回调,`BabyAgent:update` 对应段落下线;放下冻结(hold)同步改 `Timer.once`
- [x] 删除 `RpsService.ensure_ai`(RPS 未重写前,先让其走 MovementSystem.perform 过渡);独自满足松手后加 Finishing 隔一拍收尾(invalidate 即时化后,同帧 stop_ai 会作废松手指令)
- [x] (超纲收编,已裁决)StateBase:exit 统一 `Timer.cancel_all(self)`;Upset/Satisfied 的无主 call_delay_time 改 `Timer.once(owner=state)`,过期守卫删除

**验收标准**:
- WHEN 全文搜索 `stop_ai|start_ai`,THEN 仅 `MovementSystem.lua` 命中
- WHEN 宝宝在锁定期间被要求 lift/jump,THEN 指令经 `perform` 生效,无需调用方先开 AI
- 试玩:巡逻/捡物/被抱/哭闹表现不变;哭闹动画不被待机顶掉

---

## Phase 3:设施交互立体化(InteractingFacility → 子状态)

**目标**:FacilityService(1260 行)拆为 FacilityRegistry(~300 行)+ 五个 Interaction 子状态;修掉无主定时器 bug。

**主要任务**:
- [ ] 新建 `Domain/Interaction/InteractionBase.lua`:子状态契约(enter/exit/handle_event/set_intent 复用 StateBase 语义),生命周期严格嵌在 `InteractingFacilityState` 内
- [ ] `SeatInteraction`(普通座位):FollowDriver + AnimationSystem.force_play(Seat)
- [ ] `SwingInteraction`:Seat 基础上 + SwingPumpDriver + 碰撞开关
- [ ] `VehicleInteraction`:kinematic 走 PatrolDriver + FollowDriver;physics 模式平移 `_drive_vehicle_physics`(Timer 化)
- [ ] `PlayerBoundInteraction`(滑板):上/下板去抖用事件+确认定时器结构平移轮询逻辑;FollowDriver 跟随骑手
- [ ] `CribInteraction`(壳):躺床姿势 + FollowDriver,换洗流程仍暂由 CribService 驱动(Phase 5 迁移)
- [ ] `InteractingFacilityState` 重写:按 `facility_kind` 装载子状态;时长结算改 `Timer.once(owner=state)`——修掉 `:58` 无主定时器 bug;`action_lock` 由状态 enter/exit 管理,删除 `lock_ride_move_state/unlock_ride_move_state/hold_movement/cancel_movement_hold` 包装
- [ ] FacilityService 瘦身为 `Services/FacilityRegistry.lua`:注册、`nearest_match`、`get_facilities_by_kind`、互动按钮配置、custom event 发送;木偶戏代码全部移出
- [ ] 本阶段防御清扫:涉及文件按核心规则 7 执行

**验收标准**:
- WHEN 宝宝中途被抱走再放到另一设施,THEN 旧设施定时器不再触发完成结算
- WHEN 全文搜索 `play_body_anim|force_play_animation`,THEN 仅 `AnimationSystem.lua` 命中
- WHEN 交互期间查看 ViewModel 状态,THEN 显示 InteractingFacility(不再是 Idle+busy)
- 试玩:秋千越摆越高、滑板载人跟随、载具巡游不出区、坐姿不被顶掉,全部与重构前一致

---

## Phase 4:小游戏状态化(PlayRps → BallRally)

**目标**:两个千行服务改写为行为状态 + 薄 Coordinator + 道具能力;`set_busy` 具备删除条件。

**主要任务**:
- [ ] 新建 `Domain/Minigame/PlayRpsState.lua`(一级状态):WaitPlayer/Ready/Tossing/Settling/GivingUp 为内部 phase;事件驱动(骰子举放事件 + 确认/超时 Timer),Tossing 用 FlightDriver,Settling 用低频传感 Timer + 顶撞一次性 Timer 链,GivingUp 用 Wander{anchor} 意图
- [ ] 新建 `Services/Props/DiceProp.lua`:骰子配置(lifted/thrown force)、事件订阅与转发、`read_gesture`、`restore_physics`;胜负判定表(BEATS)随之迁入
- [ ] 新建 `Coordinators/RpsCoordinator.lua`(~100 行):0.5s 扫描配对(经 NeedResolver 类型查表)、仲裁、`agent:enter_state(PlayRps, context)`;删除 `RpsService`
- [ ] 同法改写 BallRally:`BallRallyState` + `BallProp` + `BallRallyCoordinator`;落点标记/提示留在状态内经 Role 接口;修或记录 `_first_player` 多人问题(至少:提示与跳跃窗口对"最近玩家"生效)
- [ ] `enter_state` 增加 PlayRps/BallRally 映射;需求匹配统一走 resolver 类型 → 状态查表
- [ ] 删除 `BabyAgent.set_busy` 及 `view_model:is_busy` 分支(状态机不再需要被压制)
- [ ] 本阶段防御清扫

**验收标准**:
- WHEN 猜拳/顶球进行中,THEN `agent.active_state` 为对应状态,意图四字段真实反映当前行为
- WHEN 全文搜索 `set_busy|RALLY_LOCK|"rps"`(锁 reason),THEN 无命中(锁只剩 StateBase 的 behavior reason)
- WHEN 玩家中途抱走宝宝/骰子被丢出界,THEN 状态经 handle_event 干净退出,锁与定时器无泄漏(连续 10 次无异常)
- 试玩:配对→抛骰→顶撞→判分全流程;超时独自满足流程;顶球满回合庆祝与漏接结算

---

## Phase 5:Crib 拆分(流程/表现/配置三分)

**目标**:CribService(729 行)拆为 CribInteraction(流程)+ CribCareView(HUD)+ Config(床名/节点),执行"UINodes 只进 View"。

**主要任务**:
- [ ] 换洗流程(子需求随机、取物持有、长按进度、歪床/扶正)迁入 `CribInteraction`,长按进度用 `Timer.every` 推进,UI 事件经 Coordinator/View 转发为 `handle_event`
- [ ] 新建 `View/CribCareView.lua`:HUD 显隐、场景进度条绑定/刷新,绑定 CribViewModel(进度、可用动作、子需求文案)
- [ ] 硬编码 `"儿童单人床0"` 与场景节点 key 迁入 `BabyStormConfig.crib`;进度条按床绑定(修多床共用 beds[1] 问题)
- [ ] `role_held`(玩家手持道具)归入 CribCoordinator 或 PlayerSessionRegistry 扩展字段,View 不持逻辑
- [ ] 删除 `CribService`;本阶段防御清扫

**验收标准**:
- WHEN 全文搜索 `Data.UINodes`,THEN 仅 View 层与 CameraModeController 命中
- WHEN 配置里换床名/加第二张床,THEN 不改代码即生效,两床进度条各自独立
- 试玩:取尿布/纸巾→床边长按→完成;放置不管→歪床→扶正,全流程与重构前一致

---

## Phase 6:大扫除 + 外层小修 + 规约更新

**目标**:退役全局 tick,删净死重与过渡代码,固化新规约。

**主要任务**:
- [ ] 退役 `BabyAgentManager` 全局 tick(确认无人依赖 `update(dt)` 后删除 `_tick`;`BabyAgent:update` 摘除)
- [ ] 删除:`BabyMvp.lua`(或移 `Docs/reference/`)、`behavior_tree/custom_node/` 示例(若不用 BT)、Phase 2-5 遗留的过渡兜底
- [ ] `ScoreService` 三个 `award_*` 塌缩为 `award(role, amount, label)` + 薄包装;`TaskEventService._emit_for_agent_after` 改 Timer
- [ ] CameraModeController:无 application 的裸注册路径清理;PRESETS 迁 Config(可选)
- [ ] 全库防御终扫:pcall 只余三类豁免,复查 30~60Hz 路径无每帧闭包分配
- [ ] 更新 `.claude/rules/baby-ai-architecture.md`:§6 tick 模型改为「事件 + 有主定时器 + Driver」三分法;checklist 增补核心规则 2/3/4/5/6;§7 加"服务层不写意图字段、不碰 action_lock"
- [ ] 更新 `AGENTS.md` 模块地图(Core/Interaction/Minigame/Coordinators/Props 目录)

**验收标准**:
- 规约 §7 checklist 全项通过:`start_move_*|play_body_anim_*|ai_command_*` 仅 System/Drivers 命中;无 tick;无 token 递归;锁 reason 唯一
- WHEN 统计 pcall,THEN 全库 ≤ 20 处且均属三类豁免
- 终验试玩(对照 Phase 1 基线清单):六种玩法 + 抱起/放下打断 × 各状态 + 历史两症状(躺哭坐不漂移、抱放不刷新求)全部通过

---

## 📊 进度总览

| Phase | 名称 | 状态 | 依赖 |
|-------|------|------|------|
| 1 | 地基(Timer/Rand/MathX/Drivers) | 🔄 代码完成,冒烟通过,待人工试玩验收 | 无 |
| 2 | System 事件化 | 🔄 代码完成,冒烟通过(2026-07-08 零报错),待人工试玩验收 | Phase 1 |
| 3 | 设施交互立体化 | ⬜ 未开始 | Phase 2 |
| 4 | 小游戏状态化(RPS→BallRally) | ⬜ 未开始 | Phase 3 |
| 5 | Crib 拆分 | ⬜ 未开始 | Phase 3 |
| 6 | 大扫除 + 规约更新 | ⬜ 未开始 | Phase 4、5 |

**每个 Phase 完成后**:eggy-playtest 跑测通过 + 更新本文件勾选状态,再进入下一阶段。
