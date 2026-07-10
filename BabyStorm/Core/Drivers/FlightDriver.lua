local Class = require("BaseClass")
local Timer = require("BabyStorm.Core.Timer")
local MathX = require("Util.MathX")

-- 运动学飞行驱动:把单位每步平滑钉到参数化轨迹上,合并两处历史实现——
--   * BallRallyService._begin_kinematic_flight/_drive_ball_kinematic(抛物弧线,ease_out_in)
--   * PlayRpsState._toss_die(纯垂直上抛,ease_out)
--
-- 只管位移,不管物理:重力/速度清零、物理开关等归 Prop/调用方,
-- 驱动期间调用方须先自行关闭引擎重力(否则引擎积分会把单位甩离轨道)。
-- 用 set_position_smooth 让引擎在两步之间插值(视觉丝滑);
-- 绝不 set_linear_velocity——给引擎初速度会把球甩离轨道、飞出界被销毁(历史 bug)。
--
---@class FlightSpec
---@field unit Unit|Obstacle          -- 被驱动的单位(球/骰子)
---@field from Vector3
---@field to Vector3
---@field duration Fixed
---@field arc_peak Fixed|nil          -- 抛物拱高;nil/0 = 无拱(垂直上抛/直线)
---@field hang Fixed|nil              -- ease_out_in 中段悬停 [0,1](沙滩球用)
---@field ease "out_in"|"out"|nil     -- 默认 "out_in";"out" = 纯减速(骰子垂直上抛)
---@field frames integer|nil          -- 驱动步长(逻辑帧),默认 1(30fps)
---@field on_complete fun()|nil       -- 进度首次到 1.0 时回调一次(已自动 stop)

local FRAME_DT = 1.0 / 30.0

---@class FlightDriver
---@field _spec FlightSpec|nil
---@field _elapsed Fixed
local FlightDriver = Class("FlightDriver")

function FlightDriver:Ctor()
    self._spec = nil
    self._elapsed = 0.0
end

---@param spec FlightSpec
function FlightDriver:start(spec)
    self:stop()
    self._spec = spec
    self._elapsed = 0.0
    local frames = spec.frames or 1
    Timer.every_frame(self, frames, function()
        self._elapsed = self._elapsed + frames * FRAME_DT
        self:_step()
    end)
end

function FlightDriver:stop()
    Timer.cancel_all(self)
    self._spec = nil
end

---@return boolean
function FlightDriver:is_active()
    return self._spec ~= nil
end

---@private
function FlightDriver:_step()
    local spec = self._spec
    if not spec then
        return
    end

    local s = self._elapsed / spec.duration
    if s > 1.0 then
        s = 1.0
    end
    local u
    if spec.ease == "out" then
        u = MathX.ease_out(s)
    else
        u = MathX.ease_out_in(s, spec.hang)
    end
    local arc = 0.0
    if spec.arc_peak and spec.arc_peak > 0.0 then
        -- 4*peak*u*(1-u):顶点在中段,s=1 时精确落回 to.y。
        arc = 4.0 * spec.arc_peak * u * (1.0 - u)
    end
    local pos = math.Vector3(
        MathX.lerp(spec.from.x, spec.to.x, u),
        MathX.lerp(spec.from.y, spec.to.y, u) + arc,
        MathX.lerp(spec.from.z, spec.to.z, u)
    )

    -- pcall 豁免理由:球/骰子可被玩家丢出世界边界而被引擎销毁,飞行中途单位可能失效。
    local unit = spec.unit
    pcall(function()
        if unit.set_position_smooth then
            unit.set_position_smooth(pos)
        else
            unit.set_position(pos)
        end
    end)

    if s >= 1.0 then
        local on_complete = spec.on_complete
        self:stop()
        if on_complete then
            on_complete()
        end
    end
end

return FlightDriver
