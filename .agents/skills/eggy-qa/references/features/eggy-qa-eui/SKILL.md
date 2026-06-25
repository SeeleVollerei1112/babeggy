---
name: eggy-qa-eui
description: |
  帧同步 EUI 自动化测试助手。为帧同步模式（非 SE）的 EUI 代码自动生成测试、
  运行测试并分析结果、根据测试失败自动修复代码。

  使用场景：
  - 用户请求"测试 UI"、"试玩测试"、"验证 UI"等
  - UI 代码编写完成后自动进入测试阶段
  - 需要验证 EUI 节点创建、层级关系、子节点结构是否正确
  - 需要通过截图视觉分析确认 UI 显示效果
  
  注意：此技能适用于帧同步模式（非 SE），使用 GameAPI/Role/LuaAPI 运行时 API。
  SE 模式请使用 eggy-se-eui-test。
---

# 帧同步 EUI 自动化测试助手

读 testspec(或读代码并生成 testspec) → 基础检查 → 按功能场景写测试 → 运行+截图 → 看日志+截图分析 → 修代码重试。**整个流程一气呵成，不在步骤间暂停询问用户。**

## 核心约束（帧同步模式特有）

1. **ENode 是 string 标识符**，不支持属性直读（无 `.Visible`/`.Position`/`.Size`）
2. **无读取接口**：EggyAPI 中没有 `get_node_visible`/`get_node_position` 等，无法在运行时读取节点属性值
3. **无模拟点击**：没有 `SimulateTap`/`SimulateSwipe` 等接口，无法在测试中模拟用户交互
4. **无测试内截图**：没有 `TF.screenshot()`，截图通过外部 `EditorAPI.take_screenshot()` 在测试完成后执行
5. **`get_eui_child_by_name` 只搜直接子节点**，递归查找需自行实现（测试框架已内置）

### 可用断言能力

| 断言类型 | 可用性 | 实现方式 |
|---------|--------|---------|
| 模块加载 | ✅ | `pcall(require, ...)` |
| 节点存在 | ✅ | 递归 `get_eui_child_by_name` |
| 子节点数量 | ✅ | `GameAPI.get_eui_children_count(node)` |
| 层级包含关系 | ✅ | 遍历 `GameAPI.get_eui_children(parent)` 验证 |
| 可见性 | ❌ | 无读取接口，依赖截图 |
| 位置/尺寸 | ❌ | 无读取接口，依赖截图 |
| 透明度 | ❌ | 无读取接口，依赖截图 |
| TouchEnabled | ❌ | 无读取接口 |
| 模拟点击 | ❌ | 无模拟点击 API，测试中不提供任何点击占位方法 |

---

## 工作流程

```
构建测试 ──> 执行测试 ──> 审查修复(最多5轮)
   │             │             │
   ▼             ▼             ▼
 testspec驱动  editor-cli    日志+截图分析
 基础检查      AI轮询等待     修代码→重跑
 编写测试代码   截图(外部)
```

### 构建测试

**必须读取**：[`references/test-guide.md`](references/test-guide.md)

- **快速路径**：`test/testspec_{模块名}.md` 存在 → 读取，跳过代码分析/Name注入/生成
- **完整路径**：读代码 → 注入 Name → 生成 testspec → 汇合
- **汇合后**：基础检查 → 按功能场景编写测试 → 自检
- 确保 `test/test_framework.lua` 存在（从 `references/test-framework.md` 中的源码复制）

### 执行测试

**必须读取**：[`references/run-and-review-guide.md`](references/run-and-review-guide.md)

通过 `game_execute` 注入测试代码，AI 轮询日志等待完成。测试完成后通过 `EditorAPI.take_screenshot()` 截图。

### 审查修复

**必须读取**：[`references/run-and-review-guide.md`](references/run-and-review-guide.md)

**先审截图再看日志（铁律）。** 截图 + 日志综合分析 → 修 UI 代码或测试代码 → 重跑。最多 5 轮，第 4~5 轮强制换修复方向。

## 全局约束

1. **绝不修改 `client/main.lua`** — 测试通过 `game_execute` 动态注入
2. **exec 内部统一单引号** — 每轮 stop/restart 保证全新环境
3. **testspec 驱动** — 无 testspec 时自动生成，所有路径统一由 testspec 驱动测试编写
4. **截图是主力验证** — 布局/居中/美观通过截图分析，代码断言验证逻辑状态
5. **自动修复不问用户** — 发现报错直接修改代码，连续两轮相同错误必须切换方向
6. **修复循环完成后统一同步 testspec** — 修复阶段专注于快速修复和重跑，**不要求每轮修复后立即同步 testspec**。待修复循环全部完成（所有测试通过 + 截图无异常）后，统一将修复期间的节点结构和交互逻辑变更同步到 `test/testspec_{模块名}.md`
7. **截图通过外部 EditorAPI 执行** — 测试代码内不调用截图，由运行流程在测试完成后通过 `EditorAPI.take_screenshot()` 截取

## Reference 文件索引

| 阶段 | 文件 |
|------|------|
| 构建测试 | [`test-guide.md`](references/test-guide.md) |
| 构建测试 | [`test-framework.md`](references/test-framework.md) |
| 执行+审查+修复 | [`run-and-review-guide.md`](references/run-and-review-guide.md) |