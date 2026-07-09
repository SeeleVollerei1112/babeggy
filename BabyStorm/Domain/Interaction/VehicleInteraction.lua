local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")
local InteractionBase = require("BabyStorm.Domain.Interaction.InteractionBase")
local FollowDriver = require("BabyStorm.Core.Drivers.FollowDriver")
local PatrolDriver = require("BabyStorm.Core.Drivers.PatrolDriver")
local Timer = require("BabyStorm.Core.Timer")
local MathX = require("Util.MathX")
local Log = require("Util.Log")

-- 载具型设施（自动驾驶）：宝宝上车，在触发区内巡游。按 vehicle_drive_mode 分两条路：
--
-- kinematic（默认）：PatrolDriver 用 set_position 挪载具（帧同步确定性巡游，不出触发区），
--   FollowDriver 把宝宝硬粘在座位点、朝向随载具。锁移动——否则每帧位移会让引擎插播
--   待机/移动动画，把骑行动作顶掉。骑行动作一次强制播放持续整段（force_play）。
--
-- physics（真·载具）：try_enter_vehicle + VehicleComp.start_move_by_direction，
--   引擎驱动宝宝，逻辑层只按节拍重新对准方向（原 _drive_vehicle_physics 平移，Timer 化）。
---@class VehicleInteraction: InteractionBase
---@field _mode "kinematic"|"physics"
---@field _patrol PatrolDriver
---@field _follow FollowDriver
---@field _target Vector3|nil  -- physics 模式的当前巡游目标
local VehicleInteraction = Class("BabyVehicleInteraction", InteractionBase)

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function VehicleInteraction:Ctor(agent, facility)
    VehicleInteraction.super.Ctor(self, agent, facility)
    self._mode = facility.def.vehicle_drive_mode or "kinematic"
    self._patrol = PatrolDriver.New()
    self._follow = FollowDriver.New()
    self._target = nil
end

function VehicleInteraction:get_intent()
    if self._mode == "physics" then
        -- 引擎载具驱动宝宝：停 AI 即可，不加锁（历史行为）。
        return {
            move_mode = Intent.MoveMode.Stop,
            anim_base = Intent.AnimBase.Idle,
            action_lock = false,
        }
    end
    return {
        move_mode = Intent.MoveMode.Scripted, -- 位移由 PatrolDriver+FollowDriver 接管
        anim_base = Intent.AnimBase.Idle,     -- 骑行动作走 force_play 外部层
        action_lock = true,
    }
end

---@param duration Fixed
function VehicleInteraction:enter(duration)
    if self._mode == "physics" then
        self:_enter_physics()
    else
        self:_enter_kinematic(duration)
    end
    Log.info("vehicle ride begin", self.def.id, "baby", self.agent.index,
        "mode", self._mode, "duration", duration)
end

-- ---------- 运动学驱动（默认）----------

---@private
---@param duration Fixed
function VehicleInteraction:_enter_kinematic(duration)
    local def = self.def
    self:_play_ride_anim(duration)
    self._patrol:start({
        vehicle = self.facility.unit,
        area = self.facility.area,
        max_speed = def.vehicle_speed or 3.0,
        turn_speed = def.vehicle_turn_speed or 3.0,
        accel = def.vehicle_accel or 6.0,
        reach = def.vehicle_reach_radius or 2.0,
        arrive_radius = def.vehicle_arrive_radius,
    })
    -- 宝宝硬粘在载具座位上（平顺度来自载具自身的缓动运动），朝向随载具。
    self._follow:start({
        unit = self.agent.unit,
        target = self.facility.unit,
        offset = MathX.to_vector3(def.vehicle_seat_offset) or math.Vector3(0.0, 0.5, 0.0),
        orient = "target",
        smooth = false,
    })
end

-- 骑行动作：一次强制播放持续整段骑行，下板时 release 停掉。
-- 用 force_play_animation_by_anim_key（anim_key）而非 play_body_anim_by_id：后者（全身动作）
-- 约 1 秒后必被 AI 待机动画顶掉，只能每秒重发，而重发会从头混入 → “起身再执行”。
---@private
---@param duration Fixed|nil
function VehicleInteraction:_play_ride_anim(duration)
    local def = self.def
    local play_time = (duration or 0) + 0.0
    if def.vehicle_ride_anim_key then
        -- 首选：AnimKey + 强制播放，长期保持动态骑行姿势，不被待机顶掉
        self.agent.animation:force_play(
            { mode = "anim_key", id = def.vehicle_ride_anim_key, duration = play_time }, "facility")
    elseif def.vehicle_ride_anim_id then
        -- 退路：全身动作预设，约 1 秒后会被引擎切回待机，仅占位（需要 AnimKey 才能持久）
        self.agent.animation:force_play(
            { mode = "body_id", id = def.vehicle_ride_anim_id, duration = play_time }, "facility")
    end
end

-- ---------- 物理驱动（真·载具）----------
-- SDK 不提供 AI 自动驾驶，只有 start_move_by_direction(方向, 时长)。
-- “转向循环”：维持一个区内目标点，每隔 segment 秒重新对准方向并续发移动；
-- 到达目标或开出触发区就重新选点，从而把活动范围约束在触发区内。

---@private
function VehicleInteraction:_enter_physics()
    self.agent.unit.try_enter_vehicle(self.facility.unit)
    local segment = self.def.vehicle_move_segment or 0.3
    Timer.once(self, self.def.vehicle_enter_delay or 0.4, function()
        self:_physics_step(segment)
        Timer.every(self, segment, function()
            self:_physics_step(segment)
        end)
    end)
end

---@private
---@param segment Fixed
function VehicleInteraction:_physics_step(segment)
    local vehicle = self.facility.unit
    local pos = vehicle.get_position()
    if not pos then
        return
    end

    local reach = self.def.vehicle_reach_radius or 2.0
    local area = self.facility.area
    local target = self._target

    local need_new = target == nil
    if target then
        local dx = target.x - pos.x
        local dz = target.z - pos.z
        if dx * dx + dz * dz <= reach * reach then
            need_new = true
        end
    end
    if area and not GameAPI.is_point_in_customtriggerspace(pos, area) then
        need_new = true
    end
    if need_new and area then
        self._target = area.random_point() or target
    end

    target = self._target
    if target then
        local dir = math.Vector3(target.x - pos.x, 0.0, target.z - pos.z)
        local length = dir:length()
        if length and length > 0.05 then
            local inv = 1.0 / length
            vehicle.start_move_by_direction(math.Vector3(dir.x * inv, 0.0, dir.z * inv), segment * 2.0)
        end
    end
end

-- ---------- 收尾 ----------

function VehicleInteraction:exit()
    if self._mode == "physics" then
        local vehicle = self.facility.unit
        vehicle.stop_move()
        self.agent.unit.try_exit_vehicle()
        vehicle.reset() -- 载具复位
    else
        self._patrol:stop()
        self._follow:stop()
        self:_release_anim()
    end
    self._target = nil
    Log.info("vehicle ride end", self.def.id, "baby", self.agent.index)
    VehicleInteraction.super.exit(self)
end

return VehicleInteraction
