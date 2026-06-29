local Class = require("BaseClass")

-- 需求运行时：持有「当前需求的耐心倒计时」并按 tick 推进（替代自调度的 call_delay_time）。
-- 需求数据本身仍由 NeedService/NeedResolver 提供；本类只管当前需求的生命周期计时。
--
-- 用法：
--   start(seconds)      开始倒计时
--   update(dt) -> evt   每 tick 调用；返回 { ticked=bool, timed_out=bool }
--                       ticked    = 跨过了一个整秒（用于刷新气泡倒计时）
--                       timed_out = 倒计时归零（用于切 Cry 状态）
--   cancel()            停止倒计时（需求被满足/进入长互动时）
--   get_remaining()     剩余整秒，用于状态展示
---@class NeedRuntime
---@field _active boolean
---@field _remaining integer
---@field _accum Fixed
local NeedRuntime = Class("BabyNeedRuntime")

function NeedRuntime:Ctor()
    self._active = false
    self._remaining = 0
    self._accum = 0.0
end

---@param seconds integer
function NeedRuntime:start(seconds)
    self._active = true
    self._remaining = seconds
    self._accum = 0.0
end

function NeedRuntime:cancel()
    self._active = false
    self._remaining = 0
    self._accum = 0.0
end

---@return boolean
function NeedRuntime:is_active()
    return self._active
end

---@return integer|nil
function NeedRuntime:get_remaining()
    if not self._active then
        return nil
    end
    return self._remaining
end

---@param dt Fixed
---@return { ticked: boolean, timed_out: boolean }
function NeedRuntime:update(dt)
    if not self._active then
        return { ticked = false, timed_out = false }
    end

    self._accum = self._accum + dt
    if self._accum < 1.0 then
        return { ticked = false, timed_out = false }
    end

    -- 跨过整秒边界（一帧通常只跨一个，循环兜底极端 dt）。
    local ticked = false
    while self._accum >= 1.0 and self._active do
        self._accum = self._accum - 1.0
        self._remaining = self._remaining - 1
        ticked = true
        if self._remaining <= 0 then
            self._active = false
            return { ticked = ticked, timed_out = true }
        end
    end
    return { ticked = ticked, timed_out = false }
end

return NeedRuntime
