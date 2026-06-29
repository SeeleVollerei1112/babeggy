local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")

-- 动画系统：宝宝侧**唯一**强制播放/停止全身动作的地方。
-- 行为层只写 agent.anim_base（+ 强制动作的 agent.anim_param），由本系统每 tick reconcile。
--
-- 关键点：把历史上「每秒重发同一个全身动作续命」的 hack 收敛进来——
--   全身动作（play_body_anim_by_id，如哭闹 23）约 1 秒后会被引擎待机动画顶掉，
--   因此 forced 动作由本系统内部每 refresh_interval 重发一次，对行为层透明。
--   行为层只需声明「现在是 Cry」，被举起时改声明 CarriedPose，本系统自然停掉重发。
--
-- anim_base 分两类：
--   非强制（Idle/Locomotion/Pickup/CarriedPose）：引擎默认表现，本系统不强制播放，
--       但负责把上一个 forced 动作显式停掉。
--   强制（Cry/Ride/Seat）：持续强制播放 agent.anim_param 描述的动作。
--       注：Ride/Seat 当前由 FacilityService 直接驱动，本系统保留通用支持。
--
-- anim_param 形如 { mode = "body_id"|"anim_key", id = integer }。
---@class BabyAnimParam
---@field mode "body_id"|"anim_key"
---@field id integer

---@class AnimationSystem
---@field _agent BabyAgent
---@field _last_base string|nil
---@field _forced BabyAnimParam|nil
---@field _refresh_elapsed Fixed
local AnimationSystem = Class("BabyAnimationSystem")

local FORCED_BASE = {
    [Intent.AnimBase.Cry] = true,
    [Intent.AnimBase.Ride] = true,
    [Intent.AnimBase.Seat] = true,
}

local REFRESH_INTERVAL = 1.0 -- 全身动作每秒重发一次，覆盖被待机顶掉的间隙
local PLAY_TIME = 2.0        -- 单次播放时长，长于重发间隔以保证无缝衔接

---@param agent BabyAgent
function AnimationSystem:Ctor(agent)
    self._agent = agent
    self._last_base = nil
    self._forced = nil
    self._refresh_elapsed = 0.0
end

---@param dt Fixed
function AnimationSystem:reconcile(dt)
    local agent = self._agent
    local unit = agent.unit
    if not unit then
        return
    end

    local base = agent.anim_base or Intent.AnimBase.Idle
    local param = agent.anim_param

    if base ~= self._last_base or not self:_same_param(param) then
        -- base / 动作描述变了：先停掉旧的 forced 动作，再按需起新的。
        self:_stop_forced(unit)
        self._last_base = base
        if FORCED_BASE[base] and param then
            self._forced = { mode = param.mode, id = param.id }
            self._refresh_elapsed = 0.0
            self:_play_forced(unit, self._forced)
        end
        return
    end

    -- base 未变：forced 动作按 refresh 间隔续命。
    if self._forced then
        self._refresh_elapsed = self._refresh_elapsed + dt
        if self._refresh_elapsed >= REFRESH_INTERVAL then
            self._refresh_elapsed = 0.0
            self:_play_forced(unit, self._forced)
        end
    end
end

---@private
---@param param BabyAnimParam|nil
---@return boolean
function AnimationSystem:_same_param(param)
    local cur = self._forced
    if not cur and not param then
        return true
    end
    if not cur or not param then
        return false
    end
    return cur.mode == param.mode and cur.id == param.id
end

---@private
---@param unit Unit|LifeEntity
---@param param BabyAnimParam
function AnimationSystem:_play_forced(unit, param)
    -- 先清掉因 AI 移动而被屏蔽的动画，确保强制动作能播出来。
    if unit.clear_banned_anim then
        pcall(function() unit.clear_banned_anim() end)
    end
    if param.mode == "anim_key" and unit.force_play_animation_by_anim_key then
        pcall(function()
            unit.force_play_animation_by_anim_key(param.id, 0.0, PLAY_TIME, 1.0, true)
        end)
    elseif param.mode == "body_id" and unit.play_body_anim_by_id then
        pcall(function()
            unit.play_body_anim_by_id(param.id, 0.0, PLAY_TIME, true)
        end)
    end
end

---@private
---@param unit Unit|LifeEntity
function AnimationSystem:_stop_forced(unit)
    local forced = self._forced
    if not forced then
        return
    end
    self._forced = nil
    if forced.mode == "body_id" then
        -- 只停这个全身动作的 id；绝不能用全局 stop_anim，否则会把被举起姿势一并重置成站立。
        if unit.stop_play_body_anim_by_id then
            pcall(function() unit.stop_play_body_anim_by_id(forced.id) end)
        elseif unit.stop_play_body_anim_with_id then
            pcall(function() unit.stop_play_body_anim_with_id(forced.id) end)
        elseif unit.stop_play_body_anim then
            pcall(function() unit.stop_play_body_anim() end)
        end
    else -- anim_key（force_play）
        if unit.stop_anim then
            pcall(function() unit.stop_anim() end)
        end
    end
end

-- 状态切换 / lock 变化后强制下一帧重新评估。
function AnimationSystem:invalidate()
    self._last_base = nil
end

-- agent destroy 时确保停掉残留的强制动作。
function AnimationSystem:cleanup()
    local unit = self._agent.unit
    if unit then
        self:_stop_forced(unit)
    end
    self._last_base = nil
end

return AnimationSystem
