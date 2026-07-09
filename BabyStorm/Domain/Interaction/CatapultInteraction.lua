local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")
local InteractionBase = require("BabyStorm.Domain.Interaction.InteractionBase")
local FollowDriver = require("BabyStorm.Core.Drivers.FollowDriver")
local Log = require("Util.Log")

-- 投石车：宝宝“骑”在投臂上等待发射。与秋千同一套“硬粘 + 强制坐姿”骨架，但：
--   1) 不给臂施力——投臂摆动由编辑器运动器负责（表现）；
--   2) 不按时长自动结束——等玩家点发射按钮：CatapultLaunchService 发 catapult_launch
--      事件（经 agent:handle_event 转发到这里）→ 停跟随，位移交给 FlightDriver 独占；
--      锁与坐姿动画保留到落地（complete_facility_interaction → 宿主 exit）才释放，
--      避免飞行中 AI 抢回控制。
-- 宝宝是脚本按帧定位的运动学单位、且与臂关闭了碰撞，运动器的物理发射碰不到它。
-- 朝向源：seat_orient_unit_name（如“投石车投臂0”）——位置仍粘 facility.unit。
---@class CatapultInteraction: InteractionBase
---@field _follow FollowDriver
local CatapultInteraction = Class("BabyCatapultInteraction", InteractionBase)

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function CatapultInteraction:Ctor(agent, facility)
    CatapultInteraction.super.Ctor(self, agent, facility)
    self._follow = FollowDriver.New()
end

function CatapultInteraction:get_intent()
    return {
        move_mode = Intent.MoveMode.Scripted, -- 位移由 FollowDriver / FlightDriver 接管
        anim_base = Intent.AnimBase.Idle,
        action_lock = true,
    }
end

---@param _duration Fixed
function CatapultInteraction:enter(_duration)
    local def = self.def
    -- 朝向来源解析一次并缓存在设施记录上（跨交互复用）。
    if def.seat_orient_unit_name and not self.facility.orient_unit then
        self.facility.orient_unit = LuaAPI.query_unit(def.seat_orient_unit_name)
        if not self.facility.orient_unit then
            Log.warn("catapult orient unit not found", def.seat_orient_unit_name)
        end
    end
    self:_set_collision_with(self.facility.unit, false)
    self:_play_seat_anim(nil)
    self._follow:start(self:_seat_follow_spec())
    self.agent:set_status("等待发射")
    Log.info("catapult seat begin", def.id, "baby", self.agent.index)
end

---@param event table
function CatapultInteraction:handle_event(event)
    if event.type == "catapult_launch" then
        -- 发射：只停跟随，位移交给 FlightDriver；落地结算时宿主 exit 统一收尾。
        self._follow:stop()
    end
end

function CatapultInteraction:exit()
    self._follow:stop()
    self:_release_anim()
    self:_set_collision_with(self.facility.unit, true)
    Log.info("catapult seat end", self.def.id, "baby", self.agent.index)
    CatapultInteraction.super.exit(self)
end

---@return boolean
function CatapultInteraction:is_timed()
    return false
end

return CatapultInteraction
