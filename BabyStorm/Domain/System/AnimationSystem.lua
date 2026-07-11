local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")

-- 动画系统：宝宝侧**唯一**强制播放/停止全身动作的地方（含设施坐姿/骑行的引擎调用）。
--
-- 两层驱动，外部强制层优先：
--   1) 意图层：行为层只写 agent.anim_base（+ 强制动作的 agent.anim_param），
--      invalidate() 立即对齐，是唯一的对齐入口。
--   2) 外部强制层：force_play(param, reason) / release(reason)，供 Interaction 子状态
--      （设施坐姿/骑行/躺床）使用。外部激活期间意图层不播/不停任何动作；
--      release 后重新按意图对齐。同一时刻只有一个外部 force（新的顶掉旧的）。
--
-- 关键点：把历史上「每秒重发同一个全身动作续命」的 hack 收敛进来——
--   全身动作（play_body_anim_by_id，如哭闹 23）约 1 秒后会被引擎待机动画顶掉，
--   因此持续型（sustain）动作由本系统 Timer 每 REFRESH_INTERVAL 重发一次，对行为层透明。
--   行为层只需声明「现在是 Cry」，被举起时改声明 CarriedPose，本系统自然停掉重发。
--
-- anim_base 分两类：
--   非强制（Idle/Locomotion/Pickup/CarriedPose）：引擎默认表现，本系统不强制播放，
--       但负责把上一个 forced 动作显式停掉。
--   强制（Cry/Ride/Seat）：持续强制播放 agent.anim_param 描述的动作。
--       注：Ride/Seat 当前由 Interaction 子状态经 force_play 外部层驱动，意图层保留通用支持。

---意图层强制动作描述。
---@class BabyAnimParam
---@field mode "body_id"|"anim_key"
---@field id integer

---外部强制播放参数（force_play）。
---@class BabyForcePlayParam
---@field mode "body_id"|"anim_key"
---@field id integer
---@field duration Fixed|nil  -- sustain=false 时的单次播放时长（设施坐姿/骑行「一次播够整段」的既有用法）
---@field sustain boolean|nil -- true 走续命循环（同 Cry）；缺省 false 单次播放

---@class AnimationSystem
---@field _agent BabyAgent
---@field _applied_base string|nil
---@field _forced BabyAnimParam|nil
---@field _external { mode: "body_id"|"anim_key", id: integer, reason: string, sustain: boolean }|nil
---@field _refresh_timer TimerHandle|nil
local AnimationSystem = Class("BabyAnimationSystem")

local FORCED_BASE = {
    [Intent.AnimBase.Cry] = true,
    [Intent.AnimBase.Ride] = true,
    [Intent.AnimBase.Seat] = true,
}

local REFRESH_INTERVAL = 1.0 -- 持续型全身动作每秒重发一次，覆盖被待机顶掉的间隙
local PLAY_TIME = 2.0        -- 续命单次播放时长，长于重发间隔以保证无缝衔接

---@param agent BabyAgent
function AnimationSystem:Ctor(agent)
    self._agent = agent
    self._applied_base = nil
    self._forced = nil
    self._external = nil
    self._refresh_timer = nil
end

-- 立即按当前意图对齐（意图变更后的正路入口）。
function AnimationSystem:invalidate()
    self._applied_base = nil
    self:_align()
end

---@private
function AnimationSystem:_align()
    local agent = self._agent
    local unit = agent.unit
    if not unit then
        return
    end
    -- 外部强制层激活期间，意图层不播/不停任何动作（release 后重新对齐）。
    if self._external then
        return
    end

    local base = agent.anim_base or Intent.AnimBase.Idle
    local param = FORCED_BASE[base] and agent.anim_param or nil
    if base == self._applied_base and self:_same_param(param) then
        return
    end

    -- base / 动作描述变了：先停掉旧的 forced 动作，再按需起新的。
    self:_stop_forced(unit)
    self._applied_base = base
    if param then
        self._forced = { mode = param.mode, id = param.id }
        self:_play(unit, self._forced, PLAY_TIME)
        self:_start_refresh()
    end
end

-- ============================================================
-- 外部强制播放层（Interaction 子状态使用）
-- ============================================================

---外部强制播放一个动作，reason 用于配对 release。
---sustain=false（缺省）：单次播放，播放时长用 param.duration（设施坐姿/骑行既有用法）；
---sustain=true：走续命循环（同 Cry）。
---@param param BabyForcePlayParam
---@param reason string
function AnimationSystem:force_play(param, reason)
    local unit = self._agent.unit
    if not unit then
        return
    end
    -- 同一时刻只有一个外部 force：新的顶掉旧的，先停旧的。
    self:_stop_external(unit)
    -- 压掉意图层 forced（含续命循环）；release 后由 _align 按意图重新对齐。
    self:_stop_forced(unit)
    self._applied_base = nil

    self._external = {
        mode = param.mode,
        id = param.id,
        reason = reason,
        sustain = param.sustain == true,
    }
    if self._external.sustain then
        self:_play(unit, self._external, PLAY_TIME)
        self:_start_refresh()
    else
        -- 一次播够整段时长（原 FacilityService 坐姿/骑行写法）。
        self:_play(unit, self._external, (param.duration or 0.0) + 0.0)
    end
end

---停止外部强制播放。reason 匹配才停（防止别的调用方误停）。
---@param reason string
function AnimationSystem:release(reason)
    if not (self._external and self._external.reason == reason) then
        return
    end
    local unit = self._agent.unit
    if unit then
        self:_stop_external(unit)
    else
        self._external = nil
        self:_cancel_refresh()
    end
    -- 外部层退场：重新按意图对齐。
    self:invalidate()
end

-- ============================================================
-- 引擎调用（唯一入口）
-- ============================================================

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
---@param param { mode: string, id: integer }
---@param play_time Fixed
function AnimationSystem:_play(unit, param, play_time)
    -- 先清掉因 AI 移动而被屏蔽的动画，确保强制动作能播出来。
    unit.clear_banned_anim()
    if param.mode == "anim_key" then
        unit.force_play_animation_by_anim_key(param.id, 0.0, play_time, 1.0, true)
    else -- body_id
        unit.play_body_anim_by_id(param.id, 0.0, play_time, true)
    end
end

---@private
---@param unit Unit|LifeEntity
---@param param { mode: string, id: integer }
function AnimationSystem:_stop(unit, param)
    if param.mode == "body_id" then
        -- 只停这个全身动作的 id；绝不能用全局 stop_anim 停 body_id 动作，
        -- 否则会把被举起姿势一并重置成站立。
        unit.stop_play_body_anim_by_id(param.id)
    else -- anim_key（force_play）
        unit.stop_anim()
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
    self:_cancel_refresh()
    self:_stop(unit, forced)
end

---@private
---@param unit Unit|LifeEntity
function AnimationSystem:_stop_external(unit)
    local external = self._external
    if not external then
        return
    end
    self._external = nil
    self:_cancel_refresh()
    self:_stop(unit, external)
end

-- 续命循环：每 REFRESH_INTERVAL 重发当前持续型动作（外部 sustain 优先，其次意图 forced）。
-- 同一时刻只有一个持续型动作，共用一个 timer。
---@private
function AnimationSystem:_start_refresh()
    self:_cancel_refresh()
    self._refresh_timer = Timer.every(self, REFRESH_INTERVAL, function()
        local unit = self._agent.unit
        local param = self._external or self._forced
        if unit and param then
            self:_play(unit, param, PLAY_TIME)
        end
    end)
end

---@private
function AnimationSystem:_cancel_refresh()
    Timer.cancel(self._refresh_timer)
    self._refresh_timer = nil
end

-- agent destroy 时清场：停外部 force + 停意图 forced + 取消名下全部定时器。
function AnimationSystem:cleanup()
    local unit = self._agent.unit
    if unit then
        -- destroy 兜底：回合收尾时宝宝单位可能已被引擎回收，停动作报错直接吞掉。
        pcall(function()
            self:_stop_external(unit)
            self:_stop_forced(unit)
        end)
    end
    self._external = nil
    self._forced = nil
    self._applied_base = nil
    Timer.cancel_all(self)
    self._refresh_timer = nil
end

return AnimationSystem
