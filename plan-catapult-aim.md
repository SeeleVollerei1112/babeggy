# TODO：投石车自选落点

> 创建时间：2026-07-08 | 范围：功能级 | 粒度：TODO 条目

## 需求概述

投石车当前落点写死在配置里（`catapult` def 的 `launch_target`），玩家无法干预。
本功能把发射改成**两段式瞄准态**：玩家点发射按钮进入瞄准 → 点击「落点区地板」选点 → 再点发射确认。
落点被限制在一块**新摆放的落点区地板组件**范围内——点击该组件才产生 `touch_pos`，天然保证落点在区内。

## 架构约束（遵守 baby-ai-architecture.md）

- 本功能是**设施交互的表现/输入扩展**，全部改动落在 `CatapultLaunchService`（服务层）与配置，**不触碰宝宝 AI 五层**。
- 位移仍由 `FlightDriver` 独占（唯一改宝宝位置处），行为/需求层不动。
- 无每秒续命动画、无 disable/enable AI。

## 关键技术依据（已核实）

| 事项 | 结论 | 位置 |
|------|------|------|
| 拿地面点击点 | 无「点空地→坐标」事件；`touch_pos`(Vector3) 仅在点到组件时随事件给出 | `EggyAPI.lua:9626` `SPEC_OBSTACLE_TOUCH_BEGIN` |
| 区域限制 | 点落点区组件才触发，`touch_pos` 必在其上；无需额外射线/区域校验 | 同上 |
| 飞行到任意点 | `FlightDriver` 已接受任意 `to`，拱高按 `arc_peak` 参数，无需改 | `FlightDriver.lua:37` |
| 现发射链路 | `on_launch_pressed → _begin_launch(delay) → _do_launch(to=def.launch_target)` | `CatapultLaunchService.lua:103-179` |

## 前置依赖（编辑器侧，需用户提供）

- [ ] **[高]** 在编辑器里摆放一块「落点区地板」组件（obstacle），覆盖允许落点的范围，提供其 **unit_id**
  - **验收**：WHEN 摆好并试玩点击该地板，THEN 日志能打印出 `SPEC_OBSTACLE_TOUCH_BEGIN` 的 `touch_pos`

## 任务列表

| 优先级 | 任务 | 状态 | 验收标准 |
|--------|------|------|---------|
| 🔴 高 | 配置加落点区字段 | ⬜ | WHEN 读取 catapult def THEN 得到 `landing_zone_unit_id` |
| 🔴 高 | 监听落点区点击→记录落点 | ⬜ | WHEN 瞄准态点地板 THEN `active.target = touch_pos` |
| 🔴 高 | 发射按钮改两段式（瞄准→确认） | ⬜ | WHEN 未选点点发射 THEN 只进瞄准态不发射 |
| 🟡 中 | 落点指示器表现 | ⬜ | WHEN 选点 THEN 指示器移动到落点 |
| 🟡 中 | 未选点/超时兜底 | ⬜ | WHEN 瞄准态未选点确认 THEN 回退到 def 默认落点或提示 |
| 🟢 低 | 试玩验证 | ⬜ | 见末尾验收清单 |

## 详细 TODO

- [ ] **[高]** 配置：`BabyStormConfig` 的 catapult def 增加 `landing_zone_unit_id`（落点区组件 ID），`launch_target` 保留作默认/兜底
  - **验收**：WHEN `CatapultLaunchService` 读取 facility.def，THEN 能取到 `landing_zone_unit_id`

- [ ] **[高]** 输入：`CatapultLaunchService:start` 里对落点区组件注册 `SPEC_OBSTACLE_TOUCH_BEGIN`
  - 仅在 `self.active` 存在且 `active.aiming == true` 时接收，写 `active.target = data.touch_pos`（做一次拷贝/`MathX.to_vector3`）
  - **验收**：WHEN 瞄准态点落点区，THEN `active.target` 更新为点击世界坐标；非瞄准态点击被忽略

- [ ] **[高]** 交互：改造 `on_launch_pressed` 为两段式
  - 无 `active` 且有骑臂宝宝 → 进入瞄准态：`self.active = { agent, facility, aiming=true, target=nil }`，`agent:set_status("选择落点")`
  - 已在瞄准态且 `active.target ~= nil` → 关闭瞄准（`aiming=false`）→ 走原 `_begin_launch/_do_launch`，`to` 用 `active.target`
  - 已在瞄准态但未选点 → 忽略或提示（见兜底任务）
  - `_do_launch` 中 `to` 取 `active.target or MathX.to_vector3(facility.def.launch_target)`
  - **验收**：WHEN 点发射→点地板→再点发射，THEN 宝宝飞向所点落点；WHEN 只点一次发射，THEN 仅进入瞄准态不飞出

- [ ] **[中]** 表现：落点指示器（贴地光圈/标记），进瞄准态显示、选点时 `set_position` 到落点、发射/结束时隐藏
  - 优先复用现有场景 UI/组件 bind 方式（参照 `_bind_button_canvas`）；无现成资源则先用 `agent:set_status` 文案兜底，指示器留 TODO
  - **验收**：WHEN 选点，THEN 指示器出现在落点处；WHEN 发射或放弃，THEN 指示器隐藏

- [ ] **[中]** 兜底：瞄准态下未选点就确认 / 中途放下宝宝 / 目标失效
  - 未选点确认：保持瞄准态并 `set_status` 提示，或直接用 def 默认落点（二选一，实现时定）
  - 放下宝宝（`active_agent` 失效）：退出瞄准态、隐藏指示器、清 `active`
  - **验收**：WHEN 瞄准中把宝宝抱走，THEN 瞄准态干净退出、无残留指示器/锁

- [ ] **[低]** 试玩验证（见验收清单）

## 最终验收清单

- [ ] 点发射按钮 → 进入瞄准态，出现落点指示器/提示
- [ ] 点落点区地板 → 指示器移动到点击处，落点被记录
- [ ] 再点发射 → 宝宝抛物线飞向所选落点并落地结算（→ Satisfied → 下一需求）
- [ ] 点击落点区**之外**不改变落点（区域限制生效）
- [ ] 瞄准中把宝宝抱走 → 瞄准态干净退出，无残留状态/指示器/移动锁
- [ ] 未破坏原有：放宝宝上臂、发射防连点、落地结算需求

## 📊 进度总览

| 阶段 | 状态 |
|------|------|
| 编辑器摆落点区组件 | ⬜ 未开始 |
| 代码实现（配置/输入/交互/表现/兜底） | ⬜ 未开始 |
| 试玩验证 | ⬜ 未开始 |
