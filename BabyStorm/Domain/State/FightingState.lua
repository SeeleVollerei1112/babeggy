local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")

-- 好斗宝宝蛋打闹：原地又踢又闹，等待玩家走近「拉架」。整个会话由 FightService 驱动
-- （选定/定身拉架玩家、读轮盘方向、推进段数、结算）；本状态只声明意图：
--   停步 + 待机姿势 + 嫌弃叠加 + 动作锁（打闹是不可被普通移动打断的动作）。
-- 进入/退出与计分由 FightService 通过 BabyAgent:finish_fight / enter_idle 控制。
---@class FightingState: StateBase
local FightingState = Class("BabyFightingState", StateBase)

---@param agent BabyAgent
function FightingState:Ctor(agent)
    FightingState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
function FightingState:enter(context)
    FightingState.super.enter(self, context)
    local agent = self.agent
    agent:set_busy(true)
    agent:set_lift_enabled(false)
    self:set_intent({
        move_mode = Intent.MoveMode.Stop,
        anim_base = Intent.AnimBase.Idle,
        anim_overlay = Intent.AnimOverlay.Angry,
        action_lock = true,
    })
    agent:set_status((context and context.status_text) or "好斗宝宝在打闹！")
end

return FightingState
