local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")

-- 被玩家举着：引擎驱动姿势，逻辑层不主动移动。
---@class CarriedState: StateBase
local CarriedState = Class("BabyCarriedState", StateBase)

---@param agent BabyAgent
function CarriedState:Ctor(agent)
    CarriedState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
function CarriedState:enter(context)
    CarriedState.super.enter(self, context)
    local agent = self.agent
    agent.last_lift_unit = context and context.lift_unit or nil
    agent.last_role = context and context.role or nil
    agent:show_current_need()
    self:set_intent({
        move_mode = Intent.MoveMode.Carried,
        anim_base = Intent.AnimBase.CarriedPose,
        action_lock = false,
    })
    if not (context and context.suppress_lift_event) then
        agent.services.task:emit_lift_baby(agent)
    end
end

return CarriedState
