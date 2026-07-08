local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")
local Rand = require("Util.Rand")

-- 移动系统：全工程**唯一**真正改变宝宝位置 / 下发移动指令 / 开关 AI 的地方。
-- 行为层只写 agent.move_mode（+ move_target / pickup_target / wander_params）。
--
-- 运作模型（事件驱动）：
--   invalidate()   立即按当前 move_mode / action_lock 对齐（意图变更的正路）。
--   reconcile(dt)  空转兜底：仅在「已应用模式 ≠ 意图模式」时补一次对齐，Phase 6 摘除。
--   周期性动作（巡逻换点、速度重申）挂 Timer，模式退出/锁定时取消。
--
-- 行为对照（保持历史行为）：
--   Stop         停在原地。
--   Wander       巡逻：进入时立刻发第一个巡逻点，之后每 interval 换一个点。
--                参数缺省时 move_speed 比率被压成 0，宝宝实际几乎不位移——这是既有设计
--                （宝宝平时驻留，只有取物/被抱时才动）；调用方可通过 wander_params
--                给出锚点小半径挪动 / 真实速度的参数化巡逻。
--   PickupTarget 朝 agent.pickup_target（装备）寻路并拾取，速度比率提到 pickup_move_speed_ratio。
--   MoveToTarget 朝 agent.move_target（坐标）移动（预留）。
--   Carried      被举起：引擎驱动，逻辑层不发任何移动指令。
--   Scripted     位移由 Driver 接管：不发任何移动指令，只记录模式。
--
-- ActionLock 锁定时强制 Stop，不发任何移动指令。

---宝宝巡逻（Wander）参数。全部可缺省，全缺省即历史 Idle 巡逻行为。
---@class BabyWanderParams
---@field anchor Vector3|nil      -- 巡逻锚点；nil 时用 arena:random_point()
---@field radius Fixed|nil        -- 与 anchor 搭配：巡逻点 = anchor 的 x/z 各偏移 ±radius（小步挪动语义）
---@field speed_ratio Fixed|nil   -- 移速比率；缺省 0.0（原地驻留，既有设计）
---@field interval Fixed|nil      -- 换点间隔；缺省 config.baby.patrol_interval
---@field threshold Fixed|nil     -- 到点判定阈值；缺省 config.baby.patrol_threshold

-- PickupTarget 期间重申速度比率的间隔：锁解除时 ActionLock 会把 move_speed 恢复成 1.0，
-- 若不周期性重申，取物速度会被悄悄抹掉（原来是每帧重申）。
local PICKUP_SPEED_REASSERT_INTERVAL = 0.5

---@class MovementSystem
---@field _agent BabyAgent
---@field _applied_mode string|nil
---@field _wander_timer TimerHandle|nil
---@field _speed_timer TimerHandle|nil
local MovementSystem = Class("BabyMovementSystem")

---@param agent BabyAgent
function MovementSystem:Ctor(agent)
    self._agent = agent
    self._applied_mode = nil
    self._wander_timer = nil
    self._speed_timer = nil
end

-- 立即按当前意图/锁状态对齐（意图变更后的正路入口）。
function MovementSystem:invalidate()
    self._applied_mode = nil
    self:_align()
end

-- 空转兜底：意图与已应用模式漂移时补一次对齐（不再做 dt 累计；Phase 6 摘除本调用）。
---@param dt Fixed
function MovementSystem:reconcile(dt)
    self:_align()
end

---@private
function MovementSystem:_align()
    local agent = self._agent
    local unit = agent.unit
    if not unit then
        return
    end

    -- 锁定优先：强制 Stop；解锁后由 invalidate/兜底重新进入意图模式。
    local mode = agent.move_mode or Intent.MoveMode.Stop
    if agent.action_lock:is_locked() then
        mode = Intent.MoveMode.Stop
    end
    if mode == self._applied_mode then
        return
    end

    -- 模式切换：先取消上一模式的周期动作，再进入新模式。
    self:_cancel_mode_timers()
    self._applied_mode = mode
    self:_enter_mode(unit, mode)
end

---@private
---@param unit Unit|LifeEntity
---@param mode string
function MovementSystem:_enter_mode(unit, mode)
    if mode == Intent.MoveMode.Stop or mode == Intent.MoveMode.Carried then
        self:_stop(unit)
    elseif mode == Intent.MoveMode.Wander then
        self:_begin_wander(unit)
    elseif mode == Intent.MoveMode.PickupTarget then
        self:_begin_pickup(unit)
    elseif mode == Intent.MoveMode.MoveToTarget then
        self:_set_speed(unit, 1.0)
        self:_command_move_to(unit, self._agent.move_target)
    elseif mode == Intent.MoveMode.Scripted then
        -- 位移由 Driver 接管：什么都不发，只记录模式（本阶段无人使用）。
    end
end

-- ============================================================
-- Wander：进入时立刻发第一个巡逻点，之后 Timer 周期换点。
-- ============================================================

---@private
---@param unit Unit|LifeEntity
function MovementSystem:_begin_wander(unit)
    local params = self._agent.wander_params or {}
    local interval = params.interval or self._agent.config.baby.patrol_interval
    self:_command_wander_point(unit)
    self._wander_timer = Timer.every(self, interval, function()
        local cur = self._agent.unit
        if cur then
            self:_command_wander_point(cur)
        end
    end)
end

---@private
---@param unit Unit|LifeEntity
function MovementSystem:_command_wander_point(unit)
    local agent = self._agent
    local params = agent.wander_params or {}
    -- 缺省巡逻速度压成 0：宝宝原地驻留，仅保留朝向/巡逻指令语义（既有设计）。
    self:_set_speed(unit, params.speed_ratio or 0.0)
    local target = self:_make_wander_target(unit, params)
    if target then
        local threshold = params.threshold or agent.config.baby.patrol_threshold
        unit.start_move_to_pos_with_threshold(target, threshold, 0.5)
    end
end

-- 巡逻点选取：anchor+radius 同时给出时，在锚点小半径内挪动（x/z 各偏 ±radius，y 用锚点高度，
-- 对应猜拳配对 fidget 语义：半径很小，保证不走出配对范围）；否则用场地随机点（y 用当前高度）。
---@private
---@param unit Unit|LifeEntity
---@param params BabyWanderParams
---@return Vector3|nil
function MovementSystem:_make_wander_target(unit, params)
    if params.anchor and params.radius then
        return math.Vector3(
            params.anchor.x + Rand.signed() * params.radius,
            params.anchor.y,
            params.anchor.z + Rand.signed() * params.radius
        )
    end
    local random = self._agent.services.arena:random_point()
    if not random then
        return nil
    end
    local current = unit.get_position() or random
    return math.Vector3(random.x, current.y, random.z)
end

-- ============================================================
-- PickupTarget：寻路拾取 + 周期性重申速度比率。
-- ============================================================

---@private
---@param unit Unit|LifeEntity
function MovementSystem:_begin_pickup(unit)
    local agent = self._agent
    local item = agent.pickup_target
    if not (item and item.equipment) then
        return
    end
    unit.start_ai()
    self:_set_speed(unit, agent.config.baby.pickup_move_speed_ratio)
    -- 装备单位可能已被拾取/回收销毁，仅此调用保留 pcall。
    pcall(function()
        unit.ai_command_pick_up_equipment(item.equipment, Enums.MoveMode.DIRECT, 0.2)
    end)
    -- 速度比率周期性重申，避免锁解除后被 ActionLock 恢复成 1.0。
    self._speed_timer = Timer.every(self, PICKUP_SPEED_REASSERT_INTERVAL, function()
        local cur = self._agent.unit
        if cur then
            self:_set_speed(cur, self._agent.config.baby.pickup_move_speed_ratio)
        end
    end)
end

---@private
---@param unit Unit|LifeEntity
---@param target Vector3|nil
function MovementSystem:_command_move_to(unit, target)
    if target then
        unit.start_move_to_pos_with_threshold(target, self._agent.config.baby.patrol_threshold, 0.5)
    end
end

---@private
---@param unit Unit|LifeEntity
function MovementSystem:_stop(unit)
    unit.stop_ai()
    unit.ai_command_stop_move(0.1)
end

---@private
---@param unit Unit|LifeEntity
---@param ratio Fixed
function MovementSystem:_set_speed(unit, ratio)
    unit.set_attr_ratio_fixed("move_speed", ratio)
end

---@private
function MovementSystem:_cancel_mode_timers()
    Timer.cancel(self._wander_timer)
    self._wander_timer = nil
    Timer.cancel(self._speed_timer)
    self._speed_timer = nil
end

-- ============================================================
-- 语义动作接口：供状态层/过渡期服务调用。
-- 引擎坑位：部分 ai_command_* 在 AI 被 stop_ai() 关闭后不会生效（ActionLock/本系统的
-- Stop 模式都会 stop_ai，且解锁并不会自动 start_ai），指令会静默失效——所以除
-- stop_move 外，perform 内部一律先 start_ai 再发指令，调用方不必自己开 AI。
-- ============================================================

---@param action "release_lift"|"jump"|"directional_move"|"stop_move"
---@param args { dir: Vector3, duration: Fixed }|nil directional_move 必填
function MovementSystem:perform(action, args)
    local unit = self._agent.unit
    if not unit then
        return
    end
    if action == "stop_move" then
        -- 停步不开 AI（开 AI 反而可能让引擎接管走位）。
        unit.ai_command_stop_move(0.1)
        return
    end
    unit.start_ai()
    if action == "release_lift" then
        unit.ai_command_lift() -- 松手放下举着的东西
    elseif action == "jump" then
        unit.ai_command_jump()
    elseif action == "directional_move" and args then
        unit.ai_command_start_move(args.dir, args.duration)
    end
end

-- 外部（被抱起 / ActionLock 停步回调等）需要立刻停步时的快捷入口；
-- 同时取消周期动作并清空已应用模式，下一次 invalidate/兜底会重新对齐。
function MovementSystem:force_stop()
    local unit = self._agent.unit
    if unit then
        self:_stop(unit)
    end
    self:_cancel_mode_timers()
    self._applied_mode = nil
end

-- agent destroy 时清场：取消本系统名下全部定时器。
function MovementSystem:cleanup()
    Timer.cancel_all(self)
    self._wander_timer = nil
    self._speed_timer = nil
    self._applied_mode = nil
end

return MovementSystem
