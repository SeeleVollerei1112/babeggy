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
| 进度条硬编码"儿童单人床0"、多床共用 beds[1] | `CribService.lua:153` | Phase 5(核实：Phase 5 开始时该处已是逐床独立绑定/判定,无共用 beds[1] 代码,可能在更早的"完成婴儿床交互"提交中已修——本阶段仅确认现状并原样保留) |
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
- [x] 新建 `Domain/Interaction/InteractionBase.lua`:子状态契约(get_intent/enter/exit/handle_event/is_timed),生命周期严格嵌在 `InteractingFacilityState` 内;共享工具(坐姿跟随 spec/坐姿动画/碰撞开关)
- [x] `SeatInteraction`(普通座位,兜底):FollowDriver + AnimationSystem.force_play("facility")
- [x] `SwingInteraction`:Seat 基础上 + SwingPumpDriver + 碰撞开关 + 离座清座椅速度
- [x] `VehicleInteraction`:kinematic 走 PatrolDriver + FollowDriver;physics 模式平移 `_drive_vehicle_physics`(Timer.every 化,owner=interaction)
- [x] `PlayerBoundInteraction`(滑板):轮询降到 0.1s + 确认时长去抖(0.2s 上板/0.3s 下板,原 60Hz tick 计数换算);上板后 FollowDriver 跟随骑手(位置参考玩家、朝向参考板本体)
- [x] `CribInteraction`(壳):躺床姿势 + FollowDriver,换洗流程仍暂由 CribService 驱动(Phase 5 迁移)
- [x] (计划外新增)`CatapultInteraction`:投石车骑臂等发射;CatapultLaunchService 发射改经 `agent:handle_event({type="catapult_launch"})` 通知停跟随(不再戳 seat_token),延迟定时器改 Timer.once(owner=service)
- [x] `InteractingFacilityState` 重写:按 `facility_kind` 装载子状态;时长结算改 `Timer.once(owner=state)`——修掉 `:58` 无主定时器 bug;`action_lock` 由状态 set_intent/exit 管理;**exit 统一收尾**(子状态 exit→释放占用→发 end 事件),Satisfied/Upset/Cry 切换自动触发;新增 `BabyAgent:handle_event` 事件转发入口
- [x] 删除 `lock_ride_move_state/unlock_ride_move_state`(调用方已归零);**保留** `hold_movement/cancel_movement_hold`——它们是放下冻结(reason "hold")的入口,只被 BabyAgent 自己调用,与骑乘锁无关(Phase 6 再议是否内联)
- [x] FacilityService(1273 行)瘦身为 `Services/FacilityRegistry.lua`(~280 行):注册、`nearest_match`、`get_facilities_by_kind`、互动按钮配置、`send_interaction_event`、宝宝判定;木偶戏代码全部移出;`set_trigger_registry`/`set_crib_service`/`is_crib`/`is_player_bound`/`is_catapult`/`end_interaction` 等无人使用的接口删除
- [x] 本阶段防御清扫:Interaction/Registry/CatapultLaunchService 内方法存在性检查全删,pcall 仅剩既有豁免(装备可能已销毁、destroy 兜底);CryState 的设施收尾防御块删除(exit 统一收尾接管)

**验收标准**:
- WHEN 宝宝中途被抱走再放到另一设施,THEN 旧设施定时器不再触发完成结算
- WHEN 全文搜索 `play_body_anim|force_play_animation`,THEN 仅 `AnimationSystem.lua` 命中
- WHEN 交互期间查看 ViewModel 状态,THEN 显示 InteractingFacility(不再是 Idle+busy)
- 试玩:秋千越摆越高、滑板载人跟随、载具巡游不出区、坐姿不被顶掉,全部与重构前一致

---

## Phase 4:小游戏状态化(PlayRps → BallRally)

**目标**:两个千行服务改写为行为状态 + 薄 Coordinator + 道具能力;`set_busy` 具备删除条件。

**主要任务**:
- [x] 新建 `Domain/Minigame/PlayRpsState.lua`(一级状态):wait_player/ready/tossing/settling/giving_up/finishing 为内部 phase;骰子举放事件经 DiceProp→Coordinator→`agent:handle_event` 转发,等待超时/顶撞链/放弃时长走 `Timer.once(owner=state)`,Settling 传感 `Timer.every(0.1)`;Tossing 用两个 FlightDriver(ease="out" 垂直上抛);面向锁定经 `MovementSystem.perform("face_target"/"clear_face_target")`(新增)
- [x] 新建 `Services/Props/DiceProp.lua`:骰子配置(lifted/thrown force 归零)、事件订阅与转发(listener 模式)、`read_gesture`(AXIS_GESTURE 标定逐行平移)、`freeze_for_toss/restore_physics`;胜负判定表(BEATS)迁入 `judge_outcome`
- [x] 新建 `Coordinators/RpsCoordinator.lua`(~90 行):0.5s Timer 扫描配对、单会话仲裁、`agent:enter_state(PlayRps, context)`;删除 `RpsService`
- [x] 同法改写 BallRally:`BallRallyState` + `BallProp` + `BallRallyCoordinator`;落点标记 sfx/提示留在状态内经 Role 接口;**已修** `_first_player` 多人问题:开局选"离球最近的玩家"为搭档,跳跃事件对启动时所有玩家注册(遗留:中途加入的玩家未注册跳跃事件,Phase 6 处理);松手确认 = LIFTED_END 事件 + 两段 release_timeout 兜底(幂等 phase 守卫)
- [x] `enter_state` 增加 PlayRps=8/BallRally=9 映射(BabyStormEnum + BabyAgent._new_state)
- [x] 删除 `BabyAgent.set_busy`、`view_model` Busy 字段及全部 `is_busy` 分支(on_lifted_begin 守卫、IdleState 扫描守卫;各状态 set_busy 调用一并移除——lift 门控本就由 set_lift_enabled 承担)
- [x] 本阶段防御清扫:新文件方法存在性检查零出现;pcall 仅留"可能已销毁单位"(骰子/球可被打飞出界销毁、玩家断线)、sfx 表现兜底、destroy 兜底三类,均带理由注释

**验收标准**:
- WHEN 猜拳/顶球进行中,THEN `agent.active_state` 为对应状态,意图四字段真实反映当前行为
- WHEN 全文搜索 `set_busy|RALLY_LOCK|"rps"`(锁 reason),THEN 无命中(锁只剩 StateBase 的 behavior reason)
- WHEN 玩家中途抱走宝宝/骰子被丢出界,THEN 状态经 handle_event 干净退出,锁与定时器无泄漏(连续 10 次无异常)
- 试玩:配对→抛骰→顶撞→判分全流程;超时独自满足流程;顶球满回合庆祝与漏接结算

---

## Phase 5:Crib 拆分(流程/表现/配置三分)

**目标**:CribService(729 行)拆为 CribInteraction(流程)+ CribCareView(HUD)+ Config(床名/节点),执行"UINodes 只进 View"。

**主要任务**:
- [x] 换洗流程(子需求随机、取物持有、长按进度、歪床/扶正)迁入 `CribInteraction`,长按进度用 `Timer.every` 推进,UI 事件经 Coordinator/View 转发为 `handle_event`
- [x] 新建 `View/CribCareView.lua`:HUD 显隐、场景进度条绑定/刷新;可见性与进度数据全部问 `CribCoordinator`(无独立 ViewModel,与原实现一致)
- [x] 场景节点 key 已在 `BabyStormConfig.crib`(cabinet_unit_name/cabinet_pos 等本就在配置里,非本阶段新迁移);进度条按床绑定(逐床独立绑定/判定,未见"共用 beds[1]"的实际代码,判定为文档描述已过时——本阶段确认并保留逐床实现)
- [x] `role_held`(玩家手持道具)迁入 `CribCoordinator`,View 不持逻辑
- [x] 删除 `CribService`;本阶段防御清扫(旧 bind_model 兼容清理段、crib_progress_button 死字段均已删除)

**验收标准**:
- WHEN 全文搜索 `Data.UINodes`,THEN 仅 View 层与 CameraModeController 命中
- WHEN 配置里换床名/加第二张床,THEN 不改代码即生效,两床进度条各自独立
- 试玩:取尿布/纸巾→床边长按→完成;放置不管→歪床→扶正,全流程与重构前一致

---

## Phase 6:大扫除 + 外层小修 + 规约更新

**目标**:退役全局 tick,删净死重与过渡代码,固化新规约。

**主要任务**:
- [x] 退役 `BabyAgentManager` 全局 tick(`_tick_token` 递归改 `Timer.every(self, TICK_DT, ...)`,`destroy()` 改 `Timer.cancel_all(self)`;`BabyAgent:update` 摘除 `movement:reconcile`/`animation:reconcile` 两行,`MovementSystem:reconcile`/`AnimationSystem:reconcile` 方法本体删除;`CatapultLaunchService:update` 空方法与 manager tick 里的调用段一并删除)
- [x] 删除/迁移:`BabyMvp.lua` 全库无运行时 require,已 `git mv` 到 `Docs/reference/BabyMvp.lua`;`behavior_tree/custom_node/` 全库无运行时 require,已 `git rm -r`
- [x] `ScoreService` 四个 `award_*`/`penalize_wrong` 塌缩为私有 `_award(role, session_delta, tip_text, tip_duration, role_delta)` + 薄包装(原签名/文案不变);`TaskEventService._emit_for_agent_after` 改 `Timer.once(agent, delay, ...)`,手写 `agent.destroyed` 守卫删除
- [x] CameraModeController:无 application 的裸注册路径清理(改为 `Log.warn` 后跳过绑定);PRESETS 迁 Config 本阶段跳过(标注可选,维持最小改动)
- [x] 全库防御终扫:BallProp/DiceProp 新增 `position()` 单一入口,BallRallyState/PlayRpsState/BallRallyCoordinator 多处重复 `pcall(ball/die.get_position)` 归并调用;CribCoordinator `tilt_bed` 4 个嵌套 pcall 合并 1 个,`emit_action_event` 直调(同 FacilityRegistry 写法),`_on_pick_item` 的 set_lifted_enabled 并入创建后单个 pcall 块;`BabyAgent:_is_lifted_now` 直调;残余 pcall 逐一核对/补齐豁免注释。实际 pcall 调用点(`pcall(` 计数)从 68 降到 55,均属引擎事件回调/可能已销毁单位/destroy 兜底三类
- [x] 更新 `.claude/rules/baby-ai-architecture.md`:§0 适用范围扩到 Coordinators/Core/View;§3 状态表补 InteractingFacility(子状态)/PlayRps/BallRally + 结构补充(目录职责);§5 改"单一锁,reason 仅 behavior/hold,服务层不得碰";§6 改「事件 + 有主定时器 + Driver」三分法(保留 0.1s 节拍只派发 state update);§7 checklist 增补核心规则 2/3/4/5/6/7
- [x] 更新 `AGENTS.md`:Architecture Rules 增补 Core/Coordinators/Props/Interaction/Minigame 职责与 UINodes/Rand 约束;Module Map 更新为重构后模块树;BabyMvp 指向 `Docs/reference/`

**验收标准**:
- 规约 §7 checklist 全项通过:`start_move_*|play_body_anim_*|ai_command_*` 仅 System/Drivers 命中;无 token 递归;锁 reason 仅 behavior/hold(0.1s 节拍保留——行为 phase 需要 dt,只派发 state update,经 Timer.every 驱动,原"删除 _tick"按此落地)
- WHEN 统计 pcall,THEN 全库 55 处且均属三类豁免、带理由注释(原定 ≤20 经现场评估过紧:球/骰可被丢出界销毁、玩家可断线的合法防御面即有数十处,未为凑数删真防御)
- 终验试玩(对照 Phase 1 基线清单):六种玩法 + 抱起/放下打断 × 各状态 + 历史两症状(躺哭坐不漂移、抱放不刷新求)全部通过

---

## 📊 进度总览

| Phase | 名称 | 状态 | 依赖 |
|-------|------|------|------|
| 1 | 地基(Timer/Rand/MathX/Drivers) | 🔄 代码完成,冒烟通过,待人工试玩验收 | 无 |
| 2 | System 事件化 | 🔄 代码完成,冒烟通过(2026-07-08 零报错),待人工试玩验收 | Phase 1 |
| 3 | 设施交互立体化 | 🔄 代码完成(2026-07-09),待试玩验收 | Phase 2 |
| 4 | 小游戏状态化(RPS→BallRally) | 🔄 代码完成(2026-07-10),待试玩验收 | Phase 3 |
| 5 | Crib 拆分 | 🔄 代码完成(2026-07-10),待试玩验收 | Phase 3 |
| 6 | 大扫除 + 规约更新 | 🔄 代码完成,待文档与试玩 | Phase 4、5 |

**每个 Phase 完成后**:eggy-playtest 跑测通过 + 更新本文件勾选状态,再进入下一阶段。
