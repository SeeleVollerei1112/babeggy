local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Enum = require("BabyStorm.Config.BabyStormEnum")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")
local Rand = require("Util.Rand")

-- 空闲：原地驻留 + 就近扫描当前需求物品 + 展示需求倒计时；站够了起身漫游。
--
-- WanderingState 继承本状态：扫描 / 倒计时 / 可举起完全一样，只覆写两个点——
-- apply_move_intent（动不动）与 schedule_next（下一站去哪）。二者构成 Idle ⇄ Wandering 的走走停停循环。
---@class IdleState: StateBase
---@field _scan_elapsed Fixed
local IdleState = Class("BabyIdleState", StateBase)

---@param agent BabyAgent
function IdleState:Ctor(agent)
    IdleState.super.Ctor(self, agent)
    self._scan_elapsed = 0.0
end

---@param context BabyStateContext|nil
function IdleState:enter(context)
    IdleState.super.enter(self, context)
    local agent = self.agent
    agent:set_lift_enabled(true)
    agent:show_current_need()
    self._scan_elapsed = 0.0
    self:apply_move_intent()
    self:schedule_next()
end

-- 覆写点：本状态怎么动。
-- Idle 原地驻留——Wander 但不给 speed_ratio，MovementSystem 会把移速比率压成 0（既有设计）。
function IdleState:apply_move_intent()
    self:set_intent({
        move_mode = Intent.MoveMode.Wander,
        anim_base = Intent.AnimBase.Locomotion,
        action_lock = false,
    })
end

-- 覆写点：本状态待够了去哪。Idle 站够 idle_rest_* 秒就起身漫游。
function IdleState:schedule_next()
    local baby = self.agent.config.baby
    Timer.once(self, Rand.fixed(baby.idle_rest_min_seconds, baby.idle_rest_max_seconds), function()
        self.agent:enter_state(Enum.BabyState.Wandering)
    end)
end

---@param dt Fixed
function IdleState:update(dt)
    local agent = self.agent
    if not agent.unit then
        return
    end
    local pos = agent.unit.get_position and agent.unit.get_position()
    if not pos then
        return
    end

    -- 需求扫描（纯距离检测，Idle / Wandering 共用）：每 item_scan_interval 秒，在
    -- item_pickup_radius 内找一件匹配当前需求的物品；找到即转 SeekingItem 走过去捡，
    -- 最后 contact_radius 内兜底强制拾取。
    -- 玩家因此有两种“投喂”方式，走的是同一条路径：把物品丢在宝宝身边，或者拿着走到宝宝身边
    -- （只要物品没进玩家自己的装备槽，宝宝就照捡不误，见 ItemService:_is_on_ground）。
    -- 副作用：拿着物品路过“正好想要它”的宝宝时也会被抢，绕不过去——距离检测的必然结果。
    -- 只认地面物品（设施需玩家抱送），也只认当前需求：随手捡玩具不在这里，见 WanderingState:enter。
    self._scan_elapsed = self._scan_elapsed + dt
    if self._scan_elapsed >= agent.config.baby.item_scan_interval then
        self._scan_elapsed = 0.0
        agent:try_match_current_need_at(pos, "item_to_baby")
    end
end

return IdleState
