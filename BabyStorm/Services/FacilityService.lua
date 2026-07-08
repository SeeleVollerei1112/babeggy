local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local MathX = require("Util.MathX")
local Rand = require("Util.Rand")
local Log = require("Util.Log")

local ZERO = math.Vector3(0.0, 0.0, 0.0)

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
    self.crib_service = nil
end

---注入 CribService：crib 型设施的换尿布/擦屁股玩法（UI、取物、长按、歪床）由它驱动。
---@param service CribService
function FacilityService:set_crib_service(service)
    self.crib_service = service
end

---@param kind string
---@return BabyFacilityRecord[]
function FacilityService:get_facilities_by_kind(kind)
    local result = {}
    for index = 1, #self.facilities do
        local facility = self.facilities[index]
        if facility.def and facility.def.facility_kind == kind then
            result[#result + 1] = facility
        end
    end
    return result
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

-- 一个 need 可对应多个可互换的设施单位（如两个秋千座椅）：facility_names 列表里每个名字
-- 各注册一条共享同一 def 的记录，nearest_match 会就近挑空闲的那个。退化到单个 facility_name。
---@param need BabyNeedDef
function FacilityService:_register_facility(need)
    local names = need.facility_names
    local ids = need.facility_unit_ids
    local registered = false
    if names and #names > 0 then
        for index = 1, #names do
            self:_register_facility_unit(need, names[index])
        end
        registered = true
    end
    -- 也支持按“实体ID”注册（投石臂等只有 id 没有稳定名字的组件）。
    if ids and #ids > 0 then
        for index = 1, #ids do
            self:_register_facility_unit(need, nil, GameAPI.get_unit(ids[index]))
        end
        registered = true
    end
    if not registered then
        self:_register_facility_unit(need, need.facility_name)
    end
end

---@param need BabyNeedDef
---@param facility_name string|nil
---@param unit_override Unit|nil 已解析的设施单位（按 id 注册时传入）
---@return BabyFacilityRecord
function FacilityService:_register_facility_unit(need, facility_name, unit_override)
    local unit = unit_override or (facility_name and LuaAPI.query_unit(facility_name)) or nil
    local area = need.area_name and LuaAPI.query_unit(need.area_name) or nil
    local contact_area = need.contact_area_name and LuaAPI.query_unit(need.contact_area_name) or nil

    if not unit then
        Log.warn("missing facility unit", need.id, facility_name)
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
    -- 诊断：打出设施解析到的单位坐标，便于核对“投臂原点离放下点多远”。
    if unit and unit.get_position then
        local p = unit.get_position()
        if p then
            Log.info("facility registered", need.id, facility_name or "(by-id)", "pos", p.x, p.y, p.z)
        end
    end
    return facility
end

---@param facility BabyFacilityRecord|nil
---@return boolean
function FacilityService:is_crib(facility)
    return facility ~= nil and facility.def ~= nil and facility.def.facility_kind == "crib"
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
    local offset = MathX.to_vector3(def.vehicle_follow_offset)
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
    local off = MathX.to_quaternion(facility.def.vehicle_follow_rotation)
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
    local offset = MathX.to_vector3(def.vehicle_passenger_offset)
    local rotation = MathX.to_quaternion(def.vehicle_passenger_rotation)
    local scale = MathX.to_vector3(def.vehicle_passenger_scale)
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

    -- 载具/秋千座椅/婴儿床/投石车不挂玩家互动按钮：交互由“玩家把宝宝抱来放下”触发，避免玩家自己按键。
    -- 婴儿床的取物/换洗/扶正都走 CribService 的场景 UI，同样不需要单位自带的互动按钮。
    if need.facility_kind == "vehicle" or need.facility_kind == "swing_seat"
        or need.facility_kind == "crib" or need.facility_kind == "catapult" then
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
        -- 歪掉的婴儿床（crib_tilted）在扶正前不可再放宝宝：跳过它，就近选另一张可用的床。
        if self.resolver and self.resolver:item_matches_need(facility, need)
            and not facility.active_agent and not facility.crib_tilted then
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
    -- 诊断：有候选但距离超出接触半径 → 打出实际距离与半径，方便判断是加大 radius 还是投臂原点不对。
    if best and best.def then
        Log.info("facility match miss", best.def.id,
            "dist", best_dist and math.sqrt(best_dist) or -1.0, "radius", radius)
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

    -- 必须返回 Fixed（小数）：该值会作为 call_delay_time 的间隔使用，
    -- 传整数会被当成 0 立即触发，导致秋千互动“坐下即结束”。
    return Rand.int(min_seconds, max_seconds) + 0.0
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
    elseif self:_is_swing_seat(facility) then
        self:_begin_swing_seat(agent, facility, duration)
    elseif self:is_catapult(facility) then
        self:_begin_catapult(agent, facility)
    elseif self:is_crib(facility) then
        self:_begin_crib(agent, facility)
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

    -- 先强制播放坐姿动画（force_play 可覆盖 AI 的站立/待机动画）；引擎调用收敛在 AnimationSystem。
    if def.seat_anim_id then
        agent.animation:force_play({ mode = "anim_key", id = def.seat_anim_id, duration = play_time }, "facility")
        Log.info("facility anim force", def.id, agent.index, "anim", def.seat_anim_id)
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
        local offset = MathX.to_vector3(def.seat_offset)
        local pos = nil
        if offset and facility.unit.get_local_offset_position then
            pos = facility.unit.get_local_offset_position(offset)
        elseif facility.unit.get_position then
            pos = facility.unit.get_position()
        end
        if pos then
            pcall(function() agent.unit.set_position(pos) end)
        end
        -- 朝向：seat_follow_orientation=true 时跟随座椅实时朝向（宝宝随秋千一起前后倾，
        -- 可叠加 seat_rotation 偏移）；否则用固定 seat_rotation（原静止秋千行为）。
        -- 朝向来源默认取 facility.unit；若配了 seat_orient_unit_name（如投石车用“投石车投臂0”），
        -- 则以那个单位的朝向为准（位置仍粘 facility.unit）。
        local orient_src = facility.orient_unit or facility.unit
        if agent.unit.set_orientation then
            local rot = nil
            if def.seat_follow_orientation and orient_src and orient_src.get_orientation then
                local ok, srot = pcall(function() return orient_src.get_orientation() end)
                if ok and srot then
                    rot = srot
                    local off = MathX.to_quaternion(def.seat_rotation)
                    if off then
                        local mok, composed = pcall(function() return srot * off end)
                        if mok and composed then
                            rot = composed
                        end
                    end
                end
            else
                rot = MathX.to_quaternion(def.seat_rotation)
            end
            if rot then
                pcall(function() agent.unit.set_orientation(rot) end)
            end
        end
    end

    LuaAPI.call_delay_time(0.0333, function()
        self:_sync_seat(agent, facility, token)
    end)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_unseat_agent(agent, facility)
    agent.animation:release("facility")
    if facility.unit and facility.bind_id and facility.unit.unbind_model then
        pcall(function()
            facility.unit.unbind_model(facility.bind_id)
        end)
    end
    facility.bind_id = nil
end

-- ===== 秋千座椅：把宝宝绑到会摆动的座椅上，并周期性给座椅施力让它越摆越高 =====
-- 与上面 winter_swing（设施组件收到自定义事件后自己摆）不同：这里座椅是物理刚体，
-- 由脚本 apply_force 驱动摆动，宝宝像绑滑板那样每帧硬粘到座位点、跟随座椅朝向一起摆。
-- 复用 _seat_agent/_sync_seat 做绑定与坐姿动画，只额外加：锁移动、关碰撞、施力循环。

---@param facility BabyFacilityRecord|nil
---@return boolean
function FacilityService:_is_swing_seat(facility)
    return facility ~= nil and facility.def ~= nil and facility.def.facility_kind == "swing_seat"
end

---@param facility BabyFacilityRecord|nil
---@return boolean
function FacilityService:is_catapult(facility)
    return facility ~= nil and facility.def ~= nil and facility.def.facility_kind == "catapult"
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param duration Fixed|nil
function FacilityService:_begin_swing_seat(agent, facility, duration)
    if not (facility.unit and agent.unit) then
        Log.warn("swing seat missing unit", facility.def.id)
        return
    end
    -- 锁住宝宝 AI/移动：每帧把它硬粘到摆动座椅上，避免被待机/移动动画顶掉或被 AI 抢走。
    if agent.lock_ride_move_state then
        agent:lock_ride_move_state()
    end
    -- 关掉宝宝与座椅之间的碰撞：宝宝被硬粘到座位点，开着碰撞会互相顶、把座椅推歪。下板恢复。
    self:_set_seat_collision(agent, facility, false)
    -- 坐姿动画 + 每帧跟随（会摆动的）座椅座位点；_seat_agent 内部分配 seat_token 并起 _sync_seat。
    self:_seat_agent(agent, facility, duration)
    -- 周期性给座椅施力，与跟随循环共用同一个 seat_token，令牌失效时一起停。
    self:_drive_swing_force(agent, facility, facility.seat_token)
    Log.info("swing seat begin", facility.def.id, "baby", agent.index, "duration", duration)
end

---开/关宝宝与座椅之间的碰撞。上座时关、离座时开。
---@param agent BabyAgent|nil
---@param facility BabyFacilityRecord
---@param enable boolean
function FacilityService:_set_seat_collision(agent, facility, enable)
    if not (agent and agent.unit and facility.unit and GameAPI.enable_collision_between_units) then
        return
    end
    pcall(function()
        GameAPI.enable_collision_between_units(agent.unit, facility.unit, enable)
    end)
end

---周期性给座椅施力：顺着座椅当前水平运动方向推（“泵”能量），自然越摆越高、不依赖相位。
---接近静止（起摆/端点）时按 swing_push_dir 给一推把秋千起起来；速度超过 swing_max_speed 不再加力。
---@param agent BabyAgent
---@param facility BabyFacilityRecord
---@param token integer|nil
function FacilityService:_drive_swing_force(agent, facility, token)
    if agent.destroyed or facility.active_agent ~= agent or facility.seat_token ~= token then
        return
    end

    local seat = facility.unit
    local def = facility.def
    if seat and seat.apply_force then
        local mag = def.swing_force_magnitude or 12.0
        local max_speed = def.swing_max_speed or 4.0
        local fx, fz = 0.0, 0.0
        local v = seat.get_linear_velocity and seat.get_linear_velocity() or nil
        local horiz = v and math.sqrt(v.x * v.x + v.z * v.z) or 0.0
        if horiz > 0.05 then
            -- 顺着当前运动方向推；已达上限则本拍不加力，避免越摆越飞。
            if horiz < max_speed then
                fx = v.x / horiz * mag
                fz = v.z / horiz * mag
            end
        else
            -- 几乎静止：按配置方向起摆。
            local dir = MathX.to_vector3(def.swing_push_dir) or math.Vector3(1.0, 0.0, 0.0)
            fx, fz = dir.x * mag, dir.z * mag
        end
        if fx ~= 0.0 or fz ~= 0.0 then
            pcall(function() seat.apply_force(math.Vector3(fx, 0.0, fz)) end)
        end
    end

    LuaAPI.call_delay_time(def.swing_force_interval or 0.2, function()
        self:_drive_swing_force(agent, facility, token)
    end)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_end_swing_seat(agent, facility)
    facility.seat_token = nil    -- 令牌失效：跟随循环与施力循环下一拍自动停止
    self:_stop_ride_anim(agent)  -- 停掉坐姿动画（与 _seat_agent 的 force_play 对应）
    if agent and agent.unlock_ride_move_state then
        agent:unlock_ride_move_state()
    end
    self:_set_seat_collision(agent, facility, true) -- 恢复碰撞
    -- 让座椅停摆：清掉速度，避免下一个宝宝来坐时它还在乱晃。
    local seat = facility.unit
    if seat then
        pcall(function()
            if seat.set_linear_velocity then seat.set_linear_velocity(ZERO) end
            if seat.set_angular_velocity then seat.set_angular_velocity(ZERO) end
        end)
    end
    Log.info("swing seat end", facility.def.id, "baby", agent.index)
end

-- ===== 投石车：宝宝“骑”在投臂上等待发射 =====
-- 与秋千座椅同一套骨架（复用 _seat_agent/_sync_seat 每帧硬粘到臂的 socket_origin + 跟随朝向），但：
--   1) 不给臂施力——投臂摆动由编辑器运动器负责（表现）；
--   2) 不按时长自动结束——等玩家点发射按钮，由 CatapultLaunchService 停跟随、抛物线发射后再结算。
-- 宝宝是脚本按帧定位的运动学单位、且与臂关闭了碰撞，运动器的物理发射碰不到它。

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_begin_catapult(agent, facility)
    if not (facility.unit and agent.unit) then
        Log.warn("catapult missing unit", facility.def.id)
        return
    end
    -- 朝向来源：让宝宝坐姿朝向与“投石车投臂0”一致（位置仍粘 facility.unit / 投臂本体）。
    if facility.def.seat_orient_unit_name and not facility.orient_unit then
        facility.orient_unit = LuaAPI.query_unit(facility.def.seat_orient_unit_name)
        if not facility.orient_unit then
            Log.warn("catapult orient unit not found", facility.def.seat_orient_unit_name)
        end
    end
    -- 锁住宝宝 AI/移动：每帧把它硬粘到投臂上，避免被待机/移动动画顶掉或被 AI 抢走。
    if agent.lock_ride_move_state then
        agent:lock_ride_move_state()
    end
    -- 关掉宝宝与投臂之间的碰撞：宝宝被硬粘到坐点，开着碰撞会互相顶、也会被运动器摆臂撞飞。
    self:_set_seat_collision(agent, facility, false)
    -- 坐姿动画 + 每帧跟随投臂坐点（_seat_agent 内部分配 seat_token 并起 _sync_seat）。
    self:_seat_agent(agent, facility, nil)
    Log.info("catapult seat begin", facility.def.id, "baby", agent.index)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_end_catapult(agent, facility)
    facility.seat_token = nil    -- 令牌失效：跟随循环下一拍自动停止（发射时已提前停过，这里幂等）
    self:_stop_ride_anim(agent)  -- 停坐姿动画
    if agent and agent.unlock_ride_move_state then
        agent:unlock_ride_move_state()
    end
    self:_set_seat_collision(agent, facility, true) -- 恢复碰撞
    Log.info("catapult seat end", facility.def.id, "baby", agent.index)
end

-- ===== 婴儿床：宝宝躺床（绑床 + 躺姿动作），换尿布/擦屁股玩法交给 CribService =====
-- 与秋千座椅同一套“硬粘 + 强制播放动作”骨架（复用 _seat_agent/_sync_seat），只是：
--   1) 播躺姿动作（seat_anim_id=49），朝向与床一致；
--   2) 锁移动、关碰撞，避免宝宝被待机顶掉或把床顶歪；
--   3) 起完后把会话交给 CribService（弹柜UI取物 → 床边长按换洗 → 完成/歪床）。
-- 结束（完成或被歪床打断）由 CribService 通过 agent 回调 end_interaction，走到 _end_crib 收尾。

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_begin_crib(agent, facility)
    if not (facility.unit and agent.unit) then
        Log.warn("crib missing unit", facility.def.id)
        return
    end
    -- 锁住宝宝 AI/移动：每帧把它硬粘到床上，避免被待机/移动动画顶掉或被 AI 抢走。
    if agent.lock_ride_move_state then
        agent:lock_ride_move_state()
    end
    -- 关掉宝宝与床之间的碰撞：宝宝被硬粘到躺位，开着碰撞会互相顶、把床推歪。离床恢复。
    self:_set_seat_collision(agent, facility, false)
    -- 躺姿动作 + 每帧跟随床躺位（复用 _seat_agent：分配 seat_token 并起 _sync_seat）。
    self:_seat_agent(agent, facility, nil)
    -- 把换尿布/擦屁股玩法交给 CribService 驱动（子需求随机、取物、长按、歪床、扶正）。
    if self.crib_service then
        self.crib_service:begin_session(agent, facility)
    else
        Log.warn("crib service missing", facility.def.id)
    end
    Log.info("crib begin", facility.def.id, "baby", agent.index)
end

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function FacilityService:_end_crib(agent, facility)
    facility.seat_token = nil     -- 令牌失效：躺位跟随循环下一拍自动停止
    self:_stop_ride_anim(agent)   -- 停躺姿动作（与 _seat_agent 的 force_play 对应）
    if agent and agent.unlock_ride_move_state then
        agent:unlock_ride_move_state()
    end
    self:_set_seat_collision(agent, facility, true) -- 恢复碰撞
    if self.crib_service then
        self.crib_service:end_session(agent, facility)
    end
    Log.info("crib end", facility.def.id, "baby", agent.index)
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
    drive.heading = MathX.approach_angle(drive.heading, desired, turn_speed * KINE_DT)

    -- 目标速度：靠近目标点线性减速；朝向偏差大时降速避免甩头
    local target_speed = max_speed
    if dist < arrive_radius then
        target_speed = max_speed * (dist / arrive_radius)
    end
    if math.abs(MathX.wrap_angle(desired - drive.heading)) > 0.5 then
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
    if not (anim_key or body_anim) then
        return
    end
    local play_time = (duration or 0) + 0.0
    local param
    if anim_key then
        -- 首选：AnimKey + 强制播放，长期保持动态骑行姿势，不被待机顶掉
        param = { mode = "anim_key", id = anim_key, duration = play_time }
    else
        -- 退路：全身动作预设，约 1 秒后会被引擎切回待机，仅占位（需要 AnimKey 才能持久）
        param = { mode = "body_id", id = body_anim, duration = play_time }
    end
    agent.animation:force_play(param, "facility")
end

---@param agent BabyAgent
function FacilityService:_stop_ride_anim(agent)
    if not agent then
        return
    end
    agent.animation:release("facility")
end

---@param vehicle Unit
---@param vehicle_pos Vector3
---@param offset_values Fixed[]|nil
---@return Vector3
function FacilityService:_vehicle_seat_pos(vehicle, vehicle_pos, offset_values)
    local offset = MathX.to_vector3(offset_values) or math.Vector3(0.0, 0.5, 0.0)
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
    elseif self:_is_swing_seat(facility) then
        self:_end_swing_seat(agent, facility)
    elseif self:is_catapult(facility) then
        self:_end_catapult(agent, facility)
    elseif self:is_crib(facility) then
        self:_end_crib(agent, facility)
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
        elseif self:_is_swing_seat(facility) and facility.active_agent then
            self:_end_swing_seat(facility.active_agent, facility)
        elseif self:is_crib(facility) and facility.active_agent then
            facility.seat_token = nil
            self:_stop_ride_anim(facility.active_agent)
            if facility.active_agent.unlock_ride_move_state then
                facility.active_agent:unlock_ride_move_state()
            end
        end
    end
    self.facilities = {}
end

return FacilityService
