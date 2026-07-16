local Class = require("BaseClass")
local IdleState = require("BabyStorm.Domain.State.IdleState")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")
local Rand = require("Util.Rand")

-- 漫游：Idle 站够了起身逛一段，逛够了回 Idle（走走停停的另一半）。
--
-- 继承 IdleState：需求扫描 / 需求倒计时 / 可举起全部一样，只覆写「真的会走」和「逛够了回 Idle」。
-- 起身那一刻掷一次骰，决定这趟要不要顺路捡个玩具去玩——**只掷这一次**：
-- 放进 update 轮询的话，概率会被反复掷放大成「迟早必捡」，宝宝就成了见玩具必捡。
---@class WanderingState: IdleState
local WanderingState = Class("BabyWanderingState", IdleState)

---@param context BabyStateContext|nil
function WanderingState:enter(context)
    -- 走 IdleState:enter，其中的 apply_move_intent / schedule_next 会派发到下面的覆写版本。
    WanderingState.super.enter(self, context)

    local agent = self.agent
    local pos = agent.unit and agent.unit.get_position and agent.unit.get_position()
    if pos then
        -- 中了就立刻转 SeekingItem（本状态随即 exit，上面排的回 Idle 定时器一并取消）。
        agent:try_pick_toy_for_fun(pos)
    end
end

-- 覆写：真的走起来。Wander 缺省会把移速比率压成 0，要真位移必须显式给 speed_ratio。
function WanderingState:apply_move_intent()
    local baby = self.agent.config.baby
    self:set_intent({
        move_mode = Intent.MoveMode.Wander,
        anim_base = Intent.AnimBase.Locomotion,
        action_lock = false,
        wander = {
            speed_ratio = baby.wander_move_speed_ratio,
            interval = baby.wander_point_interval,
            -- 不给 anchor：锚点用宝宝当前位置，走到哪从哪继续逛。
            radius = baby.wander_stroll_radius,
            threshold = baby.wander_arrive_threshold,
        },
    })
end

-- 覆写：逛够 wander_* 秒回 Idle 歇着。
function WanderingState:schedule_next()
    local baby = self.agent.config.baby
    Timer.once(self, Rand.fixed(baby.wander_min_seconds, baby.wander_max_seconds), function()
        self.agent:enter_idle()
    end)
end

return WanderingState
