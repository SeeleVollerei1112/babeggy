# Baby Storm 实现架构说明

## 目标

当前重构的目标是把 MVP 中混在 `BabyMvp.lua` 的职责拆成可扩展层次，让“新增需求、道具、状态、UI、任务事件、难度节奏”都能在局部完成。

## 入口层

- `main.lua`：只监听 `GAME_INIT` / `GAME_END`，转发给 `App.GameApp`。
- `App/GameApp.lua`：应用生命周期，调用 ControllerRegistry。
- `App/ControllerRegistry.lua`：控制器装配顺序表。
- `App/TriggerRegistry.lua`：统一托管 `global/unit` 触发器句柄，销毁时按逆序注销。
- `App/PlayerSessionRegistry.lua`：玩家会话注册表，按 `RoleID` 稳定顺序遍历，记录局内统计。

## BabyStorm 模块

```text
BabyStorm/
  Config/
    BabyStormConfig.lua      数值、prefab、需求、道具、计分、难度
    BabyStormEnum.lua        宝宝状态枚举
  Domain/
    BabyAgent.lua            宝宝领域对象，持有状态机和 ViewModel
    BabyViewModel.lua        宝宝字段通知，不直接调用表现/状态
    GameViewModel.lua        全局局内快照：时间、混乱等级、满足次数、玩家数
    State/                   Idle / Carried / SeekingItem / Satisfied / Upset
  Services/
    ArenaService.lua         场地查询、随机点、落地射线
    NeedService.lua          需求随机袋
    NeedResolver.lua         需求满足规则：道具/设施/区域等匹配策略入口
    ItemService.lua          道具生成、最近道具、拾取归属判定
    ScoreService.lua         加分/扣分/提示
    TaskEventService.lua     任务事件发射
    DifficultyService.lua    混乱等级与后续波次入口
    RoundService.lua         每秒节奏、玩家会话同步、局内时间快照
  View/
    BabySceneView.lua        头顶场景 UI 与 ViewModel 绑定
```

## 生命周期与触发器

`BabyAgentManager` 持有自己的 `TriggerRegistry`。宝宝的抱起/放下事件、道具获得事件都通过 registry 注册；Manager 销毁时先注销触发器，再销毁 Agent 和道具实体。

这样做是为了支持编辑器内反复开始/停止试玩，避免旧回调残留导致重复触发。

## 玩家会话与全局快照

`GameApp` 初始化时创建 `PlayerSessionRegistry` 并暴露给 Controller。BabyStorm 的 `RoundService` 每秒调用 `sessions:sync_all()`，用当前有效玩家刷新会话表。

`ScoreService` 在奖励/惩罚时同步写入玩家 session：

- `satisfied_count`
- `wrong_count`
- `score_awarded`

`GameViewModel` 提供全局局内快照，后续 HUD 可以只绑定它，不需要知道 Manager/Service 细节。

## 状态机

宝宝当前只有一个核心状态：

- `Idle`：显示当前需求，巡逻，可被抱起。
- `Carried`：被玩家抱起，停止移动，记录最后交互玩家。
- `SeekingItem`：放下后发现正确道具，锁定宝宝并命令拾取。
- `Satisfied`：正确完成，发任务事件、加分、延迟刷新下一需求。
- `Upset`：错误道具或失败拾取，增加压力并返回 Idle。

新增状态时：

1. 在 `BabyStorm/Domain/State/` 添加状态文件。
2. 在 `BabyStorm/Config/BabyStormEnum.lua` 加枚举。
3. 在 `BabyAgent:_new_state` 增加映射。

## MVVM 解耦

`BabyViewModel` 只保存字段和广播变化：

- `State`
- `StatusText`
- `NeedId`
- `NeedText`
- `Busy`
- `Stress`

`BabySceneView` 通过 `ViewBinding` 订阅 `StatusText`，刷新头顶 EUI。状态机不直接操作 UI 节点，UI 也不决定状态跳转。

## 需求扩展

新增需求只改 `BabyStormConfig.needs`：

```lua
{
    id = "toy",
    item_key = 123,
    item_name = "玩具",
    action_text = "玩玩具",
    need_text = "想要玩具",
    matched_text = "去玩玩具",
    satisfied_text = "玩到玩具了",
}
```

当前规则已收口在 `NeedResolver`：

- `resolver = "equipment"`：通过 `item_key` 匹配道具。
- 后续可增加 `resolver = "facility"`：通过设施单位、触发区或交互按钮满足需求。
- 后续可增加 `resolver = "recipe"`：通过多个道具合成结果满足需求。

宝宝状态机只接收“是否匹配”的结果，不关心具体规则。

## 验证方式

已完成静态检查：

- require 路径存在性检查。
- 关键方法存在性检查。
- EggyAPI 本地存根事件/枚举名核对。

仍需编辑器连接后验证：

- `.codemaker/editor-cli.exe status`
- `EditorAPI.run_game()`
- 读取 `log.txt` 确认无运行时 require/API 报错。
