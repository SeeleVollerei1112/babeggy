local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")

-- 空闲：巡逻（实际原地驻留）+ 就近扫描当前需求物品 + 展示需求倒计时。
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
    -- 巡逻 + 待机移动表现。Wander 实际几乎不位移（move_speed 比率为 0，既有设计）。
    self:set_intent({
        move_mode = Intent.MoveMode.Wander,
        anim_base = Intent.AnimBase.Locomotion,
        action_lock = false,
    })
end

---@param dt Fixed
function IdleState:update(dt)
    local agent = self.agent
    -- 就近扫描：玩家把可拾取物件放到宝宝身边时，宝宝据此自己去捡。
    -- 只认地面物品（设施需玩家抱送）。
    self._scan_elapsed = self._scan_elapsed + dt
    if self._scan_elapsed < agent.config.baby.item_scan_interval then
        return
    end
    self._scan_elapsed = 0.0

    if not agent.unit then
        return
    end
    local pos = agent.unit.get_position and agent.unit.get_position()
    if pos then
        agent:try_match_current_need_at(pos, "item_to_baby")
    end
end

return IdleState
