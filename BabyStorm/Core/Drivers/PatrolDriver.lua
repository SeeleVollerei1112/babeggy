local Class = require("BaseClass")
local Timer = require("BabyStorm.Core.Timer")
local MathX = require("Util.MathX")

-- 载具运动学巡游驱动,自 FacilityService._drive_vehicle_kinematic 平移。
--
-- 为什么不用物理速度/力驱动:本环境是帧同步地图,set_position + 纯定点数学
-- 才能保证锁帧确定性、保证不冲出触发区;apply_force / set_linear_velocity 依赖
-- 物理 tick 积分,有不同步与被碰撞顶出区的风险。运动曲线三层平滑:
--   1) 朝向按 turn_speed 限速插值 → 平滑转弯而非瞬切;
--   2) 速度朝目标速度按 accel 逼近,靠近目标点/大角度转弯时降速 → 起步加速、到点缓停;
--   3) 前瞻到边界则改朝区内换目标并减速 → 消除边界顿挫。
--
-- 本 Driver 只挪载具;乘客(宝宝)由调用方在 on_step 里粘座位或另起 FollowDriver。
-- 调用方约定:销毁单位前必须先 stop()。
--
---@class PatrolSpec
---@field vehicle Unit                 -- 被驱动的载具
---@field area Unit|nil                -- 巡游触发区(选目标点 + 边界约束)
---@field max_speed Fixed|nil          -- 默认 3.0
---@field turn_speed Fixed|nil         -- 转向角速度(弧度/秒),默认 3.0
---@field accel Fixed|nil              -- 加速度,默认 6.0
---@field reach Fixed|nil              -- 到点判定半径,默认 2.0
---@field arrive_radius Fixed|nil      -- 减速半径,默认 reach*2
---@field frames integer|nil           -- 驱动步长(逻辑帧),默认 1
---@field on_step fun(pos:Vector3, rot:Quaternion)|nil -- 每步回调(乘客粘座位用)

local FRAME_DT = 1.0 / 30.0

---触发区内随机点。random_point 是现行 API;get_customtriggerspaces_random_point
---是旧版单位上的废弃别名,仅作兼容回退。
---@param area CustomTriggerSpace|Unit|nil
---@return Vector3|nil
local function random_area_point(area)
    if not area then
        return nil
    end
    if area.random_point then
        return area.random_point()
    end
    if area.get_customtriggerspaces_random_point then
        return area.get_customtriggerspaces_random_point()
    end
    return nil
end

---@param pos Vector3
---@param area Unit|nil
---@return boolean
local function point_in_area(pos, area)
    if not area then
        return true -- 无区域约束视为不出界
    end
    return GameAPI.is_point_in_customtriggerspace(pos, area) or false
end

---@class PatrolDriver
---@field _spec PatrolSpec|nil
---@field _heading Fixed
---@field _speed Fixed
---@field _target Vector3|nil
local PatrolDriver = Class("PatrolDriver")

function PatrolDriver:Ctor()
    self._spec = nil
    self._heading = 0.0
    self._speed = 0.0
    self._target = nil
end

---@param spec PatrolSpec
function PatrolDriver:start(spec)
    self:stop()
    self._spec = spec
    self._speed = 0.0
    self._target = random_area_point(spec.area)

    -- 初始朝向直接对准首个目标,避免开局甩头。
    local vpos = spec.vehicle.get_position()
    if self._target and vpos then
        self._heading = math.atan2(self._target.x - vpos.x, self._target.z - vpos.z)
    else
        self._heading = 0.0
    end

    local frames = spec.frames or 1
    Timer.every_frame(self, frames, function()
        self:_step(frames * FRAME_DT)
    end)
end

function PatrolDriver:stop()
    Timer.cancel_all(self)
    self._spec = nil
    self._target = nil
end

---@return boolean
function PatrolDriver:is_active()
    return self._spec ~= nil
end

---@private
---@param dt Fixed
function PatrolDriver:_step(dt)
    local spec = self._spec
    if not spec then
        return
    end
    local vehicle = spec.vehicle
    local vpos = vehicle.get_position()
    if not vpos then
        return
    end

    local reach = spec.reach or 2.0
    local max_speed = spec.max_speed or 3.0
    local turn_speed = spec.turn_speed or 3.0
    local accel = spec.accel or 6.0
    local arrive_radius = spec.arrive_radius or (reach * 2.0)

    -- 选/换目标点:没有目标 / 已到达
    if not self._target then
        self._target = random_area_point(spec.area)
    end
    local dist = 0.0
    if self._target then
        local dx = self._target.x - vpos.x
        local dz = self._target.z - vpos.z
        dist = math.sqrt(dx * dx + dz * dz)
        if dist <= reach then
            self._target = random_area_point(spec.area) or self._target
            dx = self._target.x - vpos.x
            dz = self._target.z - vpos.z
            dist = math.sqrt(dx * dx + dz * dz)
        end
    end

    -- 期望朝向 + 转向限速
    local desired = self._heading
    if self._target and dist > 0.01 then
        desired = math.atan2(self._target.x - vpos.x, self._target.z - vpos.z)
    end
    self._heading = MathX.approach_angle(self._heading, desired, turn_speed * dt)

    -- 目标速度:靠近目标点线性减速;朝向偏差大时降速避免甩头
    local target_speed = max_speed
    if dist < arrive_radius then
        target_speed = max_speed * (dist / arrive_radius)
    end
    if math.abs(MathX.wrap_angle(desired - self._heading)) > 0.5 then
        target_speed = target_speed * 0.4
    end
    -- 当前速度朝目标速度按加速度逼近
    if self._speed < target_speed then
        self._speed = math.min(target_speed, self._speed + accel * dt)
    else
        self._speed = math.max(target_speed, self._speed - accel * dt)
    end

    -- 沿当前朝向前进
    local ux = math.sin(self._heading)
    local uz = math.cos(self._heading)
    local step = self._speed * dt
    local new_pos = math.Vector3(vpos.x + ux * step, vpos.y, vpos.z + uz * step)

    -- 前瞻边界:下一步会出区则本拍不前进、改朝区内换目标并急减速
    if spec.area and not point_in_area(new_pos, spec.area) then
        self._target = random_area_point(spec.area) or self._target
        self._speed = self._speed * 0.5
        new_pos = vpos
    end

    local face_rot = math.Quaternion(0.0, self._heading, 0.0)
    vehicle.set_position(new_pos)
    vehicle.set_orientation(face_rot)

    if spec.on_step then
        spec.on_step(new_pos, face_rot)
    end
end

return PatrolDriver
