local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

-- 捣乱：需求迟迟没被满足（倒计时低于阈值）时，宝宝主动跑到就近一个点
-- 做一次「打翻东西」的动作，制造一点混乱，随后回到 Idle 继续等待（倒计时不受影响，
-- 最终仍会超时哭闹）。触发由 BabyAgent:_maybe_start_mischief 把关（每个需求仅一次、仅 Idle）。
--
-- 两段 phase：
--   seeking —— 朝捣乱点移动（MoveToTarget），到点或兜底超时后转入 acting。
--   acting  —— 停步 + 动作锁，播放打翻动作；动作结束触发一次扰动 hook 后回到 Idle。
--
-- 表现层（脏乱特效、被打翻的道具、气泡音效）留到后续：见 _disturb 的扩展点。
---@class MischiefState: StateBase
---@field _elapsed Fixed
---@field _act_remaining Fixed
local MischiefState = Class("BabyMischiefState", StateBase)

---@param agent BabyAgent
function MischiefState:Ctor(agent)
    MischiefState.super.Ctor(self, agent)
    self._elapsed = 0.0
    self._act_remaining = 0.0
end

---@param context BabyStateContext|nil
function MischiefState:enter(context)
    MischiefState.super.enter(self, context)
    local agent = self.agent

    -- 选一个就近捣乱点（复用场地随机点）。取不到点就放弃捣乱，回到 Idle。
    local target = agent.services.arena and agent.services.arena:random_point() or nil
    if not target then
        agent:enter_idle()
        return
    end
    local pos = agent.unit and agent.unit.get_position and agent.unit.get_position()
    local ground_y = pos and pos.y or target.y
    agent.move_target = math.Vector3(target.x, ground_y, target.z)

    -- 捣乱期间仍可被抱起打断（玩家可以把宝宝抱走制止破坏）。
    agent:set_lift_enabled(true)
    self._elapsed = 0.0
    self.phase = "seeking"
    self:set_intent({
        move_mode = Intent.MoveMode.MoveToTarget,
        anim_base = Intent.AnimBase.Locomotion,
        action_lock = false,
    })
    agent:set_status("想搞点小破坏…")
end

---@param dt Fixed
function MischiefState:update(dt)
    if self.phase == "seeking" then
        self:_update_seeking(dt)
    elseif self.phase == "acting" then
        self._act_remaining = self._act_remaining - dt
        if self._act_remaining <= 0 then
            self:_finish()
        end
    end
end

---@private
---@param dt Fixed
function MischiefState:_update_seeking(dt)
    local agent = self.agent
    self._elapsed = self._elapsed + dt

    local arrived = false
    local pos = agent.unit and agent.unit.get_position and agent.unit.get_position()
    if pos and agent.move_target then
        local radius = agent.config.baby.contact_radius
        if UnitUtil.distance_xz_sq(pos, agent.move_target) <= radius * radius then
            arrived = true
        end
    end

    -- 到点、或兜底超时（寻路卡住）后，就地开始打翻动作。
    if arrived or self._elapsed >= agent.config.baby.mischief_seek_timeout then
        self:_begin_act()
    end
end

---@private
function MischiefState:_begin_act()
    local agent = self.agent
    self.phase = "acting"
    self._act_remaining = agent.config.baby.mischief_act_seconds
    -- 打翻是非移动动作：必须停步 + 动作锁（红线 §4）。
    self:set_intent({
        move_mode = Intent.MoveMode.Stop,
        anim_base = Intent.AnimBase.Pickup,
        action_lock = true,
    })
    agent:set_status("哼！打翻你！")
    self:_disturb()
end

---@private
-- 捣乱的实际扰动效果。表现层 + 道具尚未接入：此处只记录日志作为扩展点。
-- 后续可在这里生成脏乱物/打翻场景道具、发任务事件（宝宝捣乱）等。
function MischiefState:_disturb()
    Log.info("baby", self.agent.index, "mischief disturb at", self.agent.move_target)
    -- TODO(表现层/道具)：生成脏乱物、打翻就近道具、触发捣乱任务事件。
end

---@private
function MischiefState:_finish()
    -- 回到 Idle：需求倒计时仍在走，最终会超时进入 Cry。
    self.agent:enter_idle()
end

return MischiefState
