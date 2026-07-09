local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")
local InteractionBase = require("BabyStorm.Domain.Interaction.InteractionBase")
local FollowDriver = require("BabyStorm.Core.Drivers.FollowDriver")
local SwingPumpDriver = require("BabyStorm.Core.Drivers.SwingPumpDriver")
local MathX = require("Util.MathX")
local Log = require("Util.Log")

local ZERO = math.Vector3(0.0, 0.0, 0.0)

-- 秋千座椅：把宝宝绑到会摆动的物理座椅上，并周期性给座椅施力让它越摆越高。
-- 座椅是物理刚体，由 SwingPumpDriver 施力驱动摆动；宝宝像绑滑板那样每帧硬粘到
-- 座位点、跟随座椅朝向一起摆（FollowDriver）。锁移动 + 关碰撞，避免宝宝被待机/
-- 移动动画顶掉、或与座椅互相顶把它推歪。
---@class SwingInteraction: InteractionBase
---@field _follow FollowDriver
---@field _pump SwingPumpDriver
local SwingInteraction = Class("BabySwingInteraction", InteractionBase)

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function SwingInteraction:Ctor(agent, facility)
    SwingInteraction.super.Ctor(self, agent, facility)
    self._follow = FollowDriver.New()
    self._pump = SwingPumpDriver.New()
end

function SwingInteraction:get_intent()
    return {
        move_mode = Intent.MoveMode.Scripted, -- 位移由 FollowDriver 接管
        anim_base = Intent.AnimBase.Idle,     -- 坐姿走 force_play 外部层
        action_lock = true,                   -- 原 ride 锁：禁动 + 停 AI
    }
end

---@param duration Fixed
function SwingInteraction:enter(duration)
    local def = self.def
    self:_set_collision_with(self.facility.unit, false)
    self:_play_seat_anim(duration)
    self._follow:start(self:_seat_follow_spec())
    self._pump:start({
        seat = self.facility.unit,
        magnitude = def.swing_force_magnitude or 12.0,
        max_speed = def.swing_max_speed or 4.0,
        push_dir = MathX.to_vector3(def.swing_push_dir),
        interval = def.swing_force_interval or 0.2,
    })
    Log.info("swing seat begin", def.id, "baby", self.agent.index, "duration", duration)
end

function SwingInteraction:exit()
    self._pump:stop()
    self._follow:stop()
    self:_release_anim()
    self:_set_collision_with(self.facility.unit, true)
    -- 让座椅停摆：清掉速度，避免下一个宝宝来坐时它还在乱晃。
    local seat = self.facility.unit
    if seat then
        seat.set_linear_velocity(ZERO)
        seat.set_angular_velocity(ZERO)
    end
    Log.info("swing seat end", self.def.id, "baby", self.agent.index)
    SwingInteraction.super.exit(self)
end

return SwingInteraction
