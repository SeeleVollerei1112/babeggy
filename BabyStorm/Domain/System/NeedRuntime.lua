local Class = require("BaseClass")
local Timer = require("BabyStorm.Core.Timer")

-- 需求运行时：持有「当前需求的耐心倒计时」，由 Timer 每秒事件驱动（替代逐帧轮询累计）。
-- 需求数据本身仍由 NeedService/NeedResolver 提供；本类只管当前需求的生命周期计时。
--
-- 用法：
--   start(seconds, callbacks)  开始倒计时。每整秒回调 on_tick(remaining)（剩余 >0 时，
--                              用于刷新气泡倒计时）；归零时先 cancel 再回调 on_timeout
--                              （用于切 Cry 状态；先 cancel 保证回调里可安全地重新 start）。
--   cancel()                   停止倒计时（需求被满足/进入长互动时）
--   get_remaining()            剩余整秒，用于状态展示

---@class NeedRuntimeCallbacks
---@field on_tick fun(remaining: integer)
---@field on_timeout fun()

---@class NeedRuntime
---@field _active boolean
---@field _remaining integer
---@field _timer TimerHandle|nil
local NeedRuntime = Class("BabyNeedRuntime")

function NeedRuntime:Ctor()
    self._active = false
    self._remaining = 0
    self._timer = nil
end

---@param seconds integer
---@param callbacks NeedRuntimeCallbacks
function NeedRuntime:start(seconds, callbacks)
    self:cancel()
    self._active = true
    self._remaining = seconds
    self._timer = Timer.every(self, 1.0, function()
        self._remaining = self._remaining - 1
        if self._remaining <= 0 then
            -- 先 cancel 再回调：on_timeout 里往往会切状态/重新开始倒计时。
            self:cancel()
            callbacks.on_timeout()
        else
            callbacks.on_tick(self._remaining)
        end
    end)
end

function NeedRuntime:cancel()
    self._active = false
    self._remaining = 0
    Timer.cancel(self._timer)
    self._timer = nil
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

return NeedRuntime
