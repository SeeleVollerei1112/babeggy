local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")

-- 移动系统：全工程**唯一**真正改变宝宝位置 / 下发移动指令的地方。
-- 行为层只写 agent.move_mode（+ move_target / pickup_target），由本系统每 tick reconcile。
--
-- 行为对照（保持历史行为）：
--   Stop         停在原地。
--   Wander       巡逻：每 patrol_interval 朝随机点发一次移动指令，但 move_speed 比率被压成 0，
--                因此宝宝实际几乎不位移——这是既有设计（宝宝平时驻留，只有取物/被抱时才动）。
--   PickupTarget 朝 agent.pickup_target（装备）寻路并拾取，速度比率提到 pickup_move_speed_ratio。
--   MoveToTarget 朝 agent.move_target（坐标）移动（预留）。
--   Carried      被举起：引擎驱动，逻辑层不发任何移动指令。
--
-- ActionLock 锁定时强制 Stop，不发任何移动指令。
---@class MovementSystem
---@field _agent BabyAgent
---@field _last_mode string|nil
---@field _wander_elapsed Fixed
local MovementSystem = Class("BabyMovementSystem")

---@param agent BabyAgent
function MovementSystem:Ctor(agent)
    self._agent = agent
    self._last_mode = nil
    self._wander_elapsed = 0.0
end

---@param dt Fixed
function MovementSystem:reconcile(dt)
    local agent = self._agent
    local unit = agent.unit
    if not unit then
        return
    end

    -- 锁定优先：强制停步，并把模式标记清空，解锁后会重新进入当前模式。
    if agent.action_lock:is_locked() then
        if self._last_mode ~= Intent.MoveMode.Stop then
            self:_stop(unit)
            self._last_mode = Intent.MoveMode.Stop
        end
        return
    end

    local mode = agent.move_mode or Intent.MoveMode.Stop
    if mode ~= self._last_mode then
        self:_enter_mode(unit, mode)
        self._last_mode = mode
    end

    if mode == Intent.MoveMode.Wander then
        self:_tick_wander(unit, dt)
    elseif mode == Intent.MoveMode.PickupTarget then
        -- 速度比率每帧重申，避免锁解除后被恢复成 1.0。
        if unit.set_attr_ratio_fixed then
            pcall(function()
                unit.set_attr_ratio_fixed("move_speed", agent.config.baby.pickup_move_speed_ratio)
            end)
        end
    end
end

---@private
---@param unit Unit|LifeEntity
---@param mode string
function MovementSystem:_enter_mode(unit, mode)
    if mode == Intent.MoveMode.Stop or mode == Intent.MoveMode.Carried then
        self:_stop(unit)
    elseif mode == Intent.MoveMode.Wander then
        self._wander_elapsed = 0.0
        self:_set_speed(unit, 0.0)
        self:_command_wander_point(unit)
    elseif mode == Intent.MoveMode.PickupTarget then
        self:_begin_pickup(unit)
    elseif mode == Intent.MoveMode.MoveToTarget then
        self:_set_speed(unit, 1.0)
        self:_command_move_to(unit, self._agent.move_target)
    end
end

---@private
---@param unit Unit|LifeEntity
---@param dt Fixed
function MovementSystem:_tick_wander(unit, dt)
    self._wander_elapsed = self._wander_elapsed + dt
    if self._wander_elapsed >= self._agent.config.baby.patrol_interval then
        self._wander_elapsed = 0.0
        self:_command_wander_point(unit)
    end
end

---@private
---@param unit Unit|LifeEntity
function MovementSystem:_command_wander_point(unit)
    local agent = self._agent
    -- 巡逻速度压成 0：宝宝原地驻留，仅保留朝向/巡逻指令语义（既有设计）。
    self:_set_speed(unit, 0.0)
    local target = self:_make_ground_target(unit)
    if target and unit.start_move_to_pos_with_threshold then
        pcall(function()
            unit.start_move_to_pos_with_threshold(target, agent.config.baby.patrol_threshold, 0.5)
        end)
    end
end

---@private
---@param unit Unit|LifeEntity
function MovementSystem:_begin_pickup(unit)
    local agent = self._agent
    local item = agent.pickup_target
    if not (item and item.equipment) then
        return
    end
    if unit.start_ai then
        pcall(function() unit.start_ai() end)
    end
    self:_set_speed(unit, agent.config.baby.pickup_move_speed_ratio)
    if unit.ai_command_pick_up_equipment then
        pcall(function()
            unit.ai_command_pick_up_equipment(item.equipment, Enums.MoveMode.DIRECT, 0.2)
        end)
    end
end

---@private
---@param unit Unit|LifeEntity
---@param target Vector3|nil
function MovementSystem:_command_move_to(unit, target)
    if target and unit.start_move_to_pos_with_threshold then
        pcall(function()
            unit.start_move_to_pos_with_threshold(target, self._agent.config.baby.patrol_threshold, 0.5)
        end)
    end
end

---@private
---@param unit Unit|LifeEntity
function MovementSystem:_stop(unit)
    if unit.stop_ai then
        pcall(function() unit.stop_ai() end)
    end
    if unit.ai_command_stop_move then
        pcall(function() unit.ai_command_stop_move(0.1) end)
    end
end

---@private
---@param unit Unit|LifeEntity
---@param ratio Fixed
function MovementSystem:_set_speed(unit, ratio)
    if unit.set_attr_ratio_fixed then
        pcall(function() unit.set_attr_ratio_fixed("move_speed", ratio) end)
    end
end

---@private
---@param unit Unit|LifeEntity
---@return Vector3|nil
function MovementSystem:_make_ground_target(unit)
    local random = self._agent.services.arena:random_point()
    if not random then
        return nil
    end
    local current = unit.get_position and unit.get_position() or random
    return math.Vector3(random.x, current.y, random.z)
end

-- 外部（被抱起等事件）需要立刻停步时的快捷入口；下一次 reconcile 会重新对齐模式。
function MovementSystem:force_stop()
    local unit = self._agent.unit
    if unit then
        self:_stop(unit)
    end
    self._last_mode = nil
end

-- 模式标记复位：lock 释放、状态切换后强制下一帧重新 _enter_mode。
function MovementSystem:invalidate()
    self._last_mode = nil
end

return MovementSystem
