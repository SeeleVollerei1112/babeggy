local Class = require("BaseClass")
local Timer = require("BabyStorm.Core.Timer")

-- 秋千泵力驱动:周期性给物理座椅施力,自 FacilityService._drive_swing_force 平移。
-- 顺着座椅当前水平运动方向推("泵"能量),自然越摆越高、不依赖相位;
-- 接近静止(起摆/端点)时按 push_dir 给一推把秋千起起来;
-- 速度超过 max_speed 不再加力,避免越摆越飞。
--
-- 调用方约定:结束时 stop() 后自行清掉座椅速度(让它停摆),Driver 只管施力。
--
---@class SwingPumpSpec
---@field seat Unit                -- 物理刚体座椅
---@field magnitude Fixed          -- 施力大小
---@field max_speed Fixed          -- 水平速度上限
---@field push_dir Vector3|nil     -- 起摆方向,默认 +X
---@field interval Fixed|nil       -- 施力节拍,默认 0.2s

---@class SwingPumpDriver
---@field _spec SwingPumpSpec|nil
local SwingPumpDriver = Class("SwingPumpDriver")

function SwingPumpDriver:Ctor()
    self._spec = nil
end

---@param spec SwingPumpSpec
function SwingPumpDriver:start(spec)
    self:stop()
    self._spec = spec
    Timer.every(self, spec.interval or 0.2, function()
        self:_step()
    end)
end

function SwingPumpDriver:stop()
    Timer.cancel_all(self)
    self._spec = nil
end

---@return boolean
function SwingPumpDriver:is_active()
    return self._spec ~= nil
end

---@private
function SwingPumpDriver:_step()
    local spec = self._spec
    if not spec then
        return
    end
    local seat = spec.seat
    local mag = spec.magnitude
    local fx, fz = 0.0, 0.0

    local v = seat.get_linear_velocity()
    local horiz = v and math.sqrt(v.x * v.x + v.z * v.z) or 0.0
    if horiz > 0.05 then
        -- 顺着当前运动方向推;已达上限则本拍不加力。
        if horiz < spec.max_speed then
            fx = v.x / horiz * mag
            fz = v.z / horiz * mag
        end
    else
        -- 几乎静止:按配置方向起摆。
        local dir = spec.push_dir or math.Vector3(1.0, 0.0, 0.0)
        fx, fz = dir.x * mag, dir.z * mag
    end
    if fx ~= 0.0 or fz ~= 0.0 then
        seat.apply_force(math.Vector3(fx, 0.0, fz))
    end
end

return SwingPumpDriver
