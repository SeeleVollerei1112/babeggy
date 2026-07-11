local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

local ZERO = math.Vector3(0.0, 0.0, 0.0)

-- 骰子“本地轴 → 手势”标定：零旋转下 +Y(上)=布、+Z(屏幕外)=剪刀、+X(右)=石头。
-- 每条轴的两个面（正/背）是同一手势，所以只按轴映射、忽略正负号（读到的是绝对朝上轴）。
local AXIS_GESTURE = {
    { n = math.Vector3(1.0, 0.0, 0.0), gesture = "rock" },     -- 石头（右）
    { n = math.Vector3(0.0, 1.0, 0.0), gesture = "paper" },    -- 布（上）
    { n = math.Vector3(0.0, 0.0, 1.0), gesture = "scissors" }, -- 剪刀（屏幕外）
}
-- a 克制谁：石头>剪刀>布>石头。
local BEATS = { rock = "scissors", scissors = "paper", paper = "rock" }

-- 猜拳骰子道具能力层：只管两颗骰子本身的引擎接口（举起开关/物理开关/读面/判负），
-- 不持有任何流程状态——配对/抛掷/顶撞的节奏由 PlayRpsState 决定。
---@class DiceProp
---@field cfg BabyRpsConfig
---@field triggers TriggerRegistry
---@field dice (Obstacle|Unit)[]
---@field holders table<integer, Unit|LifeEntity|nil>
---@field _listener fun(event: table)|nil
local DiceProp = Class("DiceProp")

---@param config BabyStormConfig
---@param triggers TriggerRegistry
function DiceProp:Ctor(config, triggers)
    self.cfg = config.rps
    self.triggers = triggers
    self.dice = {}
    self.holders = {}
    self._listener = nil
end

---@return boolean
function DiceProp:init()
    local cfg = self.cfg
    for index = 1, #cfg.dice_names do
        local die = LuaAPI.query_unit(cfg.dice_names[index])
        if not die then
            Log.warn("rps missing die", cfg.dice_names[index])
            self.dice = {}
            return false
        end
        self.dice[index] = die
        die.set_lifted_enabled(true)
        -- 归零原生投掷力：原生抛掷是“沿朝向向前抛”，会把骰子甩向前方。
        -- 猜拳要的是“垂直于头顶抛起”，因此抛掷全程由脚本控位移（见 PlayRpsState._begin_toss），
        -- 松手瞬间不产生任何向前的冲力。
        die.set_custom_thrown_force(0.0)
        die.set_custom_thrown_force_enabled(true)
        self:_register_die_events(die, index)
    end
    Log.info("rps ready", cfg.dice_names[1], cfg.dice_names[2])
    return true
end

---@param die Obstacle|Unit
---@param index integer
function DiceProp:_register_die_events(die, index)
    -- 方法参数属于独立调用帧，避免循环变量被两个骰子的回调共同捕获。
    self.triggers:unit(die, { EVENT.SPEC_OBSTACLE_LIFTED_BEGIN }, function(_, _, data)
        self:_on_lift_begin(index, data)
    end)
    self.triggers:unit(die, { EVENT.SPEC_OBSTACLE_LIFTED_END }, function(_, _, data)
        self:_on_lift_end(index, data)
    end)
end

---@param index integer
---@param data table|nil
function DiceProp:_on_lift_begin(index, data)
    local lift_unit = data and data.lift_unit or nil
    self.holders[index] = lift_unit
    if self._listener then
        self._listener({ type = "dice_lift_begin", index = index, lift_unit = lift_unit })
    end
end

---@param index integer
---@param data table|nil
function DiceProp:_on_lift_end(index, data)
    self.holders[index] = nil
    if self._listener then
        self._listener({ type = "dice_lift_end", index = index, lift_unit = data and data.lift_unit or nil })
    end
end

---@param fn fun(event: table)
function DiceProp:set_listener(fn)
    self._listener = fn
end

function DiceProp:clear_listener()
    self._listener = nil
end

---@param index integer
---@return Obstacle|Unit|nil
function DiceProp:get(index)
    return self.dice[index]
end

---@param index integer
---@return Unit|LifeEntity|nil
function DiceProp:holder(index)
    return self.holders[index]
end

-- 某颗骰子当前位置：骰子可能在抛掷/顶撞中被打飞出界被引擎销毁，读取保留 pcall
-- （PlayRpsState._dice_at_rest / _baby_bonk_dir 统一改调本方法）。
---@param index integer
---@return Vector3|nil
function DiceProp:position(index)
    local die = self.dice[index]
    if not die then
        return nil
    end
    local ok, pos = pcall(function() return die.get_position() end)
    return ok and pos or nil
end

---@return integer
function DiceProp:count()
    return #self.dice
end

---@param unit Unit|LifeEntity|nil
---@param index integer
---@return boolean
function DiceProp:is_held_by(unit, index)
    local die = self.dice[index]
    if not (unit and die) then
        return false
    end
    -- unit 可能是断线玩家的单位，读取保留 pcall。
    local ok, held = pcall(function() return unit.get_lifted_obstacle() end)
    return ok and UnitUtil.same_unit(held, die) or false
end

-- 准备一颗骰子的垂直上抛：关物理、清速度，位移全程交给 FlightDriver 控制。
-- 到达顶点后才交还物理（见 restore_physics），让它真正自由下落，这样才有一段
-- 可以被顶/被撞的空中时间，而不是刚交还物理就已经贴地。
---@param index integer
function DiceProp:freeze_for_toss(index)
    local die = self.dice[index]
    -- 骰子可能被玩家丢出界销毁，物理开关保留 pcall（同 read_gesture 的豁免理由）。
    pcall(function()
        die.set_linear_velocity(ZERO)
        die.set_angular_velocity(ZERO)
        die.disable_gravity()
        die.set_physics_active(false)
    end)
end

-- 交还物理引擎：恢复重力与碰撞，让骰子从高处真正自由下落——这段真实物理下落期间
-- 才能被顶/被撞，翻面也由真实碰撞产生，脚本不吸附朝向。
---@param index integer
function DiceProp:restore_physics(index)
    local die = self.dice[index]
    -- 状态 exit 的兜底恢复会在骰子可能已被打飞出界销毁后调用，保留 pcall。
    pcall(function()
        die.set_linear_velocity(ZERO)
        die.set_angular_velocity(ZERO)
        die.set_physics_active(true)
        die.enable_gravity()
    end)
end

-- 读某颗骰子静止后“朝上的完整面”对应的手势：把三条本地轴用骰子当前朝向(四元数)旋到世界坐标，
-- 取竖直分量绝对值最大的那条轴（背/正面同手势，符号无所谓）。该绝对值即“此面与竖直方向的余弦”，
-- 越接近 1 越平；低于 settle_face_up_tolerance 说明是棱/角立起（平地极罕见），判为没干净落面、返回 nil。
---@param index integer
---@return string|nil
function DiceProp:read_gesture(index)
    local die = self.dice[index]
    -- 骰子可能在抛掷/顶撞中被打飞出界而被引擎销毁，orientation 查询保留 pcall。
    local ok, rot = pcall(function() return die.get_orientation() end)
    if not (ok and rot) then
        return nil
    end
    local best_abs, best_gesture = -1.0, nil
    for i = 1, #AXIS_GESTURE do
        local axis = AXIS_GESTURE[i]
        local wok, world_n = pcall(function() return rot:apply(axis.n) end)
        if wok and world_n then
            local up = world_n.y
            if up < 0.0 then up = -up end
            if up > best_abs then
                best_abs = up
                best_gesture = axis.gesture
            end
        end
    end
    if best_abs < self.cfg.settle_face_up_tolerance then
        return nil -- 棱/角着地，没有一个完整面朝上
    end
    return best_gesture
end

-- 落地判胜负（玩家视角）：两个手势都读到干净的朝上面才判，否则返回 nil（本次不判胜负）。
---@param baby_gesture string|nil
---@param player_gesture string|nil
---@return "win"|"draw"|"lose"|nil
function DiceProp:judge_outcome(baby_gesture, player_gesture)
    if not (baby_gesture and player_gesture) then
        Log.info("rps outcome unresolved", tostring(baby_gesture), tostring(player_gesture))
        return nil
    end
    local result
    if player_gesture == baby_gesture then
        result = "draw"
    elseif BEATS[player_gesture] == baby_gesture then
        result = "win"
    else
        result = "lose"
    end
    Log.info("rps outcome", "player", player_gesture, "baby", baby_gesture, "=>", result)
    return result
end

function DiceProp:destroy()
    -- 抛掷期间可能关过物理，销毁时兜底恢复，避免骰子永久停在半空/不可交互。
    for index = 1, #self.dice do
        local die = self.dice[index]
        pcall(function()
            die.set_physics_active(true)
            die.enable_gravity()
        end)
    end
    self.dice = {}
    self.holders = {}
    self._listener = nil
    Log.info("rps dice destroyed")
end

return DiceProp
