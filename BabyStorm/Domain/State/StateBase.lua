local Class = require("BaseClass")
local Enum = require("BabyStorm.Config.BabyStormEnum")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Log = require("Util.Log")

-- 行为状态基类。每个状态是「解决当前需求的一段流程」。
--
-- 契约（见 .claude/rules/baby-ai-architecture.md §4）：
--   enter 时必须调用 self:set_intent{...} 写全四个意图字段，缺省值兜底，
--   绝不沿用上一个状态的残留意图。
--   有多步流程的状态用 self.phase + update(dt) 推进，不要关闭 AI 等动画。
--   动画/抱起等事件经 handle_event(event) 进入，由当前状态决定后果。
--
-- 行为状态只声明意图；真正的移动/动画由 MovementSystem / AnimationSystem reconcile。
local LOCK_REASON = "behavior"

---@class StateBase
---@field agent BabyAgent
---@field _state_id integer
---@field _active boolean
---@field phase string|nil
local StateBase = Class("BabyStateBase")

---@param agent BabyAgent
function StateBase:Ctor(agent)
    self.agent = agent
    self._state_id = 0
    self._active = false
    self.phase = nil
end

---@param state_id integer
function StateBase:init(state_id)
    self._state_id = state_id
end

---@param context BabyStateContext|nil
function StateBase:enter(context)
    self._active = true
    self.phase = nil
    Log.info("baby", self.agent.index, "enter", Enum.get_state_name(self._state_id))
end

---@param dt Fixed
function StateBase:update(dt)
end

---@param event table
function StateBase:handle_event(event)
end

---@param context BabyStateContext|nil
function StateBase:exit(context)
    self._active = false
    -- 杜绝跨状态泄漏：行为锁随状态退出而释放。
    self.agent.action_lock:release(LOCK_REASON)
end

-- 声明本状态的意图。四字段全写，由 Movement/Animation 下一帧 reconcile。
---@param opts { move_mode: string, anim_base: string|nil, anim_overlay: string|nil, anim_param: BabyAnimParam|nil, action_lock: boolean|nil }
function StateBase:set_intent(opts)
    local agent = self.agent
    agent.move_mode = opts.move_mode or Intent.MoveMode.Stop
    agent.anim_base = opts.anim_base or Intent.AnimBase.Idle
    agent.anim_overlay = opts.anim_overlay
    agent.anim_param = opts.anim_param

    if opts.action_lock then
        agent.action_lock:acquire(LOCK_REASON)
    else
        agent.action_lock:release(LOCK_REASON)
    end
    -- 强制 Movement/Animation 下一帧按新意图重新对齐。
    agent:invalidate_systems()
end

---@return integer
function StateBase:get_state_id()
    return self._state_id
end

---@return boolean
function StateBase:is_active()
    return self._active
end

return StateBase
