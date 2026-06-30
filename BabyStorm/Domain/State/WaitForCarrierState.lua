local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")

-- 一般宝宝蛋「指定人物抱起」需求的等待状态：宝宝原地等待选定的目标玩家来抱。
-- 满足/拒绝的判定在 BabyAgent:on_lifted_begin（被抱起事件）里处理：
--   * 指定玩家抱起 → complete_carry_need（满足）。
--   * 其他玩家抱起 → reject_carry_lift（放下 + 不满），仍停留在本状态。
-- 本状态只声明「停步 + 待机 + 可被抱起」的意图，不碰移动/动画引擎。
---@class WaitForCarrierState: StateBase
local WaitForCarrierState = Class("BabyWaitForCarrierState", StateBase)

---@param agent BabyAgent
function WaitForCarrierState:Ctor(agent)
    WaitForCarrierState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
function WaitForCarrierState:enter(context)
    WaitForCarrierState.super.enter(self, context)
    local agent = self.agent
    agent:set_busy(false)
    agent:set_lift_enabled(true)
    self:set_intent({
        move_mode = Intent.MoveMode.Stop,
        anim_base = Intent.AnimBase.Idle,
        action_lock = false,
    })
    agent:set_status((agent.current_need and agent.current_need.need_text) or "想让指定的人抱抱")
end

return WaitForCarrierState
