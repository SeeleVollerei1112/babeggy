# 调试时玩家操控指南

> ⚠️ **所有玩家操控操作必须在 `editor_status == playing` 时执行。**
> 编辑时（idle）无法访问游戏内玩家对象。

## PowerShell 引号规则（必读）

Agent 在 PowerShell 中执行命令时，`\"` 转义**不可靠**，会导致 PowerShell 把字符串内容误解析为命令。

**规则：`game_execute` 内的 Lua 代码字符串只使用单引号 `'`，不使用双引号。**

```batch
# ❌ 错误：用 \" 转义，PowerShell 报"无法加载模块"错误
%CLI% exec "EditorAPI.game_execute('print(\"MCP_NO_ROLES\")')"

# ✅ 正确：Lua 内全用单引号，PowerShell 单引号字符串内用 '' 表示单引号字面量
%CLI% exec "EditorAPI.game_execute('print(''MCP_NO_ROLES'')')"
```

---

## Marker + log.txt 侧信道机制

`EditorAPI.game_execute()` 是 fire-and-forget 接口，无法直接返回 Lua 执行结果。
通过以下侧信道方式读取游戏内数据：

```
原理：
  1. 记录执行前 log.txt 的文件大小（offset_before）
  2. 注入含 print('MARKER|' .. value) 的 Lua 代码（全单引号）
  3. 等待 2 秒（游戏逻辑帧执行 + 日志写入）
  4. 读取 log.txt 从 offset_before 起的新增内容
  5. 按 MARKER| 前缀找到目标行，解析数据
```

使用步骤（Agent 操作序列）：
```batch
# Step 1: 记录 log.txt 当前大小（读文件前先 stat）
# Step 2: 注入 Lua（全单引号，无需转义）
.codemaker\editor-cli.exe --port 19836 exec "EditorAPI.game_execute('local roles = GameAPI.get_all_roles();if not roles or #roles == 0 then print(''MCP_NO_ROLES'') return end;local u = roles[1].get_ctrl_unit();local pos = u.get_position();print(''MCP_PLAYER|'' .. tostring(pos.x) .. ''|'' .. tostring(pos.y) .. ''|'' .. tostring(pos.z))')"
# Step 3: 等待 2 秒
# Step 4: 读取 log.txt 新增行，查找含 MCP_PLAYER| 的行
# Step 5: 解析 | 分隔的 x, y, z 值
```

**注意**：语句间用 `;` 分隔，不能换行；所有字符串用单引号，`''` 表示单引号字面量。

---

## 获取玩家状态快照

**完整 PowerShell 命令（game_execute 内全单引号）：**

```batch
%CLI% exec "EditorAPI.game_execute('local roles = GameAPI.get_all_roles();if not roles or #roles == 0 then print(''MCP_NO_ROLES'') return end;local u = roles[1].get_ctrl_unit();if not u then print(''MCP_NO_UNIT'') return end;local pos = u.get_position();local hp = tostring(u.get_life and u.get_life() or -1);local hpmax = tostring(u.get_life_max and u.get_life_max() or -1);local dead = tostring(u.is_die_status and u.is_die_status() or false);print(''MCP_PLAYER|'' .. tostring(pos.x) .. ''|'' .. tostring(pos.y) .. ''|'' .. tostring(pos.z) .. ''|'' .. hp .. ''|'' .. hpmax .. ''|'' .. dead)')"
```

**返回格式**（在 log.txt 中查找）：
```
MCP_PLAYER|x|y|z|hp|hp_max|is_dead
```

解析示例：`MCP_PLAYER|10.5|2.0|-3.25|100|-1|false`
- `position`: `{x: 10.5, y: 2.0, z: -3.25}`
- `hp`: `100`
- `is_dead`: `false`

**错误标记：**
- `MCP_NO_ROLES` → 游戏中没有玩家，提示「请确认玩家已进入游戏」
- `MCP_NO_UNIT` → 玩家无控制单位，提示「玩家控制单位未初始化」
- 2秒后未找到 `MCP_PLAYER|` → 报告失败，不重试

---

## 玩家移动操控

| 模式 | 适用场景 | Lua API | 触发沿途碰撞 |
|------|---------|---------|:----------:|
| **瞬移** | 快速定位到测试点 | `unit.set_position(math.Vector3(x, y, z))` | ❌ |
| **物理移动** | 测试触发区域、碰撞逻辑 | `unit.cmd_move_to_pos(math.Vector3(x, y, z), duration)` ⚠️ `duration` 必须为**浮点数** | ✅ |

### 瞬移示例

```batch
%CLI% exec "EditorAPI.game_execute('local roles = GameAPI.get_all_roles();if not roles or #roles == 0 then print(''MCP_ERR|NO_ROLES'') return end;local u = roles[1].get_ctrl_unit();u.set_position(math.Vector3(10, 2, -5));print(''MCP_OK|teleport'')')"
```

### 物理移动示例

```batch
# 让玩家物理移动到 (10, 0, 20)，持续 5 秒
%CLI% exec "EditorAPI.game_execute('local roles = GameAPI.get_all_roles();if not roles or #roles == 0 then print(''MCP_ERR|NO_ROLES'') return end;local u = roles[1].get_ctrl_unit();u.cmd_move_to_pos(math.Vector3(10, 0, 20), 5);print(''MCP_OK|move'')')"
# 等待 5 秒后再查询位置确认
```

---

## 玩家动作速查表

| 动作 | Lua API | 说明 |
|------|---------|------|
| **跳跃** | `unit.jump()` | 触发跳跃，需在地面上才有效 |
| **冲刺/飞扑** | `unit.cmd_rush()` | 触发冲刺动作 |
| **抬举** | `unit.cmd_lift()` | 触发抬举动作 |

### 跳跃示例

```batch
%CLI% exec "EditorAPI.game_execute('local roles = GameAPI.get_all_roles();if not roles or #roles == 0 then print(''MCP_ERR|NO_ROLES'') return end;local u = roles[1].get_ctrl_unit();u.jump();print(''MCP_OK|jump'')')"
```

---

## 自定义事件广播

绕过物理输入层直接触发游戏内逻辑，用于模拟触发区域进入、UI 按钮点击等场景。

### 广播无数据事件

```batch
%CLI% exec "EditorAPI.game_execute('LuaAPI.global_send_custom_event(''GAME_START'', nil);print(''MCP_EVENT|OK'')')"
```

### 广播带数据事件

```batch
# 模拟玩家拾取金币（携带 coinId=42）
%CLI% exec "EditorAPI.game_execute('local d = dict();d.set(d, ''coinId'', 42);LuaAPI.global_send_custom_event(''coin_picked'', d);print(''MCP_EVENT|OK'')')"
```

**dict 构造模板（多个键值）：**
```batch
# PowerShell 中 dict key 用单引号，'' 表示单引号字面量
"EditorAPI.game_execute('local d = dict();d.set(d, ''key1'', value1);d.set(d, ''key2'', value2);LuaAPI.global_send_custom_event(''EVENT_NAME'', d)')"
```

> ⚠️ 事件名称必须与游戏内 `LuaAPI.global_register_trigger_event({EVENT.CUSTOM_EVENT, "EVENT_NAME"}, ...)` 注册的名称完全一致。

---

## 完整操控流程示例

**场景：将玩家传送到终点并验证到达**

```bash
# 1. 确认处于 playing
%CLI% status

# 2. 获取当前位置（确认基准值）
%CLI% exec "EditorAPI.game_execute('..MCP_PLAYER|..')"
# 读取 log.txt 新增行，解析位置

# 3. 瞬移到终点坐标 (100, 2, 50)
%CLI% exec "EditorAPI.game_execute('..set_position(math.Vector3(100, 2, 50))..MCP_OK|teleport')"

# 4. 等待 1 秒
# 5. 再次查询位置，验证已到达目标坐标
%CLI% exec "EditorAPI.game_execute('..MCP_PLAYER|..')"
# 确认 x≈100, y≈2, z≈50
```
