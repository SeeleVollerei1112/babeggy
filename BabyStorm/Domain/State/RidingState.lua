local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")

---@class RidingState: StateBase
local RidingState = Class("BabyRidingState", StateBase)

---@param agent BabyAgent
function RidingState:Ctor(agent)
    RidingState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
function RidingState:enter(context)
    RidingState.super.enter(self, context)
    self.agent:begin_ride(context)
end

---@param context BabyStateContext|nil
function RidingState:exit(context)
    RidingState.super.exit(self, context)
    -- 无论以何种方式离开骑行（满足/放弃/被打断），都恢复碰撞、停止循环
    self.agent:cleanup_ride()
end

return RidingState
