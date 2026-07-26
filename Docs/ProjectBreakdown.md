# 《宝宝模拟器 / Baby Storm》项目拆解

> 分析基准：2026-06-29 当前工作区。本文解释的是当前代码实际行为，而不是只复述旧设计文档。

## 1. 先给结论

这是一个运行在蛋仔派对帧同步编辑器中的多人合作玩法原型。玩家观察宝宝头顶需求，把正确物品送到宝宝身边，或把宝宝抱到正确设施旁；成功后加分并刷新需求，失败会进入不满，拖延则进入哭闹。

当前真正的运行入口是：

```text
main.lua
  -> App.GameApp
    -> App.ControllerRegistry
      -> BabyStorm.BabyStormController
        -> BabyStorm.BabyAgentManager
          -> 创建服务
          -> 创建 3 个 BabyAgent
          -> 启动每 0.1 秒一次的统一 tick
          -> 启动每 1 秒一次的回合计时
```

`BabyMvp.lua` 是重构前的单文件版本，当前入口没有加载它。它是行为参考，不会与 `BabyStorm/` 同时运行。

项目的核心设计不是传统 ECS，而是：

- `App` 管整个应用的开始和停止。
- `BabyAgentManager` 组装一个玩法模块。
- 每个 `BabyAgent` 代表一个宝宝，内部有状态机、需求计时、移动、动画和 ViewModel。
- `Services` 封装会影响游戏世界的 EggySDK 操作。
- `State` 只决定“宝宝现在想做什么”，再把意图交给执行系统。
- `ViewModel + ViewBinding + BabySceneView` 把状态文案送到宝宝头顶气泡。

## 2. 运行环境与重要约束

这不是标准 Lua 命令行项目。它依赖编辑器注入的 `GameAPI`、`LuaAPI`、`GlobalAPI`、`EVENT` 和 `Enums`。

- 帧同步逻辑必须保持确定性；随机数优先使用 `LuaAPI.rand()` 或平台的同步随机接口。
- 数值有 `integer` 与 `Fixed` 的区别，定时器间隔等参数常需写成 `1.0` 而不是 `1`。
- 平台对象的方法以 `unit.get_position()` 形式调用，不使用标准 Lua 的 `unit:get_position()`。
- 运行环境没有完整的 `io/os/debug` 标准库。
- `Data/*` 是编辑器自动导出的资源表，不应手改。
- 游戏对象、触发器和延迟回调有跨试玩残留风险，所以代码大量使用注册表、`started`、`destroyed` 和 token 做生命周期保护。

`EggyAPI.lua` 与 `EggyEditorAPI.lua` 都只是 IDE 类型声明和 API 字典，不是业务实现。前者描述试玩期 API，后者描述编辑期 API。

## 3. 四条最重要的数据流

### 3.1 启动与停止

```text
EVENT.GAME_INIT
  -> GameApp.init
  -> 同步玩家会话
  -> ControllerRegistry 顺序初始化控制器
  -> BabyStormController 创建并启动 Manager

EVENT.GAME_END
  -> GameApp.destroy
  -> ControllerRegistry 逆序销毁控制器
  -> Manager 停 tick、注销触发器、销毁宝宝/道具/设施状态
  -> GameApp 清空公共触发器和玩家会话
```

逆序销毁是为了按依赖的反方向拆卸。`main.lua` 自己注册的 `GAME_INIT/GAME_END` 属于整个脚本生命周期，不放进 `TriggerRegistry`。

### 3.2 每个宝宝的 tick

`BabyAgentManager` 用 `LuaAPI.call_delay_time(0.1, ...)` 形成统一循环。每个宝宝依次执行：

```text
NeedRuntime:update(dt)
  -> 超时则进入 Cry
  -> 跨整秒则刷新倒计时文案

BabyAgent:_update_hold(dt)
  -> 处理放下后的短暂移动锁

active_state:update(dt)
  -> 推进当前行为状态的 phase

MovementSystem:reconcile(dt)
  -> 把 move_mode 变成引擎移动命令

AnimationSystem:reconcile(dt)
  -> 把 anim_base/anim_param 变成引擎动画命令
```

这是工程最重要的边界：状态层写意图，执行系统把意图落到引擎。

### 3.3 正确物品流程

有两种交付方式：玩家把宝宝放到物品旁，或把物品放到空闲宝宝旁。

```text
发现当前需求对应的地面物品
  -> SeekingItemState
  -> MovementSystem 下发拾取命令
  -> 拾取事件或距离兜底确认归属
  -> BabyAgent.complete_item_obtained（item.done 保证幂等）
  -> SatisfiedState
  -> 发任务事件、加分、提高 satisfied_count/chaos_level
  -> 延迟销毁并补生成同类物品
  -> 选择下一需求
  -> IdleState
```

### 3.4 设施与超时流程

设施需求必须由玩家抱宝宝到设施附近并放下，空闲扫描不会自动触发设施。

```text
Carried -> 放到匹配设施旁
  -> InteractingFacilityState
  -> FacilityService.begin_interaction
  -> 秋千：按帧把宝宝同步到座位
     或滑板：按配置选择 kinematic / physics / player_bound
  -> 完成交互
  -> SatisfiedState
```

需求倒计时归零则进入 `CryState`。地面哭闹时会锁移动、持续播放哭闹动作，但仍允许把正确物品送过来补救；被抱起时改用引擎的携带姿势。哭闹窗口结束仍未满足，就放弃旧需求并抽取新需求。

## 4. 状态机

| 状态 | 进入原因 | 主要行为 | 常见出口 |
| --- | --- | --- | --- |
| `Idle` | 初始化、满足结束、普通放下 | 展示需求倒计时；每 0.5 秒扫描附近正确物品 | `Carried`、`SeekingItem`、`Cry` |
| `Carried` | 玩家举起宝宝 | 记录玩家；停止自主移动；发送举起任务事件 | 放下后进入 `SeekingItem`、`InteractingFacility` 或 `Idle` |
| `SeekingItem` | 匹配到物品，或放到错误物品旁 | 走向物品、等待拾取、距离内强制拾取兜底 | `Satisfied` 或 `Upset` |
| `InteractingFacility` | 放到匹配设施旁 | 启动设施交互；取消需求倒计时 | `Satisfied` 或设施忙时 `Upset` |
| `Satisfied` | 正确物品已拾取或设施完成 | 加分、发任务事件、开心反馈、延迟收尾 | `Idle` |
| `Upset` | 错误物品、拾取失败、设施不可用 | 压力 +1、错误提示、可选扣分 | 1 秒后 `Idle` |
| `Cry` | 需求超时 | 哭闹倒计时、补救匹配、概率拒绝抱起 | 补救成功进入目标状态；否则换需求后回 `Idle/Carried` |

状态实例按需创建并缓存于 `BabyAgent.states`。每次切换时先 `exit` 旧状态，再更新 ViewModel 的状态字段，最后 `enter` 新状态。

## 5. 目录和文件职责

### 5.1 根目录

#### `main.lua`

唯一正式入口。只注册 `GAME_INIT` 与 `GAME_END`，把生命周期转给 `GameApp`。它刻意不含玩法规则。

#### `BaseClass.lua`

项目自带的轻量类系统：

- `Class("Name", Super)` 创建类表。
- `New(...)` 建实例、挂元表、调用 `Ctor`。
- 支持单继承和简单多继承查找。
- `super` 指向第一个父类。

它让项目可以写 `BabyAgent.New()`、`StateBase` 继承等面向对象形式。这里的冒号用于项目自定义 Lua 方法；平台对象仍使用点调用。

#### `BabyMvp.lua`

旧版单文件原型，把区域查询、需求随机袋、宝宝生成、物品生成、抱起事件、拾取、UI、任务事件和计分全部写在一起。它证明了最小玩法闭环，但存在职责混杂、定时回调分散、触发器难统一清理等问题，因此被拆成当前分层结构。当前未被 `main.lua` 引用。

#### `BabyStormDebug.lua`

编辑器插件入口，暴露三个按钮式能力：启动模块、停止模块、打印 Manager 快照。它绕过 `GameApp` 直接调用 `BabyStormController`，适合编辑器局部调试，不是正式启动路径。

#### `DebugTools.lua`

通用编辑器调试插件示例。`SetPosition` 传送指定玩家；`SetRoleGameResult` 让指定玩家胜利或失败。它不参与 BabyStorm 运行。

#### `EggyAPI.lua`

试玩期 API 的自动生成 LuaDoc 声明，当前约 1279 个函数、55 个类。业务代码借它获得类型提示和 API 签名；文件本身的方法体为空。不要把它当成 SDK 的本地实现。

#### `EggyEditorAPI.lua`

编辑期 `EditorAPI` 的自动生成声明，当前约 184 个函数。用于场景/EUI 编辑自动化，不参与试玩逻辑。

#### `eggy.json`

工程同步配置：项目名、项目 ID、编辑器服务端口、同步开关、排除目录和版本。`serverPort=58124` 是工程同步服务，不是 VS Code Lua 调试端口。

#### `AGENT.md`

面向代码代理/开发者的工程规则和目标说明，规定分层、扩展点和编辑器验证方式。它是开发文档，不会被 Lua 运行时加载。

#### `log.txt`

编辑器试玩输出，已被 `.gitignore` 忽略。它是运行产物，不是源码；排错时读取，平时不应提交。

### 5.2 `App/`：应用生命周期层

#### `App/GameApp.lua`

保存单例 `application`：`started`、公共 `TriggerRegistry`、`PlayerSessionRegistry` 以及注册触发器的包装函数。`init` 防重复启动，先同步玩家再初始化控制器；`destroy` 销毁控制器并重新创建干净的注册表和会话表。

#### `App/ControllerRegistry.lua`

控制器装配表。当前只装配 `BabyStormController`。初始化按正序，销毁按逆序；以后增加新玩法模块或 HUD 控制器时在这里登记。

#### `App/PlayerSessionRegistry.lua`

以 `RoleID` 为键保存局内玩家会话，记录满足次数、错误次数、累计计分。另维护排序后的 RoleID 数组，避免 `pairs` 的非确定遍历影响帧同步。`sync_all` 同步加入/离开的有效玩家。

#### `App/TriggerRegistry.lua`

统一包装全局和单位触发器注册，保存句柄及其所属单位；销毁时逆序注销。注销使用 `pcall`，避免某个已失效对象阻断其余清理。

### 5.3 `BabyStorm/` 顶层：玩法模块装配

#### `BabyStorm/BabyStormController.lua`

把 BabyStorm 接入 App 控制器协议。它持有唯一 Manager：`init` 幂等创建，启动失败则丢弃；`destroy` 清理并置空；`get_manager` 供调试读取。

#### `BabyStorm/BabyAgentManager.lua`

整个玩法的组合根，负责：

- 按依赖顺序创建 Arena、Need、Resolver、Item、Facility、Score、Task、Difficulty、Round、View。
- 把服务集合注入每个 BabyAgent。
- 生成配置数量的宝宝，并注册抱起/放下事件。
- 接收物品获得事件，找到对应宝宝，再按需求判断对错。
- 每 0.1 秒统一更新全部宝宝。
- 销毁时停回合、失效 tick token、注销事件、销毁实体和绑定。

Manager 不实现具体状态行为；它解决的是对象组装、跨 Agent 路由和生命周期。

### 5.4 `BabyStorm/Config/`

#### `BabyStormConfig.lua`

唯一主要调参入口，包含：

- 场地区域和落地射线距离。
- 宝宝数量、移动/扫描/拾取/超时/反馈参数。
- 成功分数与错误惩罚。
- 回合时长。
- 混乱等级增长阈值。
- 三个装备需求：奶昔、冰淇淋、蛋糕。
- 两个设施需求：秋千、滑板。

资源 ID 优先读 `Data.Prefab`，同时保留硬编码 fallback。当前滑板实际配置为 `vehicle_drive_mode="kinematic"`；`player_bound` 注释描述的是另一种模式，不是当前运行路径。

#### `BabyStormEnum.lua`

定义核心状态 ID 到名字的映射，以及 `get_state_name` 调试转换。`BabyStateLayer.Core` 当前没有实际消费者，是预留概念。

### 5.5 `BabyStorm/Domain/`：宝宝领域层

#### `BabyAgent.lua`

单个宝宝的中心协调对象。它拥有单位引用、当前需求、最近交互玩家、ViewModel、状态缓存和四个子系统。重要职责是：

- 初始化宝宝单位能力。
- 串联统一 tick。
- 管理状态切换。
- 处理抱起/放下边界事件。
- 在物品与设施之间路由需求匹配。
- 对拾取和设施完成做幂等结算。
- 管理需求超时、放下冻结、骑乘锁和哭闹拒抱。

它不应成为第二个 Manager；跨宝宝行为应放在 Manager/Service，单宝宝生命周期才放这里。

#### `BabyIntent.lua`

定义状态层与执行系统之间的协议：移动模式、基础动画、情绪 overlay。它是常量表，不保存运行状态。

#### `BabyViewModel.lua`

保存单宝宝的可观察字段：状态、状态文案、需求 ID、需求文案、忙碌、压力。Setter 通过 `ViewModelBase` 只在值变化时广播；`set_need` 批量更新两个相关字段。

#### `GameViewModel.lua`

保存全局局内快照：已过时间、剩余时间、混乱等级、满足总数、宝宝数、玩家数。目前服务会更新这些值，但尚无 HUD/View 订阅它。

### 5.6 `BabyStorm/Domain/State/`：行为状态

#### `StateBase.lua`

状态共同协议：`enter/update/handle_event/exit`、状态 ID、活跃标记和 `phase`。`set_intent` 一次写入移动、动画、overlay 和行为锁，并强制执行系统下次重新对账。退出会释放 `behavior` 原因的动作锁，防止锁跨状态泄漏。

#### `IdleState.lua`

显示当前需求，允许抱起，以无参数 `Wander` 意图运行漫游功能引入前的场地随机点巡逻，并按配置间隔扫描附近正确地面物品。需要停步的特殊行为临时覆盖移动意图，回到 Idle 后自动恢复旧版巡逻；玩具和小游戏的局部走走停停使用带参数 `Wander`，两条路径互不改写。

#### `CarriedState.lua`

记录举起单位和对应玩家，设置忙碌，改为 `Carried` 移动模式与携带姿势，并发送任务事件。`suppress_lift_event` 用于哭闹结束后仍被抱着的状态恢复，避免重复计任务。

#### `SeekingItemState.lua`

保存 `seeking` phase，设置目标物品并让 MovementSystem 发拾取命令。每隔一段时间检查物品归属；足够近时强制换入装备槽；超时则进入 Upset。错误物品也复用这个状态，但 `pending_purpose="reject"`。

#### `InteractingFacilityState.lua`

锁定宝宝可抱状态，发送设施交付事件，调用 FacilityService 开始互动。互动开始后取消需求耐心计时，避免 20～60 秒的设施过程被 20～30 秒需求超时打断。玩家绑定模式不设固定结束延迟，而等 FacilityService 判定下板。

#### `SatisfiedState.lua`

执行正确结算：停止移动、开心 overlay、显示成功文案、加分、推进难度、分阶段发满意/分类/开心任务事件。等待足够长的表现窗口后再清物品或结束设施并抽取新需求。

#### `UpsetState.lua`

错误反馈：忙碌、停步、Angry overlay、压力 +1、发送错误任务事件、执行可配置扣分；1 秒后返回 Idle，旧需求不变。

#### `CryState.lua`

需求超时行为。地面状态使用行为锁和持续哭闹动画；抱起时切换为携带姿势；放下恢复哭闹。期间仍扫描正确物品作为补救。哭闹计时结束后换新需求，并根据是否仍被抱着回到 Carried 或 Idle。

### 5.7 `BabyStorm/Domain/System/`：执行与运行时子系统

#### `NeedRuntime.lua`

纯计时状态，不自行调度回调。接收 `dt`，累计跨整秒后减少剩余时间，并返回 `{ticked, timed_out}`。把需求倒计时统一进 Agent tick，避免散落的延迟回调。

#### `ActionLock.lua`

按 reason 维护幂等锁集合。第一个锁加入时加 `BUFF_FORBID_MOVE`、停 AI、速度归零；最后一个锁释放时移除 Buff 并恢复速度。当前 reason 包括 `behavior`、`hold`、`ride`。

#### `MovementSystem.lua`

把 `Stop/Wander/MoveToTarget/PickupTarget/Carried` 意图翻译为引擎移动调用。ActionLock 优先级最高。它缓存上次模式，只在模式切换时执行入口动作；Pickup 模式每帧重申速度，避免解锁后被恢复为 1.0。

#### `AnimationSystem.lua`

管理需要强制播放的 Cry/Ride/Seat 动画，缓存上次基础动画和参数。由于 `play_body_anim_by_id` 可能约 1 秒后被待机顶掉，它把“每秒续播”的平台兼容逻辑集中在这里；离开强制动画时精确停止旧动作。

### 5.8 `BabyStorm/Services/`：平台副作用与跨领域能力

#### `ArenaService.lua`

查询主触发区、生成区域随机点，并尝试用障碍物射线把随机点贴到最高地面。区域不存在时 Manager 启动失败。

#### `NeedService.lua`

用 `RandomBag` 从需求配置中抽取需求，保证一袋内每项恰好出现一次，再重新洗牌；比每次独立随机更均匀。

#### `NeedResolver.lua`

需求规则的统一判定点。目前支持 `equipment` 与 `facility`：装备比较 `item_key`，设施比较 `facility_id/id`。同时提供可生成装备需求过滤和展示文案 fallback。

#### `ItemService.lua`

为每种装备需求生成一个世界道具，注册获得事件，维护 `BabyItemRecord` 列表。它负责最近匹配搜索、跳过已持有物品、判断是否归宝宝所有、强制拾取、销毁并补货。距离只比较 XZ，避免单位枢轴高度影响地面接近判定。

#### `FacilityService.lua`

全项目最大的服务，负责注册设施、占用关系、接触判定、座位同步和三套载具策略：

- 普通座位/秋千：约 30Hz 把宝宝同步到设施局部座位点，并强制坐姿动画。
- `kinematic`：当前滑板模式。约 30Hz 用确定性位置计算移动滑板，包含转向限速、加减速、到点减速、边界回避，并把宝宝同步到座位。
- `physics`：宝宝尝试进入真实载具，再按方向分段驱动车辆；仅适合真正带载具组件的单位。
- `player_bound`：约 60Hz 检测非宝宝角色是否持续站在板上，去抖后让宝宝跟随该玩家，离板后完成。

它还负责碰撞开关、可选装饰模型绑定、角度转换、设施开始/结束自定义事件。当前只有 `kinematic` 路径由配置启用。

#### `ScoreService.lua`

正确时更新玩家 session 并调用 `role.add_score`；错误时更新错误计数并按配置扣分。找不到具体玩家时只显示全局提示。当前错误惩罚配置为 0。

#### `TaskEventService.lua`

把领域事件翻译成 `QuestData` 可消费的自定义事件。优先发给最后交互玩家，否则广播所有玩家。部分事件按 1.5 秒分阶段发送，以配合任务引导节奏。

#### `DifficultyService.lua`

累计全局满足次数，每满足配置数量就提升 chaos level，上限为 5，并同步 `GameViewModel`。目前只改变指标，没有实际修改宝宝数、超时、移动或事件频率。

#### `RoundService.lua`

注册每秒触发器，更新已过/剩余时间、同步在线玩家，并写入 `GameViewModel`。当前剩余时间到 0 后只停在 0，回合仍继续，不会自动胜负结算。

### 5.9 `BabyStorm/View/`

#### `BabySceneView.lua`

为每个 Agent 创建 `ViewBinding`，只订阅 `StatusText`。字段变化时调用单位气泡 API；空文本隐藏气泡。销毁时解除全部绑定。当前并没有独立实现 `anim_overlay` 的表情/特效展示。

### 5.10 `MVVM/`

#### `ViewModelBase.lua`

通用可观察字段容器：

- 保存字段值与每字段委托列表。
- 生成唯一委托 handle。
- 广播时复制快照，允许回调过程中解绑。
- 支持嵌套 batch，同一字段在一批中只广播一次且保留首次变化顺序。
- `set_property` 不接受 `nil`，相同值不广播。

#### `ViewBinding.lua`

管理 View 对 ViewModel 的单向订阅，支持单条和批量绑定。销毁时按 owner 移除委托。当前工作区版本避免使用 table/userdata 作为去重键，以适配帧同步沙盒限制；这是用户已有未提交改动，本文没有修改它。

### 5.11 `Util/`

#### `Log.lua`

统一 `[BabyStorm]` 日志前缀，把可变参数转成字符串后拼接输出；提供 info/warn 两级文本标记。

#### `RandomBag.lua`

复制源数组后用 Fisher-Yates 洗牌，`take` 从袋尾取值，空袋时重洗。使用 `LuaAPI.rand` 保证同步随机。

#### `RoleUtil.lua`

获取 RoleID，或从单位反查玩家。反查依次尝试 owner、role_id，最后稳定扫描有效玩家控制单位。

#### `UnitUtil.lua`

通过单位 ID 做稳定同一性比较，并提供三维距离平方与 XZ 距离平方，避免不必要的开方。

#### `TaskEvents.lua`

集中定义所有任务事件名与基础 payload。`emit` 给单个玩家控制单位发自定义事件，`emit_all` 广播所有有效玩家。`Data/QuestData.lua` 中的任务目标字符串与这里对应。

### 5.12 `Data/`：编辑器自动导出数据

这些文件顶部都标注了自动导出，职责是把编辑器资产转换成 Lua 表。

| 文件 | 当前内容与用途 |
| --- | --- |
| `Prefab.lua` | 有效资源总表：宝宝角色、三种装备、场景 EUI、秋千和滑板单位 ID |
| `EquipmentPrefab.lua` | 三种自定义食物装备的名称、描述和 prefabID |
| `QuestData.lua` | “新手引导”任务链，消费举起、交付、拾取、满意、错误等自定义事件 |
| `AbilityData.lua` | 当前为空的技能导出表 |
| `AbilityLuaData.lua` | 当前为空的技能 Lua 数据表 |
| `AchievementData.lua` | 当前为空的成就表 |
| `ArchivesData.lua` | 当前为空的存档表 |
| `MontageKeys.lua` | 当前为空的动画 Montage Key 表 |
| `StoryData.lua` | 当前为空的剧情表 |
| `UINodes.lua` | 当前为空；旧 `BabyMvp.lua` 仍尝试读取其中节点键，因此旧 UI 路径并不完整 |

### 5.13 `behavior_tree/`

#### `custom_node/example_action_node.lua`

行为树自定义 Action 示例。`run` 读取 `env.owner` 但不使用，直接返回引擎 `behavior.behavior_ret.SUCCESS`。当前 BabyStorm 状态机不依赖行为树。

#### `custom_node/node_config.lua`

把 `ExampleAction` 注册到自定义节点配置。当前是未跟踪文件，通常由行为树加载约定发现，不在 `main.lua` require 链中。

### 5.14 `Docs/`

#### `BabyStormArchitecture.md`

早期重构架构说明，准确描述了 App/Domain/Services/MVVM 的方向，但状态列表和功能进度落后于当前代码，例如没有完整覆盖 Cry、设施和载具实现。

#### `BabyStormGameplayResearch.md`

玩法定位、玩家动词、需求类型和 P0～P3 优先级研究。它解释“为什么做”，不解释当前每行代码“怎么做”。

#### `ProjectBreakdown.md`

本文，基于当前工作区做实际模块和文件拆解。

### 5.15 工程与代理工具目录

- `.gitignore`：只忽略 `log.txt`。
- `.vscode/launch.json`：VS Code 使用 `eggy-lua` 调试器连接 `127.0.0.1:1635`。
- `.agents/`：Codex 使用的 Eggy 开发、UI、测试、日志、计划等技能及参考资料；不进入游戏包逻辑。
- `.claude/`：Claude 版本的同类技能、工程规则和 `baby-ai-architecture.md` 验收规约；不进入游戏运行时。
- `.codemaker/`：CodeMaker 配置、同类技能副本、规则和 `editor-cli.exe`。`config.json` 记录帧同步模式及工具版本；二进制负责与编辑器交互。
- `.vscode`、`.agents`、`.claude`、`.codemaker` 中的大量技能参考文件是开发工具资料，不是 BabyStorm 的业务模块。同一套 Eggy 指南存在多份副本，是为了不同代理工具各自发现技能。

## 6. 对象所有权与清理责任

| 对象 | 创建者 | 主要持有者 | 清理者 |
| --- | --- | --- | --- |
| `GameApplication` | `GameApp.lua` 模块加载时 | `GameApp` | `GameApp.destroy` 重置内容 |
| `BabyAgentManager` | `BabyStormController` | Controller 单例变量 | Controller 调用 Manager.destroy |
| 各 Service | Manager.start | `manager.services` | Manager.destroy |
| BabyAgent | Manager | `manager.agents` | Manager.destroy |
| 宝宝实体 | Manager._create_baby | Agent 引用 | 当前 `BabyAgent.destroy` 只清逻辑，未显式销毁宝宝实体 |
| 装备实体 | ItemService | `item.items` | ItemService.destroy 或满足后补货流程 |
| 设施实体 | 编辑器场景 | FacilityRecord 只引用 | 不销毁，只结束互动/解绑/停移动 |
| 触发器 | TriggerRegistry 包装注册 | Registry | Registry.destroy 逆序注销 |
| ViewModel 委托 | ViewBinding | ViewBinding 与 ViewModel | ViewBinding.destroy / ViewModel.clear |

宝宝实体未显式调用 destroy 是一个值得注意的生命周期点：是否由编辑器在 GAME_END 自动清场取决于平台。若要支持不结束游戏只调用调试 `stop/start`，需要试玩验证是否会残留旧宝宝。

## 7. 当前实现与设计目标之间的差距

这些不是“代码一定报错”，而是当前功能边界：

1. `RoundService` 没有回合结束状态，180 秒后玩法仍继续。
2. `DifficultyService` 只计算 chaos level，没有让玩法实际变难。
3. `GameViewModel` 已有数据，但没有全局 HUD View。
4. `anim_overlay` 被状态写入，但没有单独表现系统消费。
5. `BabyStateLayer` 和 `StateBase.handle_event` 暂未使用。
6. `MoveToTarget` 是已实现但当前状态没有使用的移动模式。
7. FacilityService 内 `physics/player_bound` 分支已实现但当前配置未启用，不能视为已通过实机验证。
8. 架构规约宣称只有 MovementSystem/AnimationSystem 可移动和播动画，但设施同步因平台限制仍直接在 `FacilityService` 中设置位置和播放座位/骑行动作；当前实现实际上把“设施拥有的位移表现”作为例外。
9. 延迟回调虽然检查状态或 `destroyed`，但没有统一取消句柄；目前主要靠守卫变成 no-op。
10. `BabyStormDebug.start()` 不传 `application`，因此调试直启时没有玩家 session，统计和部分计分记录会退化，但角色本身仍可直接加分。

## 8. 修改功能时从哪里下手

| 目标 | 首要修改点 | 通常还要检查 |
| --- | --- | --- |
| 调宝宝数量/时间/分数 | `BabyStormConfig.lua` | 无 |
| 新增装备需求 | 编辑器预设 + `Data.Prefab` 自动导出 + `Config.needs` | `QuestData` 是否需要新任务 |
| 新增设施需求 | `Config.needs` | `FacilityService` 是否已有对应交互策略 |
| 新增行为状态 | `BabyStormEnum.lua` + 新 State 文件 | `BabyAgent:_new_state` 与转移入口 |
| 改拾取规则 | `NeedResolver.lua` | `ItemService.nearest_match`、Agent 结算 |
| 改设施移动 | `FacilityService.lua` | 配置中的 drive mode 与参数 |
| 新增头顶显示字段 | `BabyViewModel.lua` | `BabySceneView.lua` 绑定 |
| 新增全局 HUD | `GameViewModel.lua` | 新 View + Controller/Manager 装配 |
| 新增任务事件 | `TaskEvents.lua` + `TaskEventService.lua` | 编辑器导出的 `QuestData.lua` |
| 改玩家统计/计分 | `PlayerSessionRegistry.lua` + `ScoreService.lua` | 回合结算设计 |

## 9. 推荐阅读顺序

第一次阅读不要从 1000 行的 FacilityService 开始。建议：

1. `main.lua`、`GameApp.lua`、`ControllerRegistry.lua`
2. `BabyStormController.lua`、`BabyAgentManager.lua`
3. `BabyStormConfig.lua`、`BabyStormEnum.lua`、`BabyIntent.lua`
4. `BabyAgent.lua`
5. `StateBase.lua` 和七个具体状态
6. `NeedRuntime/ActionLock/MovementSystem/AnimationSystem`
7. `NeedService/NeedResolver/ItemService`
8. 最后读 `FacilityService`
9. 再用 `BabyMvp.lua` 对照重构前后的职责变化

读完后应能独立回答三个问题：一次正确物品交付经过哪些对象；为什么动作锁必须按 reason 幂等；为什么设施需求不能由 Idle 的物品扫描自动触发。
