local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

---@class BabyFacilityRecord
---@field def BabyNeedDef
---@field unit Unit|nil
---@field area Unit|nil
---@field contact_area Unit|nil
---@field active_agent BabyAgent|nil
---@field bind_id any
---@field rider Unit|LifeEntity|nil
---@field seat_token integer|nil
---@field onboard_streak integer|nil
---@field offboard_streak integer|nil
---@field drive { heading: Fixed, speed: Fixed, target: Vector3|nil }|nil

---@class FacilityService
---@field config BabyStormConfig
---@field resolver NeedResolver|nil
---@field trigger_registry TriggerRegistry|nil
---@field facilities BabyFacilityRecord[]
---@field seat_token integer|nil
local FacilityService = Class("FacilityService")

---@param config BabyStormConfig
function FacilityService:Ctor(config)
    self.config = config
    self.resolver = nil
    self.trigger_registry = nil
    self.facilities = {}
    self.seat_token = 0
    self.is_baby_unit = nil
end

---@param resolver NeedResolver
function FacilityService:set_need_resolver(resolver)
    self.resolver = resolver
end

---@param registry TriggerRegistry
function FacilityService:set_trigger_registry(registry)
    self.trigger_registry = registry
end

---注入“是否宝宝单位”判定。宝宝也是 character，必须靠它把宝宝从“踩板玩家”里排除掉。
---@param fn fun(unit:Unit|LifeEntity|nil):boolean
function FacilityService:set_baby_unit_filter(fn)
    self.is_baby_unit = fn
end

---@return nil
function FacilityService:init()
    local needs = self.config.needs
    for index = 1, #needs do
        local need = needs[index]
        if self.resolver and self.resolver:is_facility_need(need) then
            self:_register_facility(need)
        end
    end
end

---@param need BabyNeedDef
---@return BabyFacilityRecord
function FacilityService:_register_facility(need)
    local unit = need.facility_name and LuaAPI.query_unit(need.facility_name) or nil
    local area = need.area_name and LuaAPI.query_unit(need.area_name) or nil
    local contact_area = need.contact_area_name and LuaAPI.query_unit(need.contact_area_name) or nil

    if not unit then
        Log.warn("missing facility unit", need.id, need.facility_name)
    end
    if not area then
        Log.warn("missing facility area", need.id, need.area_name)
    end
    if need.contact_area_name and not contact_area then
        Log.warn("missing facility contact area", need.id, need.contact_area_name)
    end

    self:_configure_facility_unit(unit, need)

    local facility = {
        def = need,
        unit = unit,
        area = area,
        contact_area = contact_area,
        active_agent = nil,
    }
    self.facilities[#self.facilities + 1] = facility
    return facility
end

---@param facility BabyFacilityRecord|nil
---@return boolean
function FacilityService:is_player_bound(facility)
    return facility ~= nil and facility.def ~= nil
        and facility.def.facility_kind == "vehicle"
        and facility.def.vehicle_drive_mode == "player_bound"
end

-- ===== player_bound 检测：轮询“谁站在板上” =====
-- 滑板是“机关”，没有互动按钮、也不是载具，碰撞事件又是瞬时的（蹭一下就 begin+end），
-- 都无法表达“玩家正站在板上”这个持续状态。玩法是“站到板上、板载着玩家跑”，所以改成轮询：
-- 板被骑时会带着玩家一起移动，真正的骑手会持续贴在板上，旁观者会被甩开。
-- 因此判定 = 持续（去抖）有非宝宝角色贴在板的水平范围内；持续离开才算下板。
local PLAYER_BOUND_DT = 0.0166 -- ~60Hz：跟随/朝向逼近的步子更细腻，配合 smooth 接口不卡顿
local ON_BOARD_TICKS = 12      -- 连续约 0.2s 贴在板上才确认上板（滤掉路过蹭碰）
local OFF_BOARD_TICKS = 18     -- 连续约 0.3s 离开板才确认下板（滤掉跳跃/抖动瞬间脱离）

---找出“正站在板上”的非宝宝角色：水平距离贴近板本体（板会移动，按板当前位置算）。
---@param facility BabyFacilityRecord
---@return Unit|LifeEntity|nil
function FacilityService:_find_player_on_board(facility)
    local board = facility.unit
    local bpos = board and board.get_position and board.get_position()
    if not (bpos and GameAPI.get_all_characters) then
        return nil
    end
    local radius = facility.def.vehicle_onboard_radius or 1.0
    local r2 = radius * radius
    local ok, list = pcall(function() return GameAPI.get_all_characters() end)
    if not (ok and list) then
        return nil
    end

    local best, best_dist = nil, nil
    for index = 1, #list do
        local char = list[index]
        local is_baby = self.is_baby_unit ~= nil and self.is_baby_unit(char) or false
        if char and not is_baby and char.get_position then
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

---每帧轮询：等待上板 / 跟随 / 判定下板。token 失效（下板或换人）即自动停止。
---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param token integer
function FacilityService:_player_bound_tick(agent, facility, token)
    if agent.destroyed or facility.active_agent ~= agent or facility.seat_token ~= token then
        return
    end

    local on_board = self:_find_player_on_board(facility)

    if facility.rider then
        -- 已上板：跟随玩家，并判断当初那个玩家是否还在板上
        local still = on_board ~= nil and UnitUtil.same_unit(on_board, facility.rider)
        facility.offboard_streak = still and 0 or ((facility.offboard_streak or 0) + 1)
        self:_snap_baby_to_rider(agent, facility)
        if (facility.offboard_streak or 0) >= OFF_BOARD_TICKS then
            agent:complete_facility_interaction(facility)
            return
        end
    else
        -- 等待上板：连续 ON_BOARD_TICKS 拍都有玩家贴在板上才确认
        if on_board then
            facility.onboard_streak = (facility.onboard_streak or 0) + 1
            if (facility.onboard_streak or 0) >= ON_BOARD_TICKS then
                self:_attach_player_bound_passenger(facility, on_board)
            end
        else
            facility.onboard_streak = 0
        end
    end

    LuaAPI.call_delay_time(PLAYER_BOUND_DT, function()
        self:_player_bound_tick(agent, facility, token)
    end)
end

---把宝宝跟随到玩家身上（含跳跃高度），按配置抬高/侧移；位置走平滑接口、朝向走可调转速逼近。
---每帧由 _player_bound_tick 调用。
---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_snap_baby_to_rider(agent, facility)
    local rider = facility.rider
    if not (rider and agent.unit) then
        return
    end
    local def = facility.def

    -- 位置：优先用玩家“局部坐标系偏移”（抬高/侧移会随玩家朝向走），退化为玩家世界坐标。
    -- 用 set_position_smooth 让引擎在两次更新间插值，跟随不一卡一卡。
    local offset = self:_to_vector3(def.vehicle_follow_offset)
    local pos = nil
    if offset and rider.get_local_offset_position then
        local ok, p = pcall(function() return rider.get_local_offset_position(offset) end)
        if ok and p then
            pos = p
        end
    end
    if not pos and rider.get_position then
        pos = rider.get_position()
    end
    if pos then
        if agent.unit.set_position_smooth then
            pcall(function() agent.unit.set_position_smooth(pos) end)
        elseif agent.unit.set_position then
            pcall(function() agent.unit.set_position(pos) end)
        end
    end

    -- 朝向：跟随玩家
    self:_follow_rider_orientation(agent, facility)
end

---朝向跟随：直接同步“滑板本体”的完整朝向（含 pitch/roll），让宝宝和滑板一起倾斜、贴在板上。
---参考滑板而非玩家：玩家身上还叠了转身/动作的倾，照搬会失真；滑板本体的朝向才是板真实的倾。
---用 set_orientation_smooth 让引擎在逻辑帧之间插值，和 set_position_smooth 一致 → 跟随节奏统一、不卡。
---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_follow_rider_orientation(agent, facility)
    local board = facility.unit
    if not (board and board.get_orientation and agent.unit) then
        return
    end
    local ok, rot = pcall(function() return board.get_orientation() end)
    if not (ok and rot) then
        return
    end

    -- 可选：在滑板朝向基础上叠加固定角度偏移（局部右乘），默认 {0,0,0} = 和滑板朝向完全一致
    local off = self:_to_quaternion(facility.def.vehicle_follow_rotation)
    if off then
        local mok, composed = pcall(function() return rot * off end)
        if mok and composed then
            rot = composed
        end
    end

    if agent.unit.set_orientation_smooth then
        pcall(function() agent.unit.set_orientation_smooth(rot) end)
    elseif agent.unit.set_orientation then
        pcall(function() agent.unit.set_orientation(rot) end)
    end
end

---确认上板：记录骑手、切状态、挂可选的装饰滑板。跟随由轮询循环负责，这里不再起循环。
---@param facility BabyFacilityRecord
---@param rider Unit|LifeEntity
function FacilityService:_attach_player_bound_passenger(facility, rider)
    local agent = facility.active_agent
    if not (agent and agent.unit) or facility.rider then
        return
    end

    facility.rider = rider
    facility.offboard_streak = 0
    agent:set_status("跟玩家滑行中")
    Log.info("player boarded skateboard", facility.def.id, "baby", agent.index)

    -- 关掉宝宝与玩家/滑板之间的碰撞：否则宝宝被硬贴到玩家位置会和玩家“卡住”，把板顶歪、
    -- 还会让宝宝因受力做出踉跄等动作。下板时再恢复。
    self:_set_player_bound_collision(agent, facility, false)

    -- 引擎限制：只能把模型挂到宝宝挂点上，不能把宝宝绑到玩家/物体身上；也绝不能绑“玩家正
    -- 踩着的真机关板”（会把板从玩家脚下抢走）。所以只绑可选的“装饰滑板模型”，没配就只跟随。
    self:_attach_decoration_model(agent, facility)
end

---开/关宝宝与“当前骑手 + 滑板本体”之间的碰撞。上板时关、下板时开。
---@param agent BabyAgent|nil
---@param facility BabyFacilityRecord
---@param enable boolean
function FacilityService:_set_player_bound_collision(agent, facility, enable)
    if not (agent and agent.unit and GameAPI.enable_collision_between_units) then
        return
    end
    local targets = { facility.rider, facility.unit }
    for index = 1, #targets do
        local other = targets[index]
        if other then
            pcall(function()
                GameAPI.enable_collision_between_units(agent.unit, other, enable)
            end)
        end
    end
end

---给宝宝挂一个装饰滑板模型（可选）。用 bind_model(模型UnitKey)，不碰玩家正踩的真机关。
---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_attach_decoration_model(agent, facility)
    local def = facility.def
    local model_id = def.vehicle_passenger_model
    if not (model_id and agent.unit and agent.unit.bind_model) then
        return
    end
    local socket_name = def.vehicle_passenger_socket or "socket_origin"
    local socket = Enums.ModelSocket[socket_name] or Enums.ModelSocket.socket_origin
    local offset = self:_to_vector3(def.vehicle_passenger_offset)
    local rotation = self:_to_quaternion(def.vehicle_passenger_rotation)
    local scale = self:_to_vector3(def.vehicle_passenger_scale)
    local ok, bind_id = pcall(function()
        return agent.unit.bind_model(model_id, socket, offset, rotation, scale)
    end)
    if ok and bind_id then
        facility.bind_id = bind_id
        Log.info("deco skateboard bound onto baby", def.id, "baby", agent.index, "bind", bind_id)
    else
        Log.warn("failed to bind deco skateboard", def.id, agent.index, "ok", ok, "bind", bind_id)
    end
end

---@param agent BabyAgent|nil
---@param facility BabyFacilityRecord
function FacilityService:_detach_player_bound_passenger(agent, facility)
    -- 先恢复碰撞（此时 facility.rider 还在，能正确还原与玩家的碰撞）
    self:_set_player_bound_collision(agent, facility, true)
    -- 绑定挂在宝宝身上，解绑也调用宝宝单位的 unbind_model
    if agent and agent.unit and facility.bind_id and agent.unit.unbind_model then
        pcall(function() agent.unit.unbind_model(facility.bind_id) end)
    end
    facility.bind_id = nil
    facility.rider = nil
end

---@param unit Unit|nil
---@param need BabyNeedDef
function FacilityService:_configure_facility_unit(unit, need)
    if not unit then
        return
    end

    -- 载具不挂玩家互动按钮：避免玩家自己按键把车开走，宝宝才是“驾驶员”
    if need.facility_kind == "vehicle" then
        return
    end

    if unit.enable_interact then
        unit.enable_interact()
    end
    if unit.set_interact_button_text_by_index then
        unit.set_interact_button_text_by_index(1, need.action_text)
    end
    if unit.get_interact_id and unit.set_interact_button_text then
        self:_set_interact_button_text(unit, Enums.InteractBtnType.UNIT_START, need.action_text)
        self:_set_interact_button_text(unit, Enums.InteractBtnType.UNIT_STOP, "结束" .. need.action_text)
    end
end

---@param unit Unit
---@param btn_type integer
---@param text string
function FacilityService:_set_interact_button_text(unit, btn_type, text)
    local ok, interact_id = pcall(function()
        return unit.get_interact_id(1, btn_type)
    end)
    if ok and interact_id then
        pcall(function()
            unit.set_interact_button_text(interact_id, text)
        end)
    end
end

-- 一个新的解决办法，抛起骰子后，基本上位于头顶区域，只要往四周走一点距离再跳起就能给到碰撞效果，这个碰撞效果可以实现骰子的翻转。所以我们也不需要手动旋转了。就保留个当前向上投的代码。然后玩家测就自己负责执行操作。ai宝宝测就自动移动一点距离然后跳起。大致效果: 如果跳起来投，不动一直跳，就会像马里奥顶箱子一样，一直不落下， 只要你往周围偏移点距离，骰子就会翻转，偏移如果不大，还能继续顶,我们只要检测骰子落地最后结算就行。这样的话就能分配路径去实现胜负判定效果了

---@param unit Unit|LifeEntity|nil
---@param area Unit|nil
---@return boolean
function FacilityService:_unit_in_area(unit, area)
    if not (unit and area) then
        return false
    end

    if unit.is_in_customtriggerspace then
        local ok, result = pcall(function()
            return unit.is_in_customtriggerspace(area, true)
        end)
        if ok and result then
            return true
        end
    end

    local pos = unit.get_position and unit.get_position()
    if pos and GameAPI.is_point_in_customtriggerspace then
        local ok, result = pcall(function()
            return GameAPI.is_point_in_customtriggerspace(pos, area)
        end)
        return ok and result or false
    end
    return false
end

---@param pos Vector3|nil
---@param need BabyNeedDef
---@param baby_unit Unit|LifeEntity|nil
---@return BabyFacilityRecord|nil
function FacilityService:nearest_match(pos, need, baby_unit)
    local best = nil
    local best_dist = nil
    for index = 1, #self.facilities do
        local facility = self.facilities[index]
        if self.resolver and self.resolver:item_matches_need(facility, need) and not facility.active_agent then
            -- 只有显式配置的近身接触区能触发交互。area 可能是滑板的整个巡游范围，
            -- 不能把它当接触区，否则宝宝在区域任意位置都会被远距离送上设施。
            if facility.contact_area and self:_unit_in_area(baby_unit, facility.contact_area) then
                return facility
            end
            -- 没有专用接触区或区域判定未命中时，只按地面水平距离贴近设施本体。
            -- 设施与宝宝枢轴高度不同，计入 Y 会导致站在正上方容易命中、两侧反而困难。
            if pos and facility.unit and facility.unit.get_position then
                local facility_pos = facility.unit.get_position()
                if facility_pos then
                    local dist = UnitUtil.distance_xz_sq(pos, facility_pos)
                    if not best_dist or dist < best_dist then
                        best = facility
                        best_dist = dist
                    end
                end
            end
        end
    end

    local radius = (best and best.def and best.def.contact_radius) or self.config.baby.contact_radius
    if best_dist and best_dist <= radius * radius then
        return best
    end
    return nil
end

---@param need BabyNeedDef
---@return integer
function FacilityService:_random_duration(need)
    local min_seconds = need.interact_min_seconds or 20
    local max_seconds = need.interact_max_seconds or 60
    if max_seconds < min_seconds then
        max_seconds = min_seconds
    end

    local span = max_seconds - min_seconds + 1
    local raw = LuaAPI.rand and LuaAPI.rand() or 0
    if raw < 0 then
        raw = -raw
    end
    -- 必须返回 Fixed（小数）：该值会作为 call_delay_time 的间隔使用，
    -- 传整数会被当成 0 立即触发，导致秋千互动“坐下即结束”。
    return (min_seconds + (raw % span)) + 0.0
end

---@param agent BabyAgent|nil
---@param facility BabyFacilityRecord|nil
---@return integer|nil
function FacilityService:begin_interaction(agent, facility)
    if not (agent and facility and facility.def) then
        return nil
    end
    if facility.active_agent and facility.active_agent ~= agent then
        return nil
    end

    local duration = self:_random_duration(facility.def)
    facility.active_agent = agent
    if self:_is_vehicle(facility) then
        self:_begin_vehicle_ride(agent, facility, duration)
    else
        self:_seat_agent(agent, facility, duration)
    end
    self:_send_custom_event(facility.def.interact_begin_event, agent, facility, duration)
    Log.info("facility begin", facility.def.id, "baby", agent.index, "duration", duration)
    return duration
end

---@param facility BabyFacilityRecord|nil
---@return boolean
function FacilityService:_is_vehicle(facility)
    return facility ~= nil and facility.def ~= nil and facility.def.facility_kind == "vehicle"
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param duration integer|nil
function FacilityService:_seat_agent(agent, facility, duration)
    local def = facility.def
    if not (facility.unit and agent.unit) then
        return
    end

    local play_time = duration or 0.0

    -- 先强制播放坐姿动画（force_play 可覆盖 AI 的站立/待机动画）
    if def.seat_anim_id and agent.unit.force_play_animation_by_anim_key then
        local anim_ok = pcall(function()
            agent.unit.force_play_animation_by_anim_key(def.seat_anim_id, 0.0, play_time, 1.0, true)
        end)
        Log.info("facility anim force", def.id, agent.index, "anim", def.seat_anim_id, "ok", anim_ok)
    end

    -- 再把活体单位摆到座位点（绑定 API 在本环境不挪动活体单位，改用按帧定位跟随）
    self.seat_token = (self.seat_token or 0) + 1
    facility.seat_token = self.seat_token
    self:_sync_seat(agent, facility, facility.seat_token)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param token integer
function FacilityService:_sync_seat(agent, facility, token)
    if agent.destroyed or facility.active_agent ~= agent or facility.seat_token ~= token then
        return
    end

    local def = facility.def
    if facility.unit and agent.unit and agent.unit.set_position then
        local offset = self:_to_vector3(def.seat_offset)
        local pos = nil
        if offset and facility.unit.get_local_offset_position then
            pos = facility.unit.get_local_offset_position(offset)
        elseif facility.unit.get_position then
            pos = facility.unit.get_position()
        end
        if pos then
            pcall(function() agent.unit.set_position(pos) end)
        end
        local rot = self:_to_quaternion(def.seat_rotation)
        if rot and agent.unit.set_orientation then
            pcall(function() agent.unit.set_orientation(rot) end)
        end
    end

    LuaAPI.call_delay_time(0.0333, function()
        self:_sync_seat(agent, facility, token)
    end)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_unseat_agent(agent, facility)
    local def = facility.def
    if agent.unit and def.seat_anim_id and agent.unit.stop_anim then
        pcall(function()
            agent.unit.stop_anim()
        end)
    end
    if facility.unit and facility.bind_id and facility.unit.unbind_model then
        pcall(function()
            facility.unit.unbind_model(facility.bind_id)
        end)
    end
    facility.bind_id = nil
end

-- ===== 载具型设施：宝宝上车，在触发区内手动巡游 =====
-- SDK 不提供 AI 自动驾驶，只有 start_move_by_direction(方向, 时长)。
-- 这里用“转向循环”：维持一个区内目标点，每隔 segment 秒重新对准方向并续发移动；
-- 到达目标或开出触发区就重新选点（出区时直接拐回区内），从而把活动范围约束在触发区内。

---@param facility BabyFacilityRecord
---@return string
function FacilityService:_vehicle_mode(facility)
    return (facility.def and facility.def.vehicle_drive_mode) or "kinematic"
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param duration Fixed
function FacilityService:_begin_vehicle_ride(agent, facility, duration)
    local vehicle = facility.unit
    if not (vehicle and agent.unit) then
        Log.warn("vehicle ride missing unit", facility.def.id)
        return
    end

    self.seat_token = (self.seat_token or 0) + 1
    facility.seat_token = self.seat_token
    local token = facility.seat_token
    local mode = self:_vehicle_mode(facility)

    if mode == "player_bound" then
        -- 锁住宝宝的 AI/移动，让它在板边等玩家；随后每帧轮询“谁站在板上”。
        if agent.lock_ride_move_state then
            agent:lock_ride_move_state()
        end
        facility.rider = nil
        facility.onboard_streak = 0
        facility.offboard_streak = 0
        self:_player_bound_tick(agent, facility, token)
    elseif mode == "physics" then
        -- 真·载具：宝宝上车，由 VehicleComp 物理驱动（要求该单位是可骑乘载具）
        if agent.unit.try_enter_vehicle then
            pcall(function() agent.unit.try_enter_vehicle(vehicle) end)
        end
        local enter_delay = facility.def.vehicle_enter_delay or 0.4
        LuaAPI.call_delay_time(enter_delay, function()
            self:_drive_vehicle_physics(agent, facility, token, nil)
        end)
    else
        -- 运动学模式：用 set_position 同时挪动载具与宝宝（适配滑板等非可骑乘单位，
        -- 不依赖 try_enter_vehicle / VehicleComp，任意可定位单位都能跑起来）
        facility.drive = nil -- 重置巡游状态，下一拍按新令牌初始化
        -- 先彻底锁住 AI/移动：否则每帧 set_position 位移会让引擎插播待机/移动动画，把骑行动作顶掉
        if agent.lock_ride_move_state then
            agent:lock_ride_move_state()
        end
        self:_start_ride_anim(agent, facility, duration) -- 宝宝骑滑板动作，一次播放持续到下板
        self:_drive_vehicle_kinematic(agent, facility, token)
    end
    Log.info("vehicle ride begin", facility.def.id, "baby", agent.index, "mode", mode, "duration", duration)
end

-- ---------- 运动学驱动（默认）：转向限速 + 速度缓动的 set_position 巡游 ----------
-- 为什么不直接用物理速度/力驱动这块动态刚体：本环境是帧同步地图，set_position + 纯定点
-- 数学计算才能保证锁帧确定性、保证不冲出触发区；apply_force / set_linear_velocity 依赖物理
-- tick 积分，有不同步与被碰撞顶出区的风险。因此这里保留确定性运动学骨架，只把运动曲线做平滑：
--   1) 朝向按 vehicle_turn_speed 限速插值 → 平滑转弯而非瞬切；
--   2) 速度朝目标速度按 vehicle_accel 逼近，靠近目标点/大角度转弯时降速 → 起步加速、到点缓停；
--   3) 前瞻到边界则改朝区内换目标并减速 → 消除边界顿挫。
-- 宝宝硬粘在座位上，整体平顺度由滑板自身的缓动运动带来。

local KINE_DT = 0.0333
local TWO_PI = 6.2831853

---把角度归一化到 [-pi, pi]
---@param a Fixed
---@return Fixed
local function wrap_angle(a)
    a = math.fmod(a, TWO_PI)
    if a > TWO_PI * 0.5 then
        a = a - TWO_PI
    elseif a < -TWO_PI * 0.5 then
        a = a + TWO_PI
    end
    return a
end

---把 current 朝 desired 旋转，单步最多 max_delta（弧度）
---@param current Fixed
---@param desired Fixed
---@param max_delta Fixed
---@return Fixed
local function approach_angle(current, desired, max_delta)
    local diff = wrap_angle(desired - current)
    if diff > max_delta then
        diff = max_delta
    elseif diff < -max_delta then
        diff = -max_delta
    end
    return wrap_angle(current + diff)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param token integer
function FacilityService:_drive_vehicle_kinematic(agent, facility, token)
    if agent.destroyed or facility.active_agent ~= agent or facility.seat_token ~= token then
        return
    end

    local vehicle = facility.unit
    local vpos = vehicle and vehicle.get_position and vehicle.get_position()
    if not (vpos and vehicle.set_position) then
        LuaAPI.call_delay_time(KINE_DT, function()
            self:_drive_vehicle_kinematic(agent, facility, token)
        end)
        return
    end

    local def = facility.def
    local reach = def.vehicle_reach_radius or 2.0
    local max_speed = def.vehicle_speed or 3.0
    local turn_speed = def.vehicle_turn_speed or 3.0
    local accel = def.vehicle_accel or 6.0
    local arrive_radius = def.vehicle_arrive_radius or (reach * 2.0)

    -- 跨帧状态：当前朝向(弧度)、当前速度、目标点
    local drive = facility.drive
    if not drive then
        drive = { heading = 0.0, speed = 0.0, target = self:_random_area_point(facility.area) }
        -- 初始朝向直接对准首个目标，避免开局甩头
        if drive.target then
            drive.heading = math.atan2(drive.target.x - vpos.x, drive.target.z - vpos.z)
        end
        facility.drive = drive
    end

    -- 选/换目标点：没有目标 / 已到达
    if not drive.target then
        drive.target = self:_random_area_point(facility.area)
    end
    local dist = 0.0
    if drive.target then
        local dx = drive.target.x - vpos.x
        local dz = drive.target.z - vpos.z
        dist = math.sqrt(dx * dx + dz * dz)
        if dist <= reach then
            drive.target = self:_random_area_point(facility.area) or drive.target
            dx = drive.target.x - vpos.x
            dz = drive.target.z - vpos.z
            dist = math.sqrt(dx * dx + dz * dz)
        end
    end

    -- 期望朝向 + 转向限速
    local desired = drive.heading
    if drive.target and dist > 0.01 then
        desired = math.atan2(drive.target.x - vpos.x, drive.target.z - vpos.z)
    end
    drive.heading = approach_angle(drive.heading, desired, turn_speed * KINE_DT)

    -- 目标速度：靠近目标点线性减速；朝向偏差大时降速避免甩头
    local target_speed = max_speed
    if dist < arrive_radius then
        target_speed = max_speed * (dist / arrive_radius)
    end
    if math.abs(wrap_angle(desired - drive.heading)) > 0.5 then
        target_speed = target_speed * 0.4
    end
    -- 当前速度朝目标速度按加速度逼近
    if drive.speed < target_speed then
        drive.speed = math.min(target_speed, drive.speed + accel * KINE_DT)
    else
        drive.speed = math.max(target_speed, drive.speed - accel * KINE_DT)
    end

    -- 沿当前朝向前进
    local ux = math.sin(drive.heading)
    local uz = math.cos(drive.heading)
    local step = drive.speed * KINE_DT
    local new_pos = math.Vector3(vpos.x + ux * step, vpos.y, vpos.z + uz * step)

    -- 前瞻边界：下一步会出区则本拍不前进、改朝区内换目标并急减速
    if facility.area and not self:_point_in_area(new_pos, facility.area) then
        drive.target = self:_random_area_point(facility.area) or drive.target
        drive.speed = drive.speed * 0.5
        new_pos = vpos
    end

    local face_rot = math.Quaternion(0.0, drive.heading, 0.0)
    pcall(function() vehicle.set_position(new_pos) end)
    if vehicle.set_orientation then
        pcall(function() vehicle.set_orientation(face_rot) end)
    end

    -- 把宝宝硬粘在载具座位上（平顺度来自滑板自身的缓动运动）
    if agent.unit and agent.unit.set_position then
        local seat = self:_vehicle_seat_pos(vehicle, new_pos, def.vehicle_seat_offset)
        pcall(function() agent.unit.set_position(seat) end)
        if agent.unit.set_orientation then
            pcall(function() agent.unit.set_orientation(face_rot) end)
        end
    end

    LuaAPI.call_delay_time(KINE_DT, function()
        self:_drive_vehicle_kinematic(agent, facility, token)
    end)
end

-- ---------- 骑行动作：宝宝骑滑板姿势，一次强制播放持续整段骑行，下板时停掉 ----------
-- 用 force_play_animation_by_anim_key（强制播放）而非 play_body_anim_by_id：后者（全身动作，
-- 如哭闹23）约1秒后必被 AI 待机动画顶掉，只能每秒重发，而重发会从头混入 → "起身再执行"。
-- force_play 像秋千坐姿那样强制压住 AI 动画，单次调用 + play_time 给满整段时长 + loop=true，
-- 就能稳定保持骑行姿势、不重发、不起身，直到下板由 _stop_ride_anim 停掉。

---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param duration Fixed|nil
function FacilityService:_start_ride_anim(agent, facility, duration)
    local def = facility.def
    local anim_key = def.vehicle_ride_anim_key
    local body_anim = def.vehicle_ride_anim_id
    if not (agent.unit and (anim_key or body_anim)) then
        return
    end
    -- 清掉 AI 移动可能屏蔽的动画，确保骑行动作能播出来
    if agent.unit.clear_banned_anim then
        pcall(function() agent.unit.clear_banned_anim() end)
    end
    local play_time = (duration or 0) + 0.0
    if anim_key and agent.unit.force_play_animation_by_anim_key then
        -- 首选：AnimKey + 强制播放，长期保持动态骑行姿势，不被待机顶掉
        pcall(function() agent.unit.force_play_animation_by_anim_key(anim_key, 0.0, play_time, 1.0, true) end)
    elseif body_anim and agent.unit.play_body_anim_by_id then
        -- 退路：全身动作预设，约 1 秒后会被引擎切回待机，仅占位（需要 AnimKey 才能持久）
        pcall(function() agent.unit.play_body_anim_by_id(body_anim, 0.0, play_time, true) end)
    end
end

---@param agent BabyAgent
function FacilityService:_stop_ride_anim(agent)
    if not agent or not agent.unit then
        return
    end
    -- 与 _start_ride_anim 的 force_play 对应，优先 stop_anim（秋千坐姿同款停法）
    if agent.unit.stop_anim then
        pcall(function() agent.unit.stop_anim() end)
    elseif agent.unit.stop_play_body_anim then
        pcall(function() agent.unit.stop_play_body_anim() end)
    end
end

---@param vehicle Unit
---@param vehicle_pos Vector3
---@param offset_values Fixed[]|nil
---@return Vector3
function FacilityService:_vehicle_seat_pos(vehicle, vehicle_pos, offset_values)
    local offset = self:_to_vector3(offset_values) or math.Vector3(0.0, 0.5, 0.0)
    if vehicle.get_local_offset_position then
        local ok, p = pcall(function() return vehicle.get_local_offset_position(offset) end)
        if ok and p then
            return p
        end
    end
    return math.Vector3(vehicle_pos.x + offset.x, vehicle_pos.y + offset.y, vehicle_pos.z + offset.z)
end

-- ---------- 物理驱动（真·载具）：try_enter_vehicle + VehicleComp.start_move_by_direction ----------

---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param token integer
---@param target Vector3|nil
function FacilityService:_drive_vehicle_physics(agent, facility, token, target)
    if agent.destroyed or facility.active_agent ~= agent or facility.seat_token ~= token then
        return
    end

    local vehicle = facility.unit
    local pos = vehicle and vehicle.get_position and vehicle.get_position()
    if not pos then
        return
    end

    local reach = facility.def.vehicle_reach_radius or 2.0
    local segment = facility.def.vehicle_move_segment or 0.3

    local need_new_target = target == nil
    if target and not need_new_target then
        local dx = target.x - pos.x
        local dz = target.z - pos.z
        if dx * dx + dz * dz <= reach * reach then
            need_new_target = true
        end
    end
    if facility.area and not self:_point_in_area(pos, facility.area) then
        need_new_target = true
    end
    if need_new_target then
        target = self:_random_area_point(facility.area) or target
    end

    if target then
        local dir = math.Vector3(target.x - pos.x, 0.0, target.z - pos.z)
        local length = dir:length()
        if length and length > 0.05 then
            local inv = 1.0 / length
            local unit_dir = math.Vector3(dir.x * inv, 0.0, dir.z * inv)
            if vehicle.start_move_by_direction then
                pcall(function() vehicle.start_move_by_direction(unit_dir, segment * 2.0) end)
            elseif vehicle.vehicle_start_move then
                pcall(function() vehicle.vehicle_start_move(unit_dir, segment * 2.0) end)
            end
        end
    end

    LuaAPI.call_delay_time(segment, function()
        self:_drive_vehicle_physics(agent, facility, token, target)
    end)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_end_vehicle_ride(agent, facility)
    facility.seat_token = nil          -- 令牌失效，巡游循环与骑行动作循环下一拍自动停止
    facility.drive = nil               -- 清掉巡游状态，下次上板重新初始化
    self:_stop_ride_anim(agent)        -- 下板：停掉骑行动作
    if agent and agent.unlock_ride_move_state then
        agent:unlock_ride_move_state() -- 解除骑行移动锁，恢复 AI/移动
    end
    local vehicle = facility.unit
    local mode = self:_vehicle_mode(facility)
    if mode == "player_bound" then
        self:_detach_player_bound_passenger(agent, facility)
    elseif mode == "physics" then
        self:_stop_vehicle(vehicle)
        if agent.unit and agent.unit.try_exit_vehicle then
            pcall(function() agent.unit.try_exit_vehicle() end)
        end
        if vehicle and vehicle.reset then
            pcall(function() vehicle.reset() end) -- 载具复位
        end
    end
    Log.info("vehicle ride end", facility.def.id, "baby", agent.index)
end

---@param vehicle Unit|nil
function FacilityService:_stop_vehicle(vehicle)
    if not vehicle then
        return
    end
    if vehicle.stop_move then
        pcall(function() vehicle.stop_move() end)
    elseif vehicle.vehicle_stop_move then
        pcall(function() vehicle.vehicle_stop_move() end)
    end
end

---@param area Unit|nil
---@return Vector3|nil
function FacilityService:_random_area_point(area)
    if not area then
        return nil
    end
    if area.random_point then
        local ok, p = pcall(function() return area.random_point() end)
        if ok and p then
            return p
        end
    end
    if area.get_customtriggerspaces_random_point then
        local ok, p = pcall(function() return area.get_customtriggerspaces_random_point() end)
        if ok and p then
            return p
        end
    end
    return nil
end

---@param pos Vector3|nil
---@param area Unit|nil
---@return boolean
function FacilityService:_point_in_area(pos, area)
    if not (pos and area and GameAPI.is_point_in_customtriggerspace) then
        return false
    end
    local ok, result = pcall(function()
        return GameAPI.is_point_in_customtriggerspace(pos, area)
    end)
    return ok and result or false
end

---@param values Fixed[]|nil
---@return Vector3|nil
function FacilityService:_to_vector3(values)
    if not values then
        return nil
    end
    return math.Vector3(values[1], values[2], values[3])
end

---@param values Fixed[]|nil
---@return Quaternion|nil
function FacilityService:_to_quaternion(values)
    if not values then
        return nil
    end
    return math.Quaternion(
        math.deg_to_rad(values[1]),
        math.deg_to_rad(values[2]),
        math.deg_to_rad(values[3])
    )
end

---@param agent BabyAgent|nil
---@param facility BabyFacilityRecord|nil
function FacilityService:end_interaction(agent, facility)
    if not (agent and facility and facility.def) then
        return
    end
    if facility.active_agent and facility.active_agent ~= agent then
        return
    end

    facility.active_agent = nil
    if self:_is_vehicle(facility) then
        self:_end_vehicle_ride(agent, facility)
    else
        self:_unseat_agent(agent, facility)
    end
    self:_send_custom_event(facility.def.interact_end_event, agent, facility, 0)
    Log.info("facility end", facility.def.id, "baby", agent.index)
end

---@param event_name string|nil
---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param duration integer
function FacilityService:_send_custom_event(event_name, agent, facility, duration)
    if not event_name then
        return
    end

    local payload = {
        baby = agent.unit,
        facility = facility.unit,
        area = facility.area,
        facility_id = facility.def.facility_id,
        need_id = facility.def.id,
        duration_seconds = duration,
    }

    -- 直接发给设施单位本体（专为秋千等组件：坐上触发摆动、离开结束摆动回正）
    if facility.unit and LuaAPI.unit_send_custom_event then
        LuaAPI.unit_send_custom_event(facility.unit, event_name, payload)
    end
    -- 同时广播全局，方便其它系统监听
    if LuaAPI.global_send_custom_event then
        LuaAPI.global_send_custom_event(event_name, payload)
    end
end

---@return nil
function FacilityService:destroy()
    -- 清理仍在运行的设施互动和绑定模型。
    for index = 1, #self.facilities do
        local facility = self.facilities[index]
        if self:_is_vehicle(facility) then
            facility.seat_token = nil
            if self:is_player_bound(facility) then
                local agent = facility.active_agent
                self:_detach_player_bound_passenger(agent, facility)
                if agent and agent.unlock_ride_move_state then
                    agent:unlock_ride_move_state()
                end
            else
                self:_stop_vehicle(facility.unit)
            end
        end
    end
    self.facilities = {}
end

return FacilityService
