local Class = require("BaseClass")
local Log = require("Util.Log")

local ZERO = math.Vector3(0.0, 0.0, 0.0)

-- 顶球道具能力层：只管场上沙滩球本身的引擎接口（举起开关/物理开关/碰撞/运动学落点定位），
-- 不持有任何流程状态——发球/等待/接力/庆祝的节奏由 BallRallyState 决定。
---@class BallProp
---@field cfg BabyBallRallyConfig
---@field triggers TriggerRegistry
---@field _balls (Obstacle|Unit)[]
---@field _listener fun(event: table)|nil
local BallProp = Class("BallProp")

---@param config BabyStormConfig
---@param triggers TriggerRegistry
function BallProp:Ctor(config, triggers)
    self.cfg = config.ball_rally
    self.triggers = triggers
    self._balls = {}
    self._listener = nil
end

---@return boolean
function BallProp:init()
    local cfg = self.cfg
    self._balls = {}
    for index = 1, #cfg.ball_names do
        local name = cfg.ball_names[index]
        local ball = LuaAPI.query_unit(name)
        if ball then
            self._balls[#self._balls + 1] = ball
            self:_configure_ball(ball)
            self:_register_ball_events(ball)
        else
            Log.warn("ball rally missing ball", name)
        end
    end

    if #self._balls == 0 then
        Log.warn("ball rally no balls available")
        return false
    end
    Log.info("ball rally ready", #self._balls, "balls")
    return true
end

-- 球可能被玩家丢出界销毁（reconfigure 在每局开始时重申配置），引擎写入保留 pcall。
---@param ball Obstacle|Unit
function BallProp:_configure_ball(ball)
    pcall(function()
        ball.set_lifted_enabled(true)
        ball.set_physics_active(true)
        -- 空转/待命时保持重力开启，让球自然落地静止。
        -- （此前这里关掉重力做“运动学待命”，但 physics_active + 无重力时，
        --  球一旦与地面/围栏轻微穿插，引擎每帧把它往外顶又没有重力拉回 → 一直缓缓上飘。
        --  真正的运动学飞行会在 prepare_flight / hold_at 各自临时关重力，
        --  落地收尾再交还给这里的重力，不依赖本函数关重力。）
        ball.enable_gravity()
        ball.enable_unit_ccd()
    end)
end

-- 一局开始时重新接管某颗球：幂等地重申举起/物理/重力/CCD 开关
-- （原 `_begin_session` 里对当前会话球调用 `_configure_ball()` 的等价物）。
---@param ball Obstacle|Unit
function BallProp:reconfigure(ball)
    self:_configure_ball(ball)
end

---@param ball Obstacle|Unit
function BallProp:_register_ball_events(ball)
    self.triggers:unit(ball, { EVENT.SPEC_OBSTACLE_LIFTED_END }, function()
        if self._listener then
            self._listener({ type = "ball_lift_end", ball = ball })
        end
    end)
end

---@param fn fun(event: table)
function BallProp:set_listener(fn)
    self._listener = fn
end

---@return (Obstacle|Unit)[]
function BallProp:balls()
    return self._balls
end

-- 球是否处于“自由静止可接管”状态：没有被玩家/宝宝举着。
-- 球可能已被丢出界销毁，is_lifted_status 读取保留 pcall。
---@param ball Obstacle|Unit|nil
---@return boolean
function BallProp:is_free(ball)
    if not ball then
        return false
    end
    local ok, lifted = pcall(function() return ball.is_lifted_status() end)
    if ok and lifted then
        return false
    end
    return true
end

-- 把球钉在指定位置持球等待（发球前的头顶举球 / 庆祝时的头顶举球共用）：
-- 清线/角速度、开物理、关重力（脚本钉住，不受引擎重力影响）、设置位置。
---@param ball Obstacle|Unit
---@param pos Vector3
function BallProp:hold_at(ball, pos)
    pcall(function()
        ball.set_linear_velocity(ZERO)
        ball.set_angular_velocity(ZERO)
        ball.set_physics_active(true)
        ball.disable_gravity()
        ball.set_position(pos)
    end)
end

-- 准备一段运动学飞行：关重力、清零速度，位移全程交给 FlightDriver 控制。
---@param ball Obstacle|Unit
---@param start_pos Vector3
function BallProp:prepare_flight(ball, start_pos)
    pcall(function()
        ball.set_physics_active(true)
        ball.disable_gravity()
        -- 碰撞会留下角速度；不清零会让沙滩球纹理呈现螺旋回转。
        ball.set_angular_velocity(ZERO)
        ball.set_position(start_pos)
        -- 运动学驱动独占球的运动：线速度清零，绝不把解析初速度交给引擎。
        -- 否则引擎会在 tick 之间按该初速度（叠加残留重力/碰撞）把球甩离轨道、
        -- 飞出世界被销毁，引发后续球引用失效、整局连续判失败。
        ball.set_linear_velocity(ZERO)
    end)
end

-- 一局收尾：恢复引擎重力让它自然落地停住——否则飞行期间临时关掉的重力会让球悬在半空
-- （用户反馈“球靠在围栏上飘起来”）。被举着的球（was_held=true）由宝宝放下即可，
-- 不用清速度；漏接/出界的球（was_held=false）清零残余速度原地落下。
---@param ball Obstacle|Unit
---@param was_held boolean
function BallProp:settle(ball, was_held)
    pcall(function()
        if not was_held then
            ball.set_angular_velocity(ZERO)
            ball.set_linear_velocity(ZERO)
        end
        ball.enable_gravity()
    end)
end

-- 球与玩家/宝宝的碰撞开关：球可能已被丢出界销毁，保留 pcall。
---@param ball Obstacle|Unit|nil
---@param unit Unit|LifeEntity|nil
---@param enable boolean
function BallProp:set_collision_with(ball, unit, enable)
    if not (ball and unit) then
        return
    end
    pcall(function()
        GameAPI.enable_collision_between_units(ball, unit, enable)
    end)
end

function BallProp:destroy()
    -- 兜底恢复所有球的物理与重力，避免销毁时把球留在关重力/半空状态。
    for index = 1, #self._balls do
        local ball = self._balls[index]
        pcall(function()
            ball.set_physics_active(true)
            ball.enable_gravity()
        end)
    end
    self._balls = {}
    self._listener = nil
    Log.info("ball rally balls destroyed")
end

return BallProp
