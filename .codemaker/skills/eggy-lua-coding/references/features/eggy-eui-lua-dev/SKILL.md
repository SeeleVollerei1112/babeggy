---
name: eggy-eui-lua-dev
description: |
  帧同步UI界面 (EUI) 开发技能。提供蛋仔派对帧同步 UI 的创建、布局、事件绑定和资源管理指导。

  使用场景：
  - 创建帧同步UI界面（弹窗、按钮、列表、进度条等）
  - 需要了解EUI预设资源ID时
  - 编写动态UI创建、布局计算、事件响应等逻辑时
  - 用户提到"UI"、"界面"、"弹窗"、"按钮"、"EUI"等关键词时
---

# 帧同步UI (EUI) 开发指南

你是一位 EggyUI 帧同步框架专家，帮助玩家理清 UI 需求并生成高质量的帧同步 Lua UI 代码。核心规范必须遵守：`references/rules.md`

---

## 工作模式：Plan -> Validate -> Execute -> Test

### 阶段一：Plan（需求梳理）

**必须读取** `references/ui-aesthetics-guide.md` — 确认风格、色值、弹窗选型、执行原则

理解需求后，向玩家确认关键点：

- **简单/明确需求**（如"加个关闭按钮"、"把标题改成红色"）：只确认 1~2 个关键问题，快速推进
- **复杂/模糊需求**（涉及多界面、游戏逻辑、状态流转）：按界面类型、元素组成、交互逻辑、资源需求等维度梳理

#### Plan 输出要求
**必读** `references/api-cheatsheet.md`
所有问题收集完毕后，**必须输出一份完整的方案摘要**供玩家审阅，摘要应包含：

1. **界面清单**：列出所有界面/层级（主界面、游戏界面、弹窗等）
2. **核心元素**：每个界面包含的 UI 元素（按钮、文本、图片、进度条等）及其用途
3. **交互流程**：界面之间的跳转关系、用户操作触发的逻辑
4. **资源选型**：计划使用的预设 ID 及说明（背景、按钮、图标等）
5. **风格推荐**：选定的视觉风格

**禁止行为：**
- ❌ 问了一个问题，收到回答后就直接开始生成代码
- ❌ 把玩家回答某个子问题当成"全部确认"
- ❌ 跳过方案摘要直接进入 Execute 阶段

### 阶段二：Validate（获取确认）

输出方案摘要后，**必须显式询问玩家确认**，例如："方案如上，是否确认开始生成代码？"

只有当玩家给出**明确的肯定回复**（如"确认"、"可以"、"开始吧"、"没问题"）后，才能进入 Execute 阶段。

**判定标准：**
- ✅ 进入 Execute 的前提：玩家看到完整方案摘要 + 给出肯定回复
- ❌ 以下情况不算确认：玩家只是回答了某个子问题、玩家只选择了某个选项但还没看到完整方案

### 阶段三：Execute（生成代码）

生成代码前，**必须按以下顺序实际读取文档**，不得跳过、不得依赖记忆：
1. **必读** `references/api-cheatsheet.md` — 确认方法签名、坐标系、动画机制
2. **按需读取** 下方参考文档索引中对应的预设资源文档

> 文件读取返回空内容时**必须重试**，不得跳过直接生成代码。

所有 API 规范以参考文档为唯一权威来源，**严禁凭记忆或推测使用 API**。

生成代码时，按以下步骤执行（详见下方各步骤章节）：
1. 构建 UI 层级结构树
2. 探索可用 API
3. 查找预设资源
4. 快速预设速查
5. 按模式生成代码

### 阶段四：Test（测试验证）

UI 代码生成并写入文件后，**必须立即激活 `eggy-eui-test` 技能**执行自动化测试，无需等待玩家指令。

**规则：**
- ✅ 代码写入文件后，直接激活 `eggy-eui-test` 技能 进入自动化测试
- ❌ 禁止在代码生成后停下来等待玩家确认
- ❌ 禁止只告诉玩家"代码已生成"而不启动测试

---

## 核心原则

### 1. Fix32 定点数 (必须!)
帧同步要求所有客户端计算结果一致，**所有数值参数必须使用 `math.tofixed()` 转换**：

```lua
local tf = math.tofixed  -- 简写

-- ✅ 正确
local x = tf(100)
local width = tf(200)
GameAPI.create_eui_image_at_position(10000, canvas, tf(0), tf(0), tf(100), tf(50), "img")

-- ❌ 错误 (会报类型错误)
GameAPI.create_eui_image_at_position(10000, canvas, 0, 0, 100, 50, "img")
```

### 2. 全局对象 (不需要 require)
以下是引擎全局对象，**不需要 require 导入**：
- `GameAPI` - 游戏核心 API
- `LuaAPI` - Lua 扩展 API
- `EVENT` - 事件常量
- `math` - 数学库（包含 `math.tofixed`）

> ⚠️ `Role` 不是全局变量，必须从事件回调的 `data.role` 获取实例后再调用（如 `role.set_node_visible(...)`）。

```lua
-- ✅ 正确：只 require 项目本地模块
local UINodes = require("Data.UINodes")

-- ❌ 错误：不要 require 全局对象
local GameAPI = require("GameAPI")  -- 错误!
```

### 3. 静态节点获取 
编辑器静态节点存储在 `Data/UINodes.lua`

- `Data/UINodes.lua`内节点**直接就是 `ENode`及其子类 对象实例**  

	- `Data/UINodes.lua`文件需要**玩家手动导出**，如果你发现`Data/UINodes.lua`不存在，请在对话窗口里提示玩家使用`Eggitor`插件导出一下数据。
	- `Data/UINodes.lua`内的节点是**静态节点信息**，会在游戏开始后自动创建。
	- 相对的，通过`GameAPI`相关接口创建的节点为**动态节点**。动态节点和静态节点可以等效看待。


```lua
local UINodes = require("Data.UINodes")
local canvas = UINodes["画布0"]  -- 直接就是 ECanvas 对象

-- ✅ 静态节点canvas可以直接作为动态创建新节点时的父节点
local img = GameAPI.create_eui_image_at_position(10000, canvas, tf(0), tf(0), tf(100), tf(100), "bg")

-- ✅ 动态节点img可以实现和静态节点一样的效果
local child_img = GameAPI.create_eui_image_at_position(10000, img, tf(0), tf(0), tf(100), tf(100), "border")

```

### 4. 📐 坐标系统 (Coordinate System)

#### 4.1 基本规则

1. **设计分辨率**：
   - 默认设计分辨率：1920×1080（横向宽屏比例）
   - 适配策略：基于设计分辨率进行多屏适配

2. **坐标系定义**：
   - 轴向规则：
     - X轴（水平）：➡️向右为正方向
     - Y轴（纵向）：⬆️向上为正方向（符合数学坐标系惯例）
   - 原点位置：
     - 世界坐标系：场景左下角
     - 本地坐标系：父节点左下角位置
   - 锚点规则：
     - 所有节点视为矩形区域（拥有宽和高）
     - 默认锚点位于中心（50%宽度, 50%高度）
     - 节点坐标值 = 自身锚点到父节点左下角的偏移量
     - 示例：X=100 表示节点锚点距父节点左下角水平距离 100 像素
   
3. **画布特性**：
   - 初始尺寸：自动匹配当前屏幕物理分辨率
   - 世界坐标：画布根节点的世界坐标固定为 (0, 0)

#### 4.2 坐标系类型

| 类型                         | 计算逻辑                                                     | 使用场景                   |
| ---------------------------- | ------------------------------------------------------------ | -------------------------- |
| **世界坐标系** (World Space) | 世界坐标 = 父节点世界坐标 - 父节点尺寸的一半  + 自身局部坐标 | 全局对象定位（如场景元素） |
| **本地坐标系** (Local Space) | 直接使用相对于父节点的坐标                                   | UI 层级嵌套布局            |

1. **世界坐标系(World Space)**：
   - 全局绝对坐标系
   - 计算方式：`世界坐标 = 父节点世界坐标 - 父节点尺寸的一半  + 自身局部坐标`
   - 特例：顶层节点（直接子节点）的世界坐标等于其局部坐标

2. **本地坐标系(Local Space)**：
   - 相对父节点的坐标系
   - API规范：所有节点接口默认使用局部坐标参数
   - 变换基准：基于父节点的左下角

#### 4.3 层级规则
1. **节点层级**：
   
   - 支持无限级父子嵌套
   - 所有节点都可以作为其他节点的父节点
   - 坐标变换会自动累积父级变换
   - 父节点隐藏会导致所有子节点隐藏，合理设计层级
   
       - 例如：将需要一起显隐控制的一组子节点放在一个相同的父节点下，控制父节点的显隐即可
   - *警告*：深层嵌套可能影响性能
   
       ```lua
       local UINodes = require("Data.UINodes")  
       local canvas = UINodes["画布0"]  -- 画布根节点  
       
       -- ✅ 案例1：创建顶层节点
       local img = GameAPI.create_eui_image_at_position(10000, canvas, tf(0), tf(0), tf(100), tf(100), "bg")
       
       -- ✅ 案例2：创建嵌套层级结构的节点
       local child_img = GameAPI.create_eui_image_at_position(10000, img, tf(0), tf(0), tf(100), tf(100), "border")
       ```
   
2. **坐标转换**：
   
   - 目前没有直接的坐标转换方法，需要自行计算
   
       ```lua
       -- 世界坐标 → 本地坐标  
       local localX = worldX - parentWorldX  
       local localY = worldY - parentWorldY  
       
       -- 本地坐标 → 世界坐标  
       local worldX = parentWorldX + localX  
       local worldY = parentWorldY + localY  
       ```

实际代码实例：

```lua
local UINodes = require("Data.UINodes")  
local canvas = UINodes["画布0"]  -- 画布根节点  

-- ✅ 案例1：居中于屏幕（父节点为画布）  
local center_pos_x = 1920/2 - node.width/2  -- 水平居中  
local center_pos_y = 1080/2 - node.height/2 -- 垂直居中  

-- ✅ 案例2：居中于父节点（非画布）  
local child_center_x = parent.width/2 - node.width/2  
local child_center_y = parent.height/2 - node.height/2  

-- ✅ 案例3：相对父节点右下角对齐  
local right_bottom_x = parent.width - node.width  
local right_bottom_y = parent.height - node.height  
```

#### 4.4 屏幕适配（进阶）

- **背景介绍**

    - **屏幕分辨率**：运行时`真实设备分辨率`通常不等于`设计分辨率`（多个客户端分辨率不同）

    - **百分比坐标**：为了尽可能保证不同设备运行时效果一致，需要使用百分比坐标和屏幕自适应相关接口


- **屏幕适配优先级高于节点自身设置的大小和位置，如果设置了屏幕适配则界面显示以屏幕适配的设置为准**

- **可用接口**

| 接口方法名 | 中文说明 | 参数数量 | 参数说明 |
|-----------|---------|---------|---------|
| `set_eui_node_auto_center` | 同时设置节点居中配置（水平+垂直） | 7 | 1节点 + 2组配置（水平 垂直） |
| `set_eui_node_horizontal_auto_center` | 设置节点水平居中配置 | 4 | 1节点 + 1组配置 |
| `set_eui_node_vertical_auto_center` | 设置节点垂直居中配置 | 4 | 1节点 + 1组配置 |
| `set_eui_node_auto_adaption` | 同时设置节点边界自适应配置（左+右+上+下） | 13 | 1节点 + 4组配置（左 右 上 下） |
| `set_eui_node_left_auto_adaption` | 设置节点左侧边界自适应配置 | 4 | 1节点 + 1组配置 |
| `set_eui_node_right_auto_adaption` | 设置节点右侧边界自适应配置 | 4 | 1节点 + 1组配置 |
| `set_eui_node_top_auto_adaption` | 设置节点上侧边界自适应配置 | 4 | 1节点 + 1组配置 |
| `set_eui_node_bottom_auto_adaption` | 设置节点下侧边界自适应配置 | 4 | 1节点 + 1组配置 |

- **参数说明**

    - **一组配置**：三个变量，分别表示：
      1. `是否启用`（布尔值）
      2. `是否启用百分比`（布尔值）
      3. `具体偏移量`（数值）
          1. 居中配置中：表示子节点中心点到父节点中心点的偏移量
          2. 边缘配置中：如在左侧配置中，表示子节点左侧到父节点左侧的偏移量

    - **数值含义**：
      - 不启用百分比时，数值表示偏移像素值
      - 启用百分比时，数值表示百分比，基础范围（0到100）
          - 注意，**基准为父节点尺寸**，而**不是屏幕尺寸**
          - 100和-100就表示为父节点尺寸，两者方向不同

    - **互斥规则**：
      - 水平居中对齐和横向边缘对齐互斥
      - 垂直居中对齐和纵向边缘对齐互斥


- **🧭 偏移量方向约定**

    - **边界适配**：正值=向父节点内偏移，负值=向父节点外偏移

    - **居中适配**：和坐标系保持一致


- **代码示例**

```lua
-- 边界配置案例

local tf = math.tofixed

-- ✅ 案例1：设置某个子节点的左侧边界和父节点左侧边界完全对齐（边界重合）
GameAPI.set_eui_node_left_auto_adaption(node1, true, false, tf(0))

-- ✅ 案例2：设置某个子节点的右侧边界在父节点右侧边界外部，且相距5像素
GameAPI.set_eui_node_right_auto_adaption(node2, true, false, tf(-5))

-- ✅ 案例3：设置某个子节点的右侧边界在父节点右侧边界内部，且相距5像素
GameAPI.set_eui_node_right_auto_adaption(node2, true, false, tf(5))

-- ✅ 案例4：设置某个子节点的右侧边界在父节点内部的中心点位置
GameAPI.set_eui_node_right_auto_adaption(node2, true, true, tf(50))

-- ✅ 案例5：设置某个子节点的上侧边界在父节点上侧边界内侧，偏移父节点高度的5%
GameAPI.set_eui_node_top_auto_adaption(node5, true, true, tf(5))

-- ✅ 案例6：同时设置节点的四个方向边界的自适应配置
-- 所有边界都在父节点内侧，左侧距边界5%，右侧距边界10%，上侧距边界3%，下侧距边界8%
GameAPI.set_eui_node_auto_adaption(node6, 
    true, true, tf(5),    -- 左侧配置
    true, true, tf(10),  -- 右侧配置  
    true, true, tf(3),   -- 上侧配置
    true, true, tf(8))    -- 下侧配置


-- 中心点配置案例

-- ✅ 案例7：设置某个子节点和父节点中心点重合
GameAPI.set_eui_node_auto_center(node3, true, false, tf(0), true, false, tf(0))

-- ✅ 案例8：设置某个子节点在父节点内部水平居中，向右偏移父节点宽度的10%
GameAPI.set_eui_node_horizontal_auto_center(node4, true, true, tf(10))

-- ✅ 案例9：设置某个子节点在父节点内部垂直居中，向上偏移30像素
GameAPI.set_eui_node_vertical_auto_center(node4, true, false, tf(30))

```


## Execute 步骤详解

### 步骤一：构建 UI 层级结构树

- 创建UI前先构建出目标UI层级结构，然后基于层级结构创建UI
- 在**代码注释**中展示**UI层级树**，包括每个节点的预期坐标和大小（注意：不是控制台输出）

```lua
--[[
 创建 UI（利用嵌套层级）

 坐标系规则（锚点在节点中心）：
   节点坐标 = 自身中心锚点 到 父节点左下角 的偏移
   居中于父节点：x = 父W/2，y = 父H/2
   靠上偏移d：y = 父H - 子H/2 - d
   靠下偏移d：y = 子H/2 + d
   居左偏移d：x = 子W/2 + d
   居右偏移d：x = 父W - 子W/2 - d

 画布0  1920x1080
 ├── topBar  700x80    坐标(960, 1040)  贴顶水平居中
 │   ├── lbl_score  260x60  坐标(150, 40)   居左留20px
 │   └── lbl_timer  260x60  坐标(550, 40)   居右留20px
 ├── gridRoot  510x510  坐标(960, 500)   水平居中，垂直居中偏下
 │   ├── hole_bg_1  150x150  坐标(75,  435)  col=0,row=2(视觉顶行)
 │   │   └── mole_1  130x130  坐标(75, 75)   居中
 │   └── ... 共9个
 └── startPanel  660x300  坐标(960, 540)   屏幕正中
     ├── lbl_title       500x70  坐标(330, 235)  靠上留30px
     ├── lbl_final_score 400x60  坐标(330, 150)  垂直居中
     ├── btn_start       220x90  坐标(330,  75)  靠下留30px
     └── btn_replay      220x90  坐标(330,  75)  同位置互斥
--]]

```

### 步骤二：探索可用 API

eui相关的接口分和节点类型相挂钩

- api中带有`node`通常为通用接口，所有类型的eui节点都能使用。
- 相对的，为某个类型独有的接口。比如带label字眼的接口，为`Label`型节点专用接口。
- 只能使用真实存在的API

```bash
# 在EggyAPI.lua文件中搜索 EUI 相关 API
grep_search: "create_eui_" 或 "set_label_text" 或 "set_node_visible"

-- ❌ 不存在的 API，不要臆断
GameAPI.get_eui_node_by_id(canvasId)  -- 不存在!
GameAPI.find_eui_node(root, "Canvas")  -- 不存在!
```

### 步骤三：查找预设资源
根据需求查阅对应的预设文档：

| 需求 | 参考文档 |
|-----|---------|
| 图片预设总览 | [references/presets/image-presets.md](references/presets/image-presets.md) |
| 图片预设详细分类 | [references/presets/eui_img_presets/](references/presets/eui_img_presets/) |
| 按钮预设 | [references/presets/button-presets.md](references/presets/button-presets.md) |
| 进度条预设 | [references/presets/progress-presets.md](references/presets/progress-presets.md) |
| 所有预设 Key 值列表 | [references/preset-key-values.md](references/preset-key-values.md) |
| API速查表 | [references/api-cheatsheet.md](references/api-cheatsheet.md) |
| 签到Demo | [references/demos/checkin-demo.md](references/demos/checkin-demo.md) |

### 步骤四：快速预设速查

**图片预设 (常用):**
| 需求 | ID | 名称 | 尺寸 |
|------|-----|------|------|
| 关闭按钮图标 | 10011 | 关闭-常态 | 105x85 |
| 渐变背景 | 14588 | 渐变半透背景 | 104x174 |
| 确认弹窗 | 16347 | 蛋仔确认弹窗 | 1477x580 |
| 圆角弹窗 | 16348 | 蛋仔圆角弹窗遮罩 | 1578x682 |
| 圆形物品格 | 11084 | 纯色圆形底图 | 100x100 |
| 乐园币 | 15056 | 乐园币 | 156x156 |

**按钮预设 (常用):**
| ID | 名称 | 尺寸 | 用途 |
|-----|------|------|------|
| 10005 | 关闭 | 105x85 | 关闭按钮 |
| 11001 | 金色按钮0 | 274x122 | 确认主按钮 |
| 11002 | 蓝色按钮0 | 274x122 | 取消副按钮 |
| 10020 | 条纹金 | 300x118 | 确认按钮 |
| 10019 | 条纹蓝 | 300x118 | 取消按钮 |

**进度条预设 (常用):**
| ID | 名称 | 尺寸 |
|-----|------|------|
| 30000 | 水平进度条 | 475x26 |
| 30003 | 进度条(HP) | 506x40 |
| 20002 | 环形进度条 | 128x128 |

### 步骤五：按模式生成代码

### 创建基础 UI
```lua
local UINodes = require("Data.UINodes")
local tf = math.tofixed

--[[
UI Hierarchy Tree (Design Resolution: 1920x1080)
Canvas
├─popup_bg (preset=14588)
│  - world pos: (960, 540)
│  - size: (740, 290)
├─ btn_confirm (preset=11001)
│  - world pos: (960, 460)
│  - size: (200, 80)
├─ txt_title
│  - world pos: (960, 590)
│  - size: (300, 40)
--]]

LuaAPI.global_register_trigger_event({EVENT.GAME_INIT}, function()
    local canvas = UINodes["画布0"]
    local centerX, centerY = tf(960), tf(540)
    
    -- 创建弹窗背景
    local bg = GameAPI.create_eui_image_at_position(
        16347,              -- 预设ID: 蛋仔确认弹窗
        canvas,             -- 父节点
        centerX, centerY,   -- 位置
        tf(740), tf(290),   -- 尺寸
        "popup_bg"          -- 名称
    )
    
    -- 创建按钮
    local btn = GameAPI.create_eui_button_at_position(
        11001,              -- 预设ID: 金色按钮
        canvas,
        centerX, centerY - tf(80),
        tf(200), tf(80),
        "btn_confirm"
    )
    
    -- 创建标签（preset_id 为文本预设ID）
    local label = GameAPI.create_eui_label_at_position(
        40001,              -- 预设ID: 文本预设
        canvas,
        centerX, centerY + tf(50),
        tf(300), tf(40),
        "txt_title",
        "标题文本"
    )
end)
```

### 设置节点属性
```lua
-- 通过事件回调获取 role 实例后设置属性
local role = data.role
if role then
    role.set_node_visible(node, true)
    role.set_label_text(label, "新文本")
    role.set_button_text(btn, "确认")
end
```

### UI节点交互

通过事件系统就能让UI节点和其他模块联动起来。

| 触摸事件类型（EUITouchEventType） | 解释说明 |
| --------------------------------- | -------- |
| CLICK = 1                         | 点击     |
| PRESS = 2                         | 按下     |
| RELEASE = 3                       | 抬起     |

```lua
local UINodes = require("Data.UINodes")
local _btn =  UINodes["StartBtn"]
local _touch_event_type = 1

-- 通过下方的代码就能让指定ui节点在按下时触发特定的回调函数

---界面控件触摸交互事件
---事件主体 Default 多类型
---注册参数 _node ENode 触发事件的界面控件
---注册参数 _touch_event_type ENodeTouchEventType 触摸事件类型
---事件回调参数 role Role 触发事件的玩家
---事件回调参数 eui_node_id ENode 触发事件的界面控件
local event_id = LuaAPI.global_register_trigger_event({EVENT.EUI_NODE_TOUCH_EVENT, _btn, _touch_event_type}, function(event_name, actor, data)
	print('ui node clicked', event_name)
	print(data.role)
	print(data.eui_node_id)
end)


-- 通过下方的代码就取消前面注册的ui回调
LuaAPI.global_unregister_trigger_event(event_id)

```


### 动态列表布局
```lua
local function createGrid(parent, startX, startY, cols, rows, cellSize, gap)
    local tf = math.tofixed
    local items = {}
    
    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local x = startX + tf(col) * (cellSize + gap)
            local y = startY - tf(row) * (cellSize + gap)
            local item = GameAPI.create_eui_image_at_position(
                11084, parent, x, y, cellSize, cellSize,
                "cell_" .. (row * cols + col)
            )
            table.insert(items, item)
        end
    end
    
    return items
end
```

## 常用 API 速查

### 创建节点 (GameAPI)
| 方法 | 说明 |
|------|------|
| `create_eui_image_at_position(preset, parent, x, y, w, h, name)` | 创建图片节点 |
| `create_eui_button_at_position(preset, parent, x, y, w, h, name)` | 创建按钮节点 |
| `create_eui_label_at_position(preset, parent, x, y, w, h, name, text)` | 创建文本节点 |
| `create_eui_input_at_position(preset, parent, x, y, w, h, name, default_text)` | 创建输入框节点 |
| `create_eui_progress_at_position(preset, parent, x, y, w, h, name)` | 创建条形进度条节点 |
| `create_eui_progresstimer_at_position(preset, parent, x, y, w, h, name)` | 创建环形进度条节点 |
| `create_eui_animation_at_position(preset, parent, x, y, w, h, name)` | 创建动效节点 |
| `create_eui_bagslot_at_position(parent, x, y, w, h, preset, name)` | 创建物品格控件 |
| `create_eui_ability_at_position(preset, parent, x, y, w, h, show_unlinked, show_name, name)` | 创建技能控件 |
| `create_eui_buff_at_position(parent, x, y, w, h, name)` | 创建效果控件 |
| `create_eui_listview_at_position(parent, x, y, w, h, name)` | 创建列表节点 |
| `create_eui_clipping_at_position(parent, x, y, w, h, name, mask_image)` | 创建遮罩节点 |
| `get_eui_child_by_name(node, name)` | 按名称获取子节点 |
| `get_eui_child_by_index(node, index)` | 按索引获取子节点 |

### 设置属性 (Role)
| 方法 | 说明 |
|------|------|
| `set_node_visible(node, visible)` | 设置可见性 |
| `set_label_text(label, text)` | 设置标签文本 |
| `set_button_text(btn, text)` | 设置按钮文本 |

### 事件 (LuaAPI)
| 方法 | 说明 |
|------|------|
| `global_register_trigger_event({EVENT.GAME_INIT}, cb)` | 游戏初始化 |
| `global_register_trigger_event({EVENT.EUI_NODE_TOUCH_EVENT, node, type}, cb)` | 触摸事件 |
| `global_unregister_trigger_event(id)` | 取消事件 |

---

## 参考文档索引

以下文档是生成代码时的**唯一权威来源**，不得凭记忆或推测使用 API。

### API 文档

| 文档 | 路径 | 何时查阅 |
|------|------|---------|
| API 速查表 | `references/api-cheatsheet.md` | **每次 Execute 必读** |

### 审美规范

| 文档 | 路径 | 何时查阅 |
|------|------|---------|
| 蛋仔风格审美规范 | `references/ui-aesthetics-guide.md` | **每次 Plan 必读** |

### 预设资源文档

| 文档 | 路径 | 何时查阅 |
|------|------|---------|
| 图片预设总览 | `references/presets/image-presets.md` | 需要图片素材时 |
| 图片预设详细分类 | `references/presets/eui_img_presets/` | 需要按分类查找图片时 |
| 按钮预设 | `references/presets/button-presets.md` | 需要按钮图片时 |
| 进度条预设 | `references/presets/progress-presets.md` | 需要进度条图片时 |
| 所有预设 Key 值列表 | `references/preset-key-values.md` | 需要快速查找预设 Key 时 |
| 签到 Demo | `references/demos/checkin-demo.md` | 参考完整示例时 |

---

## Name 属性规范

为便于自动化测试和代码维护，生成 UI 节点时**必须**为关键节点设置 `Name` 属性：

| 节点类型 | 命名规则 | 示例 |
|---------|---------|------|
| 可点击按钮 | `btn_功能名` | `Name = "btn_确认"`, `Name = "btn_关闭"` |
| 面板/弹窗容器 | `panel_面板名` | `Name = "panel_商店"`, `Name = "panel_设置"` |
| 全屏遮罩 | `mask_用途` | `Name = "mask_全屏"`, `Name = "mask_弹窗背景"` |
| 进度条/CD环 | `bar_用途` / `ring_用途` | `Name = "bar_血量"`, `Name = "ring_技能CD"` |
| 文本标签（需验证内容） | `label_用途` | `Name = "label_标题"`, `Name = "label_提示"` |
| 图片（需验证状态） | `img_用途` | `Name = "img_头像"`, `Name = "img_背景"` |
| 输入框 | `input_用途` | `Name = "input_昵称"`, `Name = "input_搜索"` |
| 列表容器 | `list_用途` | `Name = "list_商品"`, `Name = "list_排行"` |
| 裁剪节点 | `clip_用途` | `Name = "clip_头像"`, `Name = "clip_内容"` |
| 粒子特效 | `fx_用途` | `Name = "fx_点击"`, `Name = "fx_命中"` |

**必须设置 Name 的节点：**
- 所有绑定了触摸事件（CLICK / PRESS / RELEASE）的节点
- 初始不可见且后续会动态显示的节点
- 需要验证状态的进度条、CD 环、文本标签
- 弹窗/面板的根容器节点

**命名约定：**
- 支持中文，保持语义清晰
- 使用下划线分隔前缀和功能名
- 避免特殊字符（如 emoji、空格）
- 同一模块内 Name 不得重复

---

## 注意事项

1. **所有数值必须 `math.tofixed()`** - 帧同步核心要求
2. **预设ID不能臆断** - 必须查阅预设文档获取
3. **API必须存在** - 生成代码前确认 API 在 EggyAPI.lua 中存在
4. **画布从 UINodes 获取** - 不要硬编码或猜测节点名
5. **全局对象不需要 require** - GameAPI、LuaAPI、EVENT、math（`Role` 需从 `data.role` 获取实例）
6. **API检查** - 生成代后再次确认是否是使用了不在 EggyAPI.lua 中出现的接口
7. **代码注释检查** - 确保在注释中输出了代码层级结构