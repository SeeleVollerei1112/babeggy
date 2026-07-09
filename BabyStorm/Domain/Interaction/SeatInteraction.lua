local Class = require("BaseClass")
local InteractionBase = require("BabyStorm.Domain.Interaction.InteractionBase")
local FollowDriver = require("BabyStorm.Core.Drivers.FollowDriver")

-- 普通座位交互（facility_kind 未特化时的兜底）：
-- 坐姿动画（force_play 压住待机）+ 每帧硬粘到座位点（绑定 API 在本环境挪不动活体单位）。
-- 历史行为：普通座位不加动作锁、不关碰撞（宿主意图 Stop 已停 AI）。
---@class SeatInteraction: InteractionBase
---@field _follow FollowDriver
local SeatInteraction = Class("BabySeatInteraction", InteractionBase)

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function SeatInteraction:Ctor(agent, facility)
    SeatInteraction.super.Ctor(self, agent, facility)
    self._follow = FollowDriver.New()
end

---@param duration Fixed
function SeatInteraction:enter(duration)
    self:_play_seat_anim(duration)
    self._follow:start(self:_seat_follow_spec())
end

function SeatInteraction:exit()
    self._follow:stop()
    self:_release_anim()
    SeatInteraction.super.exit(self)
end

return SeatInteraction
