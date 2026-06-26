local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")

---@class TimeoutState: StateBase
local TimeoutState = Class("BabyTimeoutState", StateBase)

---@param agent BabyAgent
function TimeoutState:Ctor(agent)
    TimeoutState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
function TimeoutState:enter(context)
    TimeoutState.super.enter(self, context)
    self.agent:begin_timeout_action()
end

return TimeoutState
