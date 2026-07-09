local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")
local InteractionBase = require("BabyStorm.Domain.Interaction.InteractionBase")
local FollowDriver = require("BabyStorm.Core.Drivers.FollowDriver")
local Timer = require("BabyStorm.Core.Timer")
local UnitUtil = require("Util.UnitUtil")
local MathX = require("Util.MathX")
local Log = require("Util.Log")

-- 玩家绑定型载具（滑板）：宝宝在板边等玩家，玩家站上板后宝宝跟着玩家滑行。
--
-- 上/下板检测为什么是轮询：滑板是“机关”，没有互动按钮、也不是载具，碰撞事件又是
-- 瞬时的（蹭一下就 begin+end），都无法表达“玩家正站在板上”这个持续状态。板被骑时
-- 会带着玩家一起移动，真正的骑手会持续贴在板上，旁观者会被甩开。因此判定 =
-- 持续（去抖）有非宝宝角色贴在板的水平范围内；持续离开才算下板。
-- 去抖用“确认时长”表达（原 60Hz tick 计数换算）：贴板 ≥0.2s 确认上板（滤掉路过蹭碰），
-- 离板 ≥0.3s 确认下板（滤掉跳跃/抖动瞬间脱离）。跟随的平滑度由 FollowDriver 按帧驱动
-- 提供，检测本身 0.1s 一拍足够。
---@class PlayerBoundInteraction: InteractionBase
---@field _follow FollowDriver
---@field _rider Unit|LifeEntity|nil
---@field _bind_id any
---@field _onboard Fixed
---@field _offboard Fixed
local PlayerBoundInteraction = Class("BabyPlayerBoundInteraction", InteractionBase)

local POLL_INTERVAL = 0.1
local ON_BOARD_CONFIRM = 0.2  -- 原 12 tick × 1/60s
local OFF_BOARD_CONFIRM = 0.3 -- 原 18 tick × 1/60s

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function PlayerBoundInteraction:Ctor(agent, facility)
    PlayerBoundInteraction.super.Ctor(self, agent, facility)
    self._follow = FollowDriver.New()
    self._rider = nil
    self._bind_id = nil
    self._onboard = 0.0
    self._offboard = 0.0
end

function PlayerBoundInteraction:get_intent()
    return {
        move_mode = Intent.MoveMode.Scripted, -- 等待时锁在板边；上板后位移由 FollowDriver 接管
        anim_base = Intent.AnimBase.Idle,
        action_lock = true,
    }
end

---@param _duration Fixed
function PlayerBoundInteraction:enter(_duration)
    self.agent:set_status("等待玩家上滑板")
    Timer.every(self, POLL_INTERVAL, function()
        self:_poll()
    end)
end

---@return boolean
function PlayerBoundInteraction:is_timed()
    return false
end

---@private
function PlayerBoundInteraction:_poll()
    local candidate = self:_find_player_on_board()

    if self._rider then
        -- 已上板：判断当初那个玩家是否还在板上（跟随由 FollowDriver 负责）。
        local still = candidate ~= nil and UnitUtil.same_unit(candidate, self._rider)
        self._offboard = still and 0.0 or (self._offboard + POLL_INTERVAL)
        if self._offboard >= OFF_BOARD_CONFIRM then
            self.agent:complete_facility_interaction(self.facility)
        end
    elseif candidate then
        self._onboard = self._onboard + POLL_INTERVAL
        if self._onboard >= ON_BOARD_CONFIRM then
            self:_attach(candidate)
        end
    else
        self._onboard = 0.0
    end
end

---找出“正站在板上”的非宝宝角色：水平距离贴近板本体（板会移动，按板当前位置算）。
---宝宝也是 character，必须靠注册表的宝宝判定把它从“踩板玩家”里排除掉。
---@private
---@return Unit|LifeEntity|nil
function PlayerBoundInteraction:_find_player_on_board()
    local board = self.facility.unit
    local bpos = board and board.get_position()
    if not bpos then
        return nil
    end
    local radius = self.def.vehicle_onboard_radius or 1.0
    local r2 = radius * radius
    local list = GameAPI.get_all_characters()
    if not list then
        return nil
    end

    local registry = self.agent.services.facility
    local best, best_dist = nil, nil
    for index = 1, #list do
        local char = list[index]
        if char and not registry:is_baby(char) then
            local cpos = char.get_position()
            if cpos then
                local dist = UnitUtil.distance_xz_sq(cpos, bpos)
                if dist <= r2 and (not best_dist or dist < best_dist) then
                    best, best_dist = char, dist
                end
            end
        end
    end
    return best
end

---确认上板：记录骑手、关碰撞、挂可选的装饰滑板、起跟随。
---@private
---@param rider Unit|LifeEntity
function PlayerBoundInteraction:_attach(rider)
    self._rider = rider
    self._offboard = 0.0
    self.agent:set_status("跟玩家滑行中")
    Log.info("player boarded skateboard", self.def.id, "baby", self.agent.index)

    -- 关掉宝宝与玩家/滑板之间的碰撞：否则宝宝被硬贴到玩家位置会和玩家“卡住”，
    -- 把板顶歪、还会让宝宝因受力做出踉跄等动作。下板时再恢复。
    self:_set_collision_with(rider, false)
    self:_set_collision_with(self.facility.unit, false)

    -- 引擎限制：只能把模型挂到宝宝挂点上，不能把宝宝绑到玩家/物体身上；也绝不能绑
    -- “玩家正踩着的真机关板”（会把板从玩家脚下抢走）。所以只绑可选的“装饰滑板模型”。
    self:_attach_decoration_model()

    -- 位置参考骑手（局部偏移随玩家朝向走）、朝向参考滑板本体（玩家身上叠了转身/动作的倾，
    -- 照搬会失真；板本体的朝向才是板真实的倾）。smooth 让引擎在逻辑帧之间插值，跟随不卡顿。
    self._follow:start({
        unit = self.agent.unit,
        target = rider,
        offset = MathX.to_vector3(self.def.vehicle_follow_offset),
        orient = "target",
        orient_target = self.facility.unit,
        orient_offset = MathX.to_quaternion(self.def.vehicle_follow_rotation),
        smooth = true,
    })
end

---给宝宝挂一个装饰滑板模型（可选）。用 bind_model(模型UnitKey)，不碰玩家正踩的真机关。
---@private
function PlayerBoundInteraction:_attach_decoration_model()
    local def = self.def
    if not def.vehicle_passenger_model then
        return
    end
    local socket_name = def.vehicle_passenger_socket or "socket_origin"
    local socket = Enums.ModelSocket[socket_name] or Enums.ModelSocket.socket_origin
    self._bind_id = self.agent.unit.bind_model(
        def.vehicle_passenger_model,
        socket,
        MathX.to_vector3(def.vehicle_passenger_offset),
        MathX.to_quaternion(def.vehicle_passenger_rotation),
        MathX.to_vector3(def.vehicle_passenger_scale)
    )
    if self._bind_id then
        Log.info("deco skateboard bound onto baby", def.id, "baby", self.agent.index, "bind", self._bind_id)
    else
        Log.warn("failed to bind deco skateboard", def.id, self.agent.index)
    end
end

function PlayerBoundInteraction:exit()
    self._follow:stop()
    if self._rider then
        -- 先恢复碰撞（此时 _rider 还在，能正确还原与玩家的碰撞），再解绑装饰模型。
        self:_set_collision_with(self._rider, true)
        self:_set_collision_with(self.facility.unit, true)
        if self._bind_id then
            self.agent.unit.unbind_model(self._bind_id)
        end
        self._rider = nil
        self._bind_id = nil
    end
    PlayerBoundInteraction.super.exit(self)
end

return PlayerBoundInteraction
