local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")
local UnitUtil = require("Util.UnitUtil")

-- 走向并捡起目标物品。含 reject 分支（捡起错误物品看一会儿再丢）。
-- 移动/拾取指令由 MovementSystem（PickupTarget 模式）下发；本状态用 phase 轮询拾取结果。
---@class SeekingItemState: StateBase
---@field _check_elapsed Fixed
---@field _total_elapsed Fixed
local SeekingItemState = Class("BabySeekingItemState", StateBase)

---@param agent BabyAgent
function SeekingItemState:Ctor(agent)
    SeekingItemState.super.Ctor(self, agent)
    self._check_elapsed = 0.0
    self._total_elapsed = 0.0
end

---@param context BabyStateContext|nil
function SeekingItemState:enter(context)
    SeekingItemState.super.enter(self, context)
    local agent = self.agent
    local item = context and context.item or nil
    if not (item and item.equipment) then
        agent:enter_upset({ reason = item and "pickup_failed" or "missing_item" })
        return
    end

    agent:set_lift_enabled(false)
    agent.pending_item = item
    agent.pickup_target = item
    agent.pending_purpose = (context and context.reason == "wrong_item") and "reject" or "satisfy"

    if agent.pending_purpose == "reject" then
        agent:set_status("捡起来看看")
    else
        agent:set_status(agent.services.resolver:get_match_text(agent.current_need, item))
    end
    agent.services.task:emit_delivery(agent, item, context and context.delivery_method or nil)

    self._check_elapsed = 0.0
    self._total_elapsed = 0.0
    self.phase = "seeking"
    -- 寻路 + 拾取：MovementSystem 在进入 PickupTarget 模式时下发 ai_command_pick_up_equipment。
    self:set_intent({
        move_mode = Intent.MoveMode.PickupTarget,
        anim_base = Intent.AnimBase.Pickup,
        action_lock = false,
    })
end

---@param dt Fixed
function SeekingItemState:update(dt)
    if self.phase ~= "seeking" then
        return
    end
    local agent = self.agent
    local item = agent.pending_item
    if not item or item.done then
        return
    end

    self._total_elapsed = self._total_elapsed + dt
    self._check_elapsed = self._check_elapsed + dt
    if self._check_elapsed < agent.config.baby.pickup_check_interval then
        return
    end
    self._check_elapsed = 0.0

    -- 命中：已拿到手
    if agent.services.item:item_owned_by_baby(item, agent) then
        self.phase = "done"
        agent:_resolve_pickup(item)
        return
    end

    -- 兜底：走到接触距离内强制拾取
    local baby_pos = agent.unit and agent.unit.get_position and agent.unit.get_position()
    local item_pos = item.equipment and item.equipment.get_position and item.equipment.get_position()
    local radius = agent.config.baby.contact_radius
    if baby_pos and item_pos and UnitUtil.distance_xz_sq(baby_pos, item_pos) <= radius * radius then
        if agent.services.item:force_pickup(agent, item) then
            self.phase = "done"
            agent:_resolve_pickup(item)
            return
        end
    end

    -- 超时
    if self._total_elapsed >= agent.config.baby.pickup_timeout then
        self.phase = "done"
        agent.pending_item = nil
        if agent.pending_purpose == "reject" then
            agent.pending_purpose = nil
            agent:enter_upset({ item = item, reason = "wrong_item" })
        else
            agent:enter_upset({ reason = "pickup_timeout" })
        end
    end
end

return SeekingItemState
