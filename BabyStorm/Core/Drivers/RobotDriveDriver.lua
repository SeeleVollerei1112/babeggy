local Class = require("BaseClass")
local Timer = require("BabyStorm.Core.Timer")
local MathX = require("Util.MathX")
local UnitUtil = require("Util.UnitUtil")

local FRAME_DT = math.tofixed(1) / math.tofixed(30)
local ZERO = math.tofixed(0)

---@class RobotDriveSpec
---@field robot Unit
---@field player Unit|LifeEntity
---@field move_speed Fixed
---@field spin_speed Fixed
---@field joystick_deadzone Fixed
---@field flat_roll_degrees Fixed
---@field collision_radius Fixed
---@field collision_probe_height Fixed
---@field collision_skin Fixed
---@field should_block fun(unit:Unit):boolean|nil
---@field on_step fun(position:Vector3)|nil

-- 扫地机器人连续运动驱动。
-- 唯一位移入口是 set_position_smooth；控制器只负责进入/退出会话。
---@class RobotDriveDriver
---@field _spec RobotDriveSpec|nil
---@field _height Fixed|nil
---@field _position Vector3|nil
---@field _spin_angle Fixed
---@field _flat_roll Fixed
local RobotDriveDriver = Class("RobotDriveDriver")

function RobotDriveDriver:Ctor()
    self._spec = nil
    self._height = nil
    self._position = nil
    self._spin_angle = ZERO
    self._flat_roll = math.deg_to_rad(math.tofixed(90))
end

function RobotDriveDriver:reset_spin()
    self._spin_angle = ZERO
end

---@param spec RobotDriveSpec
---@return boolean
function RobotDriveDriver:start(spec)
    self:stop()

    local robot = spec and spec.robot or nil
    local player = spec and spec.player or nil
    if not (robot and robot.get_position and robot.set_position_smooth) then
        return false
    end
    if not (player and player.get_joystick_direction) then
        return false
    end

    local pos = robot.get_position()
    if not pos then
        return false
    end

    self._spec = spec
    self._height = pos.y
    self._position = pos
    self._flat_roll = math.deg_to_rad(spec.flat_roll_degrees)
    Timer.every_frame(self, 1, function()
        self:_step()
    end)
    return true
end

function RobotDriveDriver:stop()
    Timer.cancel_all(self)
    self._spec = nil
    self._height = nil
    self._position = nil
end

---@return boolean
function RobotDriveDriver:is_active()
    return self._spec ~= nil
end

---@private
function RobotDriveDriver:_step()
    local spec = self._spec
    if not spec then
        return
    end

    local pos = self._position
    if not pos then
        return
    end

    local direction = spec.player.get_joystick_direction()
    if direction then
        local dx = direction.x
        local dz = direction.z
        local magnitude_squared = dx * dx + dz * dz
        local deadzone_squared = spec.joystick_deadzone * spec.joystick_deadzone
        if magnitude_squared > deadzone_squared then
            local magnitude = math.sqrt(magnitude_squared)
            local unit_x = dx / magnitude
            local unit_z = dz / magnitude
            local step = spec.move_speed * FRAME_DT
            local target_pos = math.Vector3(
                pos.x + unit_x * step,
                self._height,
                pos.z + unit_z * step
            )
            if self:_would_hit_obstacle(spec, pos, unit_x, unit_z, step) then
                -- set_position_smooth 可能仍在追上一帧目标；把逻辑点收回实际位置并发一个停止目标。
                local actual = spec.robot.get_position()
                if actual then
                    self._position = math.Vector3(actual.x, self._height, actual.z)
                    spec.robot.set_position_smooth(self._position)
                end
            else
                self._position = target_pos
                spec.robot.set_position_smooth(target_pos)
            end
        end
    end

    -- 轮盘只控制位移；最终朝向只取自转相位，保证左右切换时角速度恒定。
    self._spin_angle = MathX.wrap_angle(
        self._spin_angle + spec.spin_speed * FRAME_DT
    )
    local target_rot = math.Quaternion(ZERO, self._spin_angle, self._flat_roll)
    if spec.robot.set_orientation_smooth then
        spec.robot.set_orientation_smooth(target_rot)
    elseif spec.robot.set_orientation then
        spec.robot.set_orientation(target_rot)
    end

    if spec.on_step then
        spec.on_step(self._position)
    end
end

---用三条水平射线近似扫掠机器人宽度。直接位移不会获得可靠的刚体阻挡，
---因此在 set_position_smooth 前主动拒绝会穿入普通组件的目标。
---@param spec RobotDriveSpec
---@param pos Vector3
---@param unit_x Fixed
---@param unit_z Fixed
---@param step Fixed
---@return boolean
function RobotDriveDriver:_would_hit_obstacle(spec, pos, unit_x, unit_z, step)
    if not GameAPI.get_obstacles_by_raycast then
        return false
    end

    local radius = spec.collision_radius
    local probe_y = pos.y + spec.collision_probe_height
    local forward = step + radius + spec.collision_skin
    local side_x = -unit_z
    local side_z = unit_x

    for lane = -1, 1 do
        local side = radius * math.tofixed(lane)
        local start_pos = math.Vector3(
            pos.x + side_x * side,
            probe_y,
            pos.z + side_z * side
        )
        local end_pos = math.Vector3(
            start_pos.x + unit_x * forward,
            probe_y,
            start_pos.z + unit_z * forward
        )

        local ok, hits = pcall(function()
            return GameAPI.get_obstacles_by_raycast(start_pos, end_pos)
        end)
        if ok and hits then
            for index = 1, #hits do
                local hit = hits[index]
                if not UnitUtil.same_unit(hit, spec.robot)
                    and (not spec.should_block or spec.should_block(hit)) then
                    return true
                end
            end
        end
    end
    return false
end

return RobotDriveDriver
