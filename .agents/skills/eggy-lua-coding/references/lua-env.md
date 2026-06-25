# 蛋仔派对Lua环境

游戏逻辑运行在安全沙盒中，限制了部分Lua功能以确保安全性和多人游戏状态一致性。

## 库的变更

### 移除的库
- io
- os
- package
- debug

### 支持的全局变量/函数
`_VERSION` `error` `assert` `ipairs` `pairs` `next` `pcall` `tostring` `type` `xpcall` `select` `print` `traceback`

- `require` - 仅限加载script目录下的其他lua模块
- `setmetatable` - 不可使用__mode和__gc域
- `getmetatable` - 仅可获取table的metatable

## 语法变更

1. **不支持字符串和数字类型间的隐式转换**
2. **表的键只能是数字或字符串**

需要其他类型键时使用dict()：
```lua
local map = dict()
local key = {}
map:set(key, 1234)
assert(map:get(key) == 1234)

for _, kv in ipairs(map:keyvalues()) do
   print("K: " .. tostring(kv[1]) .. "V: " .. tostring(kv[2]))
end
```

## 开发者模式

PC编辑器试玩时可开启，解除部分限制：
```lua
local success = LuaAPI.enable_developer_mode()
```

特性：内置LuaSocket、解除表键限制、允许io/debug库

**注意**: 仅PC编辑器试玩有效，发布后无效！不要依赖此模式的功能。

## math库

蛋仔math库支持整数(integer)和定点数(Fixed)。

### 数值范围
定点数: -2147483647.0 ~ 2147483647.0

### 常量
`math.pi` `math.e` `math.maxval` `math.minval` `math.zero` `math.one` `math.neg_one`

### 转换函数
- `math.tointeger(x)` - 转整数(向下取整)
- `math.tofixed(x)` - 转定点数
- `math.toreal(x)` - 转实数

### 数学函数
- 三角: `sin` `cos` `tan` `asin` `acos` `atan` `atan2`
- 对数: `log` `log2` `log10` `log1p`
- 指数: `exp` `exp2` `pow`
- 取整: `round` `ceil` `floor` `trunc`
- 其他: `sqrt` `abs` `fabs` `fmod` `min` `max` `clamp`
- 角度: `rad_to_deg` `deg_to_rad`
- 比较: `equal001(a, b)` - 误差在0.001内

## Vector3

```lua
local v = math.Vector3(x, y, z)
v.x, v.y, v.z           -- 分量
v.yaw, v.pitch          -- 朝向角度(只读)
v:length()              -- 长度
v:normalize()           -- 归一化，返回原长度
v:dot(other)            -- 点积
v:cross(other)          -- 叉积
v:set_pitch_yaw(p, y)   -- 设置朝向
-- 支持 + - * / 运算
```

## Quaternion

```lua
local rot = math.Quaternion(pitch, yaw, roll)  -- 弧度制
rot.x, rot.y, rot.z, rot.w   -- 分量
rot.yaw, rot.pitch, rot.roll -- 欧拉角(只读)
rot:inverse()                -- 求逆
rot:apply(vector)            -- 旋转向量
rot:slerp(other, t)          -- 球面插值
-- 支持 * 运算
```

**注意**: 欧拉角旋转顺序为 pitch->yaw->roll (XYZ顺序)，可能与编辑器显示不同。
