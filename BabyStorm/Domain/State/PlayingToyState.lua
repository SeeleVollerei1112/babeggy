local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")
local Rand = require("Util.Rand")

-- 把玩玩具：捡到玩具后玩一会儿（原地或拿着到处走）再放下。
--
-- 捡到玩具的所有路径都汇到这里（见 BabyAgent:begin_toy_play）——玩具豁免 reject，
-- 「是不是当前需求」只决定玩完怎么收尾：
--   * satisfies = true  -> 玩完结算满足（Satisfied，计分）。
--   * satisfies = false -> 玩完直接回 Idle，不计分、不 Upset（随手捡的就是纯玩）。
--
-- 玩具全程留在场上：放下动作放在 exit 里做，所以被抱起等中途打断
-- 也不会把玩具永远攥在宝宝手里。
---@class PlayingToyState: StateBase
---@field _item BabyItemRecord|nil
---@field _satisfies boolean
---@field _paused_need_seconds integer|nil
local PlayingToyState = Class("BabyPlayingToyState", StateBase)

---@param agent BabyAgent
function PlayingToyState:Ctor(agent)
    PlayingToyState.super.Ctor(self, agent)
    self._item = nil
    self._satisfies = false
    self._paused_need_seconds = nil
end

---@param context BabyStateContext|nil
function PlayingToyState:enter(context)
    PlayingToyState.super.enter(self, context)
    local agent = self.agent
    local baby = agent.config.baby
    local item = context and context.item or nil
    self._item = item
    self._satisfies = (context and context.satisfies) and true or false
    self._paused_need_seconds = nil

    if not item then
        agent:enter_idle()
        return
    end

    agent:select_equipped_slot()
    agent:set_lift_enabled(true)

    -- 满足型：需求已经拿到手，倒计时不再需要。
    -- 随手玩型：保存当前剩余时间并暂停，放下玩具时从原秒数继续。
    if self._satisfies then
        agent:cancel_need_countdown()
    else
        self._paused_need_seconds = agent.need_runtime:get_remaining()
        if self._paused_need_seconds then
            agent:cancel_need_countdown()
        end
    end

    -- 一半概率拿着玩具到处跑，一半原地玩。
    -- 把玩时使用局部随机点，因此显式给速度、换点间隔和活动半径。
    local roam = Rand.int(1, 100) <= baby.toy_play_move_chance_percent
    if roam then
        self:set_intent({
            move_mode = Intent.MoveMode.Wander,
            anim_base = Intent.AnimBase.Locomotion,
            anim_overlay = Intent.AnimOverlay.Happy,
            action_lock = false,
            wander = {
                speed_ratio = baby.toy_play_move_speed_ratio,
                interval = baby.toy_play_move_interval,
                -- 锚点用当前位置就近逛。
                radius = baby.toy_play_stroll_radius,
                threshold = baby.local_wander_arrive_threshold,
            },
        })
    else
        self:set_intent({
            move_mode = Intent.MoveMode.Stop,
            anim_base = Intent.AnimBase.Idle,
            anim_overlay = Intent.AnimOverlay.Happy,
            action_lock = false,
        })
    end

    if self._satisfies then
        agent:set_status(agent.services.resolver:get_match_text(agent.current_need, item))
    else
        agent:set_status("玩一会儿~")
    end

    local play_seconds = self._satisfies and baby.toy_play_seconds or baby.toy_random_play_seconds
    Timer.once(self, play_seconds, function()
        agent:finish_toy_play(item, self._satisfies)
    end)
end

-- 离开本状态就一定把玩具还回地上：玩够了、被抱起等中断都走这里。
---@param context BabyStateContext|nil
function PlayingToyState:exit(context)
    local agent = self.agent
    agent.services.item:drop_to_ground(self._item)
    if self._paused_need_seconds and not agent.destroyed and agent.current_need then
        agent:_start_need_countdown(self._paused_need_seconds)
    end
    self._paused_need_seconds = nil
    self._item = nil
    PlayingToyState.super.exit(self, context)
end

return PlayingToyState
