local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")
local InteractionBase = require("BabyStorm.Domain.Interaction.InteractionBase")
local FollowDriver = require("BabyStorm.Core.Drivers.FollowDriver")
local Log = require("Util.Log")

-- 婴儿床（壳）：宝宝躺床——躺姿动作（seat_anim_id=49）+ 每帧硬粘到床躺位 + 锁移动 + 关碰撞。
-- 换尿布/擦屁股玩法（子需求随机、取物持有、长按进度、歪床/扶正）仍由 CribService 驱动
-- （Phase 5 迁入本子状态）：enter 时把会话交给它，结算由它回调
-- agent:complete_facility_interaction（完成）/ fail_facility_interaction（歪床），
-- 宿主状态 exit 时经这里 end_session 收尾。
---@class CribInteraction: InteractionBase
---@field _follow FollowDriver
local CribInteraction = Class("BabyCribInteraction", InteractionBase)

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function CribInteraction:Ctor(agent, facility)
    CribInteraction.super.Ctor(self, agent, facility)
    self._follow = FollowDriver.New()
end

function CribInteraction:get_intent()
    return {
        move_mode = Intent.MoveMode.Scripted, -- 位移由 FollowDriver 接管
        anim_base = Intent.AnimBase.Idle,     -- 躺姿走 force_play 外部层
        action_lock = true,
    }
end

---@param _duration Fixed
function CribInteraction:enter(_duration)
    self:_set_collision_with(self.facility.unit, false)
    self:_play_seat_anim(nil)
    self._follow:start(self:_seat_follow_spec())
    -- 把换尿布/擦屁股玩法交给 CribService 驱动（状态文案由它设成对应子需求）。
    self.agent.services.crib:begin_session(self.agent, self.facility)
    Log.info("crib begin", self.def.id, "baby", self.agent.index)
end

function CribInteraction:exit()
    self.agent.services.crib:end_session(self.agent, self.facility)
    self._follow:stop()
    self:_release_anim()
    self:_set_collision_with(self.facility.unit, true)
    Log.info("crib end", self.def.id, "baby", self.agent.index)
    CribInteraction.super.exit(self)
end

---@return boolean
function CribInteraction:is_timed()
    return false
end

return CribInteraction
