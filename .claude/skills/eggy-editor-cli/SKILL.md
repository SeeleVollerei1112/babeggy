---
name: eggy-editor-cli
description: |
  蛋仔派对编辑器操作技能。通过 editor-cli.exe 执行 EditorAPI 命令来操控编辑器。
  使用场景：试玩/停止试玩、检查编辑器状态、编辑 UI 界面、场景搭建。
---

# 编辑器操作指南

## CLI 配置

editor-cli.exe 默认位于项目根目录下的 [.codemaker](../../../.codemaker) 文件夹下：

```batch
set CLI = '.codemaker/editor-cli.exe'
```

> 若默认位置的 [editor-cli.exe](`../../editor-cli.exe`) 不存在，提示用户提供 editor-cli.exe 的绝对路径。

## CLI 使用

```batch
%CLI% [--timeout TIMEOUT] [--json] <command> [--option]...`
```

### 查看使用说明
使用 `--help` 参数
  - `%CLI% --help` ：CLI 工具整体说明
  - `%CLI% <command> --help` ：CLI 工具单独命令说明（用于查询 option ）

## 编辑器状态

- 编辑模式（编辑时）：允许进行地图内容相关的编辑
- 运行模式（运行时）：允许进行地图数据内容的部分读取，存在单独的游戏运行时环境，允许通过编辑器与游戏运行环境进行交互

## 核心原则

1. **CLI 连接检查**：检查编辑器连接状态（ `%CLI% status` ）
2. **需求确认**：确定用户需求
3. **EditorAPI 查阅**：查看 [EggyEditorAPI.lua](../../../EggyEditorAPI.lua) 寻找所需 API
4. **编辑器状态确认**：检查编辑器是否处于正确的模式（编辑模式/试玩模式）
3. **playing 状态**：试玩环境：可以使用 game_execute、操控玩家、读取运行日志
4. **exec 内的代码没有输出**：用 `print()` 或者 `EditorAPI.log()` 写日志，再读 `log.txt`

## 通过 CLI 运行 Lua 代码

- **编辑模式**
  - 执行代码与编辑器交互（读写）：`%CLI% exec "<lua>"`
- **试玩模式**
  - 执行代码查询编辑器信息（读）：`%CLI% exec "<lua>"`
  - 执行代码与游戏试玩环境交互：`%CLI% exec "EditorAPI.game_execute('<lua>')"`

### 引号使用规则

```batch
# 直接 exec = 外层用双引号，Lua 内用单引号
%CLI% exec "local udata = EditorAPI.get_scene_unit_data(uid); print(udata.position)"

# 使用 exec + EditorAPI.game_execute = 外层用双引号，Lua 内用单引号，game_execute 的内容内用 [[ ]]
%CLI% exec "EditorAPI.game_execute('local u = LuaAPI.query_unit([[名称]]); print(u.get_position())')"
```

## 常用

### 切换编辑与试玩

| 操作 | 命令 |
|------|------|
| 开始试玩 | `%CLI% exec "EditorAPI.run_game()"` |
| 停止试玩 | `%CLI% exec "EditorAPI.stop_game()"` |

### Lua 代码输入日志

统一使用 `print()`, 支持打印各种类型的数据，不需要使用 `tostring()`：
 - 编辑时：`%CLI% exec "print(<lua>)"`
 - 试玩时：`%CLI% exec "EditorAPI.game_execute('print(<lua>)')"`

### 日志读取

直接读取当前工作目录根目录下的 [log.txt](../../../log.txt) 即可

```powershell
# 增量读取（推荐）
$offset = (Get-Item "log.txt").Length
# ... 执行 game_execute ...
$bytes = [System.IO.File]::ReadAllBytes("log.txt")
$newContent = [System.Text.Encoding]::UTF8.GetString($bytes[$offset..($bytes.Length-1)])
```

## 注意事项

1. 批量创建时需分批：每批 ≤ 10 个，批次间延迟 200ms

## 参考文档

### 通用

- [编辑器详细状态检测](references/state-awareness.md)

### 编辑模式

- [EditorAPI（编辑时 API ）](../../../EggyEditorAPI.lua)
- [编辑模式场景编辑](references/editing/scene-editing.md)

### 试玩模式

- [EggyAPI（运行时 API ）](../../../EggyAPI.lua)
- [试玩模式玩家控制](references/playtesting/player-control.md)

### 具体功能分流

- [UI 界面（ EUI ）](references/features/eggy-editor-cli-eui/SKILL.md)