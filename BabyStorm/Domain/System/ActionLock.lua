local Class = require("BaseClass")

-- 统一的动作锁。合并历史上三套各自为政的移动锁：
--   timeout_move_locked / ride_move_locked / movement_hold_locked。
--
-- 语义：按「原因(reason)」引用计数。任意原因存在时即锁定（engaged）。
--   - 空集 -> 非空：加 BUFF_FORBID_MOVE、停 AI、速度归零（仅在边沿执行一次）。
--   - 非空 -> 空：移除 BUFF、恢复速度。
-- BUFF_FORBID_MOVE 是计数型 buff，必须幂等加减；用 reason 集合保证只在边沿
-- 加/减一次，避免「只移除一次后永久禁动」的历史 bug。
-- 同一 reason 重复 acquire 视为一次；release 不存在的 reason 是 no-op。
--
-- 锁定期间 MovementSystem 必须强制 Stop（见 MovementSystem:_align）。
---@class ActionLock
---@field _unit Unit|LifeEntity|nil
---@field _reasons table<string, boolean>
---@field _engaged boolean
---@field _stop_handler fun()|nil
local ActionLock = Class("BabyActionLock")

---@param unit Unit|LifeEntity|nil
function ActionLock:Ctor(unit)
    self._unit = unit
    self._reasons = {}
    self._engaged = false
    self._stop_handler = nil
end

---注入停步回调（由 BabyAgent 注入 movement:force_stop）：
---停步/停 AI 的引擎调用统一收敛到 MovementSystem，本锁只负责 BUFF 与速度的边沿控制。
---@param fn fun()
function ActionLock:set_stop_handler(fn)
    self._stop_handler = fn
end

---@param unit Unit|LifeEntity|nil
function ActionLock:bind_unit(unit)
    self._unit = unit
end

---@return boolean
function ActionLock:is_locked()
    return self._engaged
end

---@param reason string
---@return boolean
function ActionLock:has(reason)
    return self._reasons[reason] == true
end

-- 锁住一个原因。首个原因触发引擎层禁动。
---@param reason string
function ActionLock:acquire(reason)
    if not reason or self._reasons[reason] then
        return
    end
    self._reasons[reason] = true
    if not self._engaged then
        self._engaged = true
        self:_engage_engine()
    else
        -- 已锁定，补一次停步即可，BUFF 不重复添加。
        self:_stop_move()
    end
end

-- 释放一个原因。最后一个原因移除时解除引擎禁动。
---@param reason string
function ActionLock:release(reason)
    if not reason or not self._reasons[reason] then
        return
    end
    self._reasons[reason] = nil
    if next(self._reasons) == nil and self._engaged then
        self._engaged = false
        self:_disengage_engine()
    end
end

-- 全部释放（状态 exit / agent destroy 时调用，杜绝跨状态泄漏）。
function ActionLock:release_all()
    if not self._engaged then
        self._reasons = {}
        return
    end
    self._reasons = {}
    self._engaged = false
    self:_disengage_engine()
end

-- pcall 豁免：本锁持有的 unit 是宝宝自己的单位，agent destroy 时会与本系统一起清场，
-- 但 add_state/remove_state 边沿调用发生在 destroy 竞态附近，保留 pcall 兜底。
---@private
function ActionLock:_engage_engine()
    local unit = self._unit
    if not unit then
        return
    end
    if unit.add_state then
        pcall(function() unit.add_state(Enums.BuffState.BUFF_FORBID_MOVE) end)
    end
    self:_stop_move()
    if unit.set_attr_ratio_fixed then
        pcall(function() unit.set_attr_ratio_fixed("move_speed", 0.0) end)
    end
end

---@private
function ActionLock:_disengage_engine()
    local unit = self._unit
    if not unit then
        return
    end
    if unit.remove_state then
        pcall(function() unit.remove_state(Enums.BuffState.BUFF_FORBID_MOVE) end)
    end
    if unit.set_attr_ratio_fixed then
        pcall(function() unit.set_attr_ratio_fixed("move_speed", 1.0) end)
    end
end

---@private
function ActionLock:_stop_move()
    -- 不再自己调 stop_ai/ai_command_stop_move：全工程只允许 MovementSystem 碰 AI 开关。
    if self._stop_handler then
        self._stop_handler()
    end
end

return ActionLock
