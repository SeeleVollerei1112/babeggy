# 编辑器详细状态检测

## 基础：CLI 连接状态，编辑时/试玩时

```batch
%CLI% status
```

- `Running`：CLI 与编辑器连接状态
- `Edit Mode`：是否在编辑模式
- `In Game Runtime`：是否在试玩模式

## 编辑时详细状态

| 状态 | 指令 |
|--|--|
| UI 编辑模式 | `%CLI% exec "print(EditorAPI.is_in_eui_edit_mode())"` |