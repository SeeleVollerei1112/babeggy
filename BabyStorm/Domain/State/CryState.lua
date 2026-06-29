local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Log = require("Util.Log")

-- 需求超时哭闹（原 Timeout）。哭闹期间：
--   * 在地面：停步 + 持续哭闹动作（action_lock + 强制全身动作，由 AnimationSystem 续命）。
--   * 被举起：交给引擎被举起姿势，停掉哭闹动作、释放移动锁（on_lifted）。放下再恢复（on_dropped）。
--   * 补救窗口：未被举起时，每 tick 仍判断当前需求是否被就近满足。
--   * 倒计时归零：选下一个需求，回到 Carried（仍被举着）或 Idle。
--
-- 关键：不再「停 AI 等动画」。被举/放下只是重新声明意图，移动锁与哭闹动作由系统 reconcile。
---@class CryState: StateBase
---@field _remaining integer
---@field _accum Fixed
local CryState = Class("BabyCryState", StateBase)

---@param agent BabyAgent
function CryState:Ctor(agent)
    CryState.super.Ctor(self, agent)
    self._remaining = 0
    self._accum = 0.0
end

---@return BabyAnimParam
function CryState:_cry_anim_param()
    return { mode = "body_id", id = self.agent.config.baby.timeout_action_id or 23 }
end

-- 地面哭闹：停步、锁动作、持续播放哭闹全身动作。
function CryState:_apply_ground_cry()
    self:set_intent({
        move_mode = Intent.MoveMode.Stop,
        anim_base = Intent.AnimBase.Cry,
        anim_param = self:_cry_anim_param(),
        anim_overlay = Intent.AnimOverlay.Angry,
        action_lock = true,
    })
end

-- 被举起哭闹：引擎驱动姿势，停掉哭闹动作、释放移动锁。
function CryState:_apply_carried_cry()
    self:set_intent({
        move_mode = Intent.MoveMode.Carried,
        anim_base = Intent.AnimBase.CarriedPose,
        anim_overlay = Intent.AnimOverlay.Angry,
        action_lock = false,
    })
end

---@param context BabyStateContext|nil
function CryState:enter(context)
    CryState.super.enter(self, context)
    local agent = self.agent

    agent:set_busy(true)
    agent.view_model:add_stress(1)
    agent.pending_item = nil
    agent.pending_purpose = nil
    agent.pickup_target = nil
    agent.is_rejecting = false

    if agent.active_facility then
        agent.services.facility:end_interaction(agent, agent.active_facility)
        agent.active_facility = nil
    end

    -- 哭闹期间仍可被抱起（补救）。
    agent:set_lift_enabled(true)

    self._remaining = agent:get_timeout_action_seconds()
    self._accum = 0.0
    Log.info("baby", agent.index, "cry", self._remaining)

    if agent:_is_lifted_now() then
        -- 抱着进入哭闹：走被举姿势，并按概率拒绝本次抱起。
        self:_apply_carried_cry()
        if agent:should_reject_timeout_lift() then
            local rejected = agent:reject_timeout_lift_attempt(agent.last_lift_unit)
            Log.info("baby", agent.index, "reject carried cry lift", rejected)
        end
    else
        self:_apply_ground_cry()
    end
end

---@param dt Fixed
function CryState:update(dt)
    local agent = self.agent

    -- 补救窗口：未被举起时持续判断当前需求是否被就近满足。
    if not agent:_is_lifted_now() then
        local pos = agent.unit and agent.unit.get_position and agent.unit.get_position()
        if pos and agent:try_match_current_need_at(pos, "item_to_baby") then
            return -- 已切到寻物/设施状态
        end
    end

    self._accum = self._accum + dt
    while self._accum >= 1.0 do
        self._accum = self._accum - 1.0
        self._remaining = self._remaining - 1
        if self._remaining <= 0 then
            self:_finish()
            return
        end
    end
    agent:set_status("没满足！" .. tostring(self._remaining) .. "秒")
end

-- 被抱起（agent.on_lifted_begin 在 Cry 期间调用）。
function CryState:on_lifted()
    self:_apply_carried_cry()
end

-- 放下且未匹配到目标（agent.on_lifted_end 在 Cry 期间调用）：恢复地面哭闹。
function CryState:on_dropped()
    self:_apply_ground_cry()
end

---@private
function CryState:_finish()
    local agent = self.agent
    local lifted = agent:_is_lifted_now()
    local lift_unit = agent.last_lift_unit
    local role = agent.last_role

    agent:choose_next_need()
    if lifted then
        agent:enter_state(agent.enum.BabyState.Carried, {
            lift_unit = lift_unit,
            role = role,
            suppress_lift_event = true,
        }, true)
    else
        agent:enter_state(agent.enum.BabyState.Idle, nil, true)
    end
end

return CryState
