local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")
local Rand = require("Util.Rand")

-- 平常态：持续使用漫游功能引入前的场地随机点巡逻，同时扫描当前需求物品并展示倒计时。
-- 这是宝宝没有被特殊行为接管时的默认状态；需要停步的行为通过自己的 Stop / Carried /
-- Scripted 意图临时覆盖，结束回到 Idle 后自动恢复旧版随机点巡逻。
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
    self:_schedule_toy_interest()
end

-- 不传 wander 参数，明确走 MovementSystem 的旧版普通巡逻分支：
-- move_speed=0.0，并调用 start_move_to_pos_with_threshold(random, 4.0, 0.5)。
function IdleState:apply_move_intent()
    self:set_intent({
        move_mode = Intent.MoveMode.Wander,
        anim_base = Intent.AnimBase.Locomotion,
        action_lock = false,
    })
end

-- 漫游不再是单独状态。随手捡玩具的概率检查挂在平常态名下，失败后按较长随机间隔
-- 再检查一次；命中并切到 SeekingItem 时，StateBase:exit 会自动取消本状态的定时器。
function IdleState:_schedule_toy_interest()
    local baby = self.agent.config.baby
    Timer.once(self, Rand.fixed(baby.toy_pick_check_min_seconds, baby.toy_pick_check_max_seconds), function()
        local agent = self.agent
        local unit = agent.unit
        local pos = unit and unit.get_position and unit.get_position()
        if pos and agent:try_pick_toy_for_fun(pos) then
            return
        end
        self:_schedule_toy_interest()
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

    -- 需求扫描（纯距离检测）：每 item_scan_interval 秒，在 item_pickup_radius 内找一件
    -- 匹配当前需求的物品；找到即转 SeekingItem 走过去捡，
    -- 最后 contact_radius 内兜底强制拾取。
    -- 玩家因此有两种“投喂”方式，走的是同一条路径：把物品丢在宝宝身边，或者拿着走到宝宝身边
    -- （只要物品没进玩家自己的装备槽，宝宝就照捡不误，见 ItemService:_is_on_ground）。
    -- 副作用：拿着物品路过“正好想要它”的宝宝时也会被抢，绕不过去——距离检测的必然结果。
    -- 只认地面物品（设施需玩家抱送），也只认当前需求；随手捡玩具走上面的低频概率检查。
    self._scan_elapsed = self._scan_elapsed + dt
    if self._scan_elapsed >= agent.config.baby.item_scan_interval then
        self._scan_elapsed = 0.0
        agent:try_match_current_need_at(pos, "item_to_baby")
    end
end

return IdleState
