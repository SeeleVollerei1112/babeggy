# Baby Storm EggySDK Rebuild Guide

## Original Goal Notes

当前项目是一个多人合作游戏，玩家通过识别宝宝需求，执行对应操作进行安抚，满足宝宝的各种需求。

核心玩法循环：

```text
观察状态 -> 判断需求 -> 移动到指定位置交互 -> 宝宝状态恢复 -> 获得分数奖励 -> 新的需求出现 -> 混乱程度增加，下一轮循环
```

抽象概括：玩家判断角色状态，寻找道具进行互动，将角色转化为平常态。需求随游戏进度/时间增加，场地秩序更加混乱。做错会导致需求熵增，玩家在进行简单交互的同时，还要注意有限时间中的事件处理优先级。

实施重点：

- 需要核心状态机模型来实现状态转变。
- 使用 MVVM 风格把数据变化、状态反应、表现刷新解耦。
- 使用分层架构替代当前 MVP 单文件脚本。

## Goal

Rebuild the current Baby Storm MVP into a clear, extensible EggySDK runtime. The MVP proves the smallest loop: babies express needs, players move them near matching items, babies consume the item, score is awarded, and the next need starts.

The rebuild target is a layered framework, not only feature parity.

## Gameplay Loop

```text
Observe baby state -> infer need -> move baby/item -> match interaction -> satisfy baby -> reward -> new need -> more chaos
```

Players are solving a time-pressure priority problem. The operation is simple, but multiple babies, scattered props, wrong items, and movement friction create the “storm”.

## Architecture Rules

- `main.lua` only wires Eggy lifecycle events into `App.GameApp`.
- `App/` owns lifecycle and controller order, with no gameplay rules.
- `App.TriggerRegistry` owns trigger cleanup; gameplay modules should register events through a registry where possible.
- `App.PlayerSessionRegistry` owns deterministic per-role sessions and ordered traversal.
- `BabyStorm/BabyStormController.lua` binds the module to the app lifecycle.
- `BabyStorm/Config/` owns prefabs, item/need definitions, timing, scoring, and tuning.
- `BabyStorm/Core/` owns concurrency primitives: `Timer` (owned timers, the only timing entry point) and `Drivers/` (continuous-motion drivers: Flight/Follow/SwingPump/Patrol).
- `BabyStorm/Domain/` owns baby agents, the behavior state machine, and ViewModel state.
  - `Domain/State/` top-level behavior states; `Domain/Interaction/` facility-interaction sub-states (nested in `InteractingFacilityState`); `Domain/Minigame/` minigame states (PlayRps/BallRally); `Domain/System/` Movement/Animation/ActionLock/NeedRuntime.
- `BabyStorm/Coordinators/` owns thin coordinators: scan-and-pair, engine-event subscription forwarded to `agent:handle_event`, cross-player resources (UI routing, held items). No flow state, no intents.
- `BabyStorm/Services/` owns stateless EggySDK capabilities: spawning, arena queries, facility registry, scoring, task events; `Services/Props/` owns prop capabilities (dice/ball engine access and physics switches).
- `BabyStorm/View/` owns scene UI and presentation; only View-layer files (and presentation controllers) may require `Data.UINodes`.
- `MVVM/` provides field-change notification. ViewModels do not know who listens to them.
- `Util/` contains small shared helpers only when they remove real duplication; randomness goes through `Util/Rand` only (lockstep determinism).
- `BabyStormDebug.lua` exposes lightweight editor debug entry points for start/stop/snapshot.
- Baby-AI acceptance rules live in `.claude/rules/baby-ai-architecture.md` (intent fields, ActionLock, event + owned-timer + driver concurrency model).

## Extension Points

- Add a new need in `BabyStorm/Config/BabyStormConfig.lua`.
- Add a new need resolver strategy in `BabyStorm.Services.NeedResolver` when the need is not a simple equipment pickup.
- Add a new baby state under `BabyStorm/Domain/State/` and map it in `BabyAgent:_new_state`.
- Add a new task/achievement by subscribing through `TaskEventService`, not by editing state logic.
- Add new UI by binding to `BabyViewModel` fields.
- Add difficulty pacing in `DifficultyService`.

## Current Module Map

```text
main.lua
  -> App.GameApp
     -> App.ControllerRegistry
        -> BabyStorm.BabyStormController
           -> BabyStorm.BabyAgentManager        (0.1s tick via Core.Timer; dispatches state update(dt) only)
              -> App.TriggerRegistry
              -> App.PlayerSessionRegistry
              -> BabyStorm.Domain.GameViewModel
              -> BabyStorm.Domain.BabyAgent
                 -> Domain.System.*             (Movement/Animation/ActionLock/NeedRuntime)
                 -> Domain.State.*              (Idle/Carried/SeekingItem/Satisfied/Upset/Cry)
                 -> Domain.State.InteractingFacilityState
                    -> Domain.Interaction.*     (Seat/Swing/Vehicle/PlayerBound/Catapult/Crib)
                 -> Domain.Minigame.*           (PlayRpsState/BallRallyState)
              -> BabyStorm.Coordinators.*       (Rps/BallRally/Crib; scan-pair + event forwarding)
              -> BabyStorm.Services.*           (FacilityRegistry/Item/Need/Score/TaskEvent/...)
                 -> Services.Props.*            (DiceProp/BallProp)
              -> BabyStorm.Core.*               (Timer, Drivers: Flight/Follow/SwingPump/Patrol)
              -> BabyStorm.View.*               (BabySceneView, CribCareView)
```

The old MVP script lives at `Docs/reference/BabyMvp.lua` as a behavior reference only. Runtime entry goes through `GameApp`.

## Eggy Runtime Notes

- This code runs in the Eggy editor sandbox, not standalone Lua.
- Avoid unordered traversal for gameplay-significant iteration.
- Do not edit auto-exported `Data/*` files.
- Guard nils at Eggy event boundaries, then keep inner domain code simple.
