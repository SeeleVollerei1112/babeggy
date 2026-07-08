local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")

-- 错误物品 / 拾取失败的不满表现，短暂后回到 Idle。
---@class UpsetState: StateBase
local UpsetState = Class("BabyUpsetState", StateBase)

---@param agent BabyAgent
function UpsetState:Ctor(agent)
    UpsetState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
function UpsetState:enter(context)
    UpsetState.super.enter(self, context)
    local agent = self.agent
    local wrong_item = context and context.item or nil

    agent:set_busy(true)
    self:set_intent({
        move_mode = Intent.MoveMode.Stop,
        anim_base = Intent.AnimBase.Idle,
        anim_overlay = Intent.AnimOverlay.Angry,
        action_lock = false,
    })
    agent:set_status("不是想要的")
    agent.view_model:add_stress(1)
    if wrong_item then
        agent.services.task:emit_wrong_item(agent, wrong_item)
    end
    agent.services.score:penalize_wrong(agent.last_role)

    -- owner=self：状态 exit 时 StateBase 统一取消，不会有过期回调。
    Timer.once(self, 1.0, function()
        agent:enter_idle()
    end)
end

return UpsetState
