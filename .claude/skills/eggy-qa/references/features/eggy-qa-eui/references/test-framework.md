# 测试框架参考文档

## 框架位置

测试框架文件位于 `test/test_framework.lua`。

若不存在，在阶段三中自动创建，源码如下。

---

## 测试框架 API 速查

| 方法 | 说明 |
|------|------|
| `TF.createRunner(suiteName)` | 创建测试 runner，包含断言方法和计数器 |
| `runner:assert(name, condition, detail)` | 基础断言 |
| `runner:assertNotNil(name, value)` | 非 nil 断言（节点存在性检查） |
| `runner:assertEqual(name, actual, expected)` | 相等断言（子节点数量检查） |
| `runner:assertChildExists(name, parent, childName)` | 层级包含断言（验证 parent 下存在名为 childName 的子节点） |
| `TF.findNode(name)` | 从画布递归查找节点（by Name） |
| `TF.findNodeUnder(parent, name)` | 从指定父节点递归查找节点 |
| `TF.runSteps(runner, steps)` | 异步步骤执行器（基于 tick 帧计数） |

---

## 测试框架源码

```lua
-- test/test_framework.lua
local TF = {}

-- 初始化画布（帧同步模式）
local UINodes = require("Data.UINodes")
TF.canvas = UINodes["画布0"]

-- 递归查找节点（by Name）
-- get_eui_child_by_name 只搜直接子节点，需手动递归
local function recursiveFindNode(parent, name)
    if parent == nil then return nil end
    -- 先搜直接子节点
    local child = GameAPI.get_eui_child_by_name(parent, name)
    if child ~= nil then
        return child
    end
    -- 递归搜索所有子节点
    local children = GameAPI.get_eui_children(parent)
    if children == nil then return nil end
    for _, c in ipairs(children) do
        local found = recursiveFindNode(c, name)
        if found ~= nil then
            return found
        end
    end
    return nil
end

-- 从画布递归查找节点
function TF.findNode(name)
    return recursiveFindNode(TF.canvas, name)
end

-- 从指定父节点递归查找节点
function TF.findNodeUnder(parent, name)
    return recursiveFindNode(parent, name)
end

-- 创建测试 runner
function TF.createRunner(suiteName)
    local runner = {
        suiteName = suiteName,
        passed = 0,
        failed = 0,
    }

    print("[TEST:BEGIN] " .. suiteName)

    function runner:assert(name, condition, detail)
        if condition then
            self.passed = self.passed + 1
            print("[TEST:PASS] " .. name)
        else
            self.failed = self.failed + 1
            local msg = "[TEST:FAIL] " .. name
            if detail then
                msg = msg .. " | " .. tostring(detail)
            end
            print(msg)
        end
    end

    function runner:assertNotNil(name, value)
        self:assert(name, value ~= nil, "got nil")
    end

    function runner:assertEqual(name, actual, expected, detail)
        local ok = actual == expected
        local info = detail or ("expected " .. tostring(expected) .. " actual " .. tostring(actual))
        self:assert(name, ok, info)
    end

    -- 层级包含断言：验证 parent 的直接子节点中存在名为 childName 的节点
    function runner:assertChildExists(name, parent, childName)
        if parent == nil then
            self:assert(name, false, "parent is nil")
            return
        end
        local child = GameAPI.get_eui_child_by_name(parent, childName)
        self:assert(name, child ~= nil, "child '" .. childName .. "' not found under parent")
    end

    function runner:finish()
        print("[TEST:END] " .. self.suiteName ..
            " | passed=" .. self.passed ..
            " failed=" .. self.failed)
    end

    return runner
end

-- 异步步骤执行器（基于 tick 帧计数）
-- 帧同步模式每秒 30 帧，使用 set_tick_handler 实现延时
-- steps: { { name, delay, fn } }  delay 单位为秒
function TF.runSteps(runner, steps)
    local frameCount = 0
    local FPS = 30
    local currentStepIndex = 1
    local totalDelayFrames = 0

    -- 预计算每个步骤的触发帧
    local stepTriggerFrames = {}
    for i, step in ipairs(steps) do
        totalDelayFrames = totalDelayFrames + math.floor((step.delay or 0) * FPS)
        stepTriggerFrames[i] = totalDelayFrames
    end

    local totalSteps = #steps

    LuaAPI.set_tick_handler(function()
        frameCount = frameCount + 1

        if currentStepIndex <= totalSteps then
            if frameCount >= stepTriggerFrames[currentStepIndex] then
                local step = steps[currentStepIndex]
                local ok, err = pcall(step.fn, runner)
                if not ok then
                    print("[TEST:ERROR] " .. tostring(err))
                    runner.failed = runner.failed + 1
                end
                currentStepIndex = currentStepIndex + 1

                -- 最后一步完成后输出汇总
                if currentStepIndex > totalSteps then
                    runner:finish()
                    -- 清除 tick handler
                    LuaAPI.set_tick_handler(nil, nil)
                end
            end
        end
    end, nil)
end

return TF
```
