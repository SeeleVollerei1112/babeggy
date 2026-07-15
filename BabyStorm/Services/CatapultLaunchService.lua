local Class = require("BaseClass")
local FlightDriver = require("BabyStorm.Core.Drivers.FlightDriver")
local Timer = require("BabyStorm.Core.Timer")
local UINodes = require("Data.UINodes")
local Prefab = require("Data.Prefab")
local MathX = require("Util.MathX")
local Log = require("Util.Log")

-- ============================================================
-- CatapultLaunchService —— 投石车发射（需求驱动）
-- ============================================================
-- 需求链路：宝宝持“想被发射”需求 → 玩家抱宝宝放到投臂上 → CatapultInteraction 子状态
--   把宝宝“骑”到投臂上（FollowDriver 每帧硬粘到臂的 socket_origin + 跟随朝向）。
-- 发射：玩家点 launcher_btn → 本服务找到骑在投臂上的宝宝 → 等 launch_delay（宝宝随臂摆到接近顶点）
--   → 经 agent:handle_event 通知子状态停跟随、用 FlightDriver 把宝宝抛物线甩到 launch_target
--   → 落地调 complete_facility_interaction 结算需求（→ Satisfied → 下一个需求）。
-- 投臂摆动由编辑器运动器负责（表现）；宝宝全程是脚本按帧定位的运动学单位、且与臂关闭碰撞，
-- 运动器的物理发射碰不到它——轨迹完全由脚本决定。
-- 发射参数（落点/延迟/时长/拱高）都在 catapult 需求 def 里，见 BabyStormConfig。
---@class CatapultLaunchService
---@field config BabyStormConfig
---@field triggers TriggerRegistry
---@field facility FacilityRegistry|nil
---@field flight FlightDriver
---@field active table|nil   -- { agent = BabyAgent, facility = BabyFacilityRecord }
---@field canvas_layer any
local CatapultLaunchService = Class("CatapultLaunchService")

--- 承载发射按钮的场景画布锚点：贴在这个投石车组件上，让玩家看得到按钮
local CANVAS_ANCHOR_UNIT_ID = 1419065378

--- 画布相对锚点原点的偏移（米），抬到组件上方
local CANVAS_OFFSET = { 0.0, 2.5, 0.0 }

--- 发射按钮点击时发出的自定义事件名（与你绑到运动器的同一个，点击必触发）
local LAUNCH_CLICK_EVENT = "BABY_CATAPULT_LAUNCH_CLICK"

--- EUI 触摸事件类型：点击（与 CameraModeController 一致）
local TOUCH_CLICK = 1

--- 发射参数兜底（catapult 需求 def 未配时用）
local DEFAULT_LAUNCH_DELAY = 0.25
local DEFAULT_FLIGHT_DURATION = 1.2
local DEFAULT_ARC_PEAK = 4.0
local DEFAULT_FLIGHT_HANG = 0.4
local DEFAULT_ARM_RESET_DELAY = 1.0

---@param config BabyStormConfig
---@param triggers TriggerRegistry
function CatapultLaunchService:Ctor(config, triggers)
    self.config = config
    self.triggers = triggers
    self.facility = nil
    self.flight = FlightDriver.New()
    self.active = nil
    self.canvas_layer = nil
end

---@param facility FacilityRegistry
function CatapultLaunchService:set_facility_service(facility)
    self.facility = facility
end

---@param _agents BabyAgent[]
---@return boolean
function CatapultLaunchService:start(_agents)
    self:_bind_button_canvas()
    self:_capture_home_poses()

    -- 发射信号：主监听按钮发出的自定义事件（与运动器同一个，点击必触发），
    -- 节点点击事件作兜底。两条都进 on_launch_pressed，由 self.active 去重防重复发射。
    self.triggers:global({ EVENT.CUSTOM_EVENT, LAUNCH_CLICK_EVENT }, function()
        self:on_launch_pressed()
    end)
    self.triggers:global({ EVENT.EUI_NODE_TOUCH_EVENT, UINodes.launcher_btn, TOUCH_CLICK }, function()
        self:on_launch_pressed()
    end)

    -- [PROBE 临时] 验证「点击落点区组件能否拿到世界坐标」。核实后整段删除。
    self:_probe_landing_touch(1497478835)

    Log.info("catapult launch service ready")
    return true
end

-- [PROBE 临时] 给落点区组件挂 SPEC_OBSTACLE_TOUCH_BEGIN，把点击世界坐标打进日志。
-- 结论：若日志随点击位置变化 → touch_pos 是真实命中点，方案可行；
--       若不触发 → 组件未开启「可点击」；若坐标恒定 → 只给了组件中心，需改射线方案。
---@param unit_id integer
function CatapultLaunchService:_probe_landing_touch(unit_id)
    local unit = GameAPI.get_unit(unit_id)
    if not unit then
        Log.warn("[PROBE] 落点区组件不存在", unit_id)
        return
    end
    local touchable = unit.is_touchable and unit.is_touchable()
    Log.info("[PROBE] 落点区组件已找到", unit_id, "is_touchable=", tostring(touchable))
    self.triggers:unit(unit, { EVENT.SPEC_OBSTACLE_TOUCH_BEGIN }, function(_, _, data)
        local p = data and data.touch_pos
        if p then
            Log.info("[PROBE] 点击落点区 touch_pos =", p.x, p.y, p.z)
        else
            Log.info("[PROBE] 点击落点区触发了，但 data.touch_pos 为空", tostring(data))
        end
    end)
end

-- 记下每台投石车投臂的原始姿态，供发射后回正。
-- 时机：manager 启动、地图刚加载、运动器一次都还没转过——此刻投臂就是编辑器里摆好的样子。
-- 刻意不写死坐标：以后在编辑器里挪动投石车，这里自动跟着走，不会留下一份会悄悄过期的副本。
function CatapultLaunchService:_capture_home_poses()
    local list = self.facility and self.facility:get_facilities_by_kind("catapult") or {}
    for index = 1, #list do
        local facility = list[index]
        local arm = facility.unit
        if arm then
            facility.catapult_home_pos = arm.get_position()
            facility.catapult_home_rot = arm.get_orientation()
            local p = facility.catapult_home_pos
            Log.info("catapult home pose", facility.def.id, "pos", p and p.x, p and p.y, p and p.z)
        else
            Log.warn("catapult home pose skipped: 投臂单位缺失", facility.def.id)
        end
    end
end

-- 运动器是单程的：发射后投臂停在末态不会自己回去，得脚本把它摆回原位，
-- 否则下一个宝宝坐上来时投臂还翻着，发射姿态全错。
-- 时机：宝宝落地结算后再等 arm_reset_delay，让玩家看清宝宝飞出去，投臂才复位。
---@param facility BabyFacilityRecord
function CatapultLaunchService:_schedule_arm_reset(facility)
    if not facility.catapult_home_rot then
        return
    end
    local delay = facility.def.arm_reset_delay or DEFAULT_ARM_RESET_DELAY
    Timer.once(self, delay, function()
        self:_reset_arm(facility)
    end)
end

---@param facility BabyFacilityRecord
function CatapultLaunchService:_reset_arm(facility)
    local arm = facility.unit
    if not (arm and facility.catapult_home_rot) then
        return
    end
    -- 平滑摆回：观感上是投石车自己在复位，而不是"啪"地闪回。
    arm.set_orientation_smooth(facility.catapult_home_rot)
    if facility.catapult_home_pos then
        arm.set_position_smooth(facility.catapult_home_pos)
    end
    Log.info("catapult arm reset", facility.def.id)
end

-- 把发射按钮画布贴到投石车组件上（照 CribCareView 贴柜子UI 的做法），让玩家看得到按钮。
function CatapultLaunchService:_bind_button_canvas()
    local layer_key = Prefab.scene_eui and Prefab.scene_eui.character_catapult_canvas
    if not layer_key then
        Log.warn("catapult canvas bind skipped: Prefab.scene_eui.character_catapult_canvas 缺失")
        return
    end
    local anchor = GameAPI.get_unit(CANVAS_ANCHOR_UNIT_ID)
    if not (anchor and anchor.create_scene_ui_bind_unit) then
        Log.warn("catapult canvas bind skipped: 锚点单位不存在或不支持场景UI", CANVAS_ANCHOR_UNIT_ID)
        return
    end
    self.canvas_layer = anchor.create_scene_ui_bind_unit(
        layer_key,
        Enums.ModelSocket.socket_origin,
        math.Vector3(CANVAS_OFFSET[1], CANVAS_OFFSET[2], CANVAS_OFFSET[3]),
        -1.0,
        false,
        true
    )
    Log.info("catapult button canvas bound", CANVAS_ANCHOR_UNIT_ID, tostring(self.canvas_layer))
end

function CatapultLaunchService:on_launch_pressed()
    if self.active then
        return -- 正在延迟/飞行中，防连点二次发射
    end
    local agent, facility = self:_find_seated_baby()
    if not (agent and facility) then
        Log.info("catapult launch pressed but no baby on arm")
        return
    end
    self:_begin_launch(agent, facility)
end

-- 找当前骑在投臂上、正等待发射的宝宝（catapult 设施的 active_agent）。
---@return BabyAgent|nil, BabyFacilityRecord|nil
function CatapultLaunchService:_find_seated_baby()
    if not self.facility then
        return nil
    end
    local list = self.facility:get_facilities_by_kind("catapult")
    for index = 1, #list do
        local facility = list[index]
        local agent = facility.active_agent
        if agent and not agent.destroyed then
            return agent, facility
        end
    end
    return nil
end

-- 起手：等 launch_delay（宝宝随臂摆到接近顶点），期间保持骑乘跟随不动它。
---@param agent BabyAgent
---@param facility BabyFacilityRecord
function CatapultLaunchService:_begin_launch(agent, facility)
    self.active = { agent = agent, facility = facility }
    agent:set_status("发射准备！")

    local delay = facility.def.launch_delay or DEFAULT_LAUNCH_DELAY
    Timer.once(self, delay, function()
        if self.active then
            self:_do_launch()
        end
    end)
    Log.info("catapult launch armed", "baby", agent.index)
end

function CatapultLaunchService:_do_launch()
    local agent = self.active and self.active.agent or nil
    local facility = self.active and self.active.facility or nil
    local unit = agent and agent.unit or nil
    if not (agent and not agent.destroyed and unit and unit.get_position and facility) then
        self:_abort("发射目标失效")
        return
    end

    -- 停止骑乘跟随：通知 CatapultInteraction 停掉 FollowDriver，位移交给 FlightDriver 独占。
    -- 仍保留设施占用与动作锁，落地才结算——中途不释放，避免 AI 抢回控制。
    agent:handle_event({ type = "catapult_launch" })

    local from = unit.get_position()
    local to = MathX.to_vector3(facility.def.launch_target) or from
    agent:set_status("发射！")
    self.flight:start({
        unit = unit,
        from = from,
        to = to,
        duration = facility.def.flight_duration or DEFAULT_FLIGHT_DURATION,
        arc_peak = facility.def.flight_arc_peak or DEFAULT_ARC_PEAK,
        ease = "out_in",
        hang = facility.def.flight_hang or DEFAULT_FLIGHT_HANG,
        on_complete = function()
            self:_on_landed()
        end,
    })
    Log.info("catapult launched", "baby", agent.index, "target", to.x, to.y, to.z)
end

function CatapultLaunchService:_on_landed()
    local agent = self.active and self.active.agent or nil
    local facility = self.active and self.active.facility or nil
    if agent and not agent.destroyed and facility then
        -- 结算设施交互：切 Satisfied 时 InteractingFacilityState:exit 统一收尾
        --（解锁、恢复碰撞、停坐姿动画），随后满足需求 → 下一个需求。
        agent:complete_facility_interaction(facility)
        Log.info("catapult landed", "baby", agent.index)
    end
    if facility then
        self:_schedule_arm_reset(facility)
    end
    self.active = nil
end

-- 放弃本次发射（目标中途失效）：让宝宝按“被打断”收尾，解锁归还控制、重排需求。
---@param reason string
function CatapultLaunchService:_abort(reason)
    self.flight:stop()
    local agent = self.active and self.active.agent or nil
    local facility = self.active and self.active.facility or nil
    if agent and not agent.destroyed and facility then
        agent:fail_facility_interaction(facility)
    end
    -- 按钮已经点过，运动器照样把投臂摆了出去——发射作废也要把臂收回来。
    if facility then
        self:_schedule_arm_reset(facility)
    end
    self.active = nil
    Log.info("catapult launch aborted", reason)
end

function CatapultLaunchService:destroy()
    Timer.cancel_all(self)
    self.flight:stop()
    self.active = nil
    self.facility = nil
    self.canvas_layer = nil
    Log.info("catapult launch service destroyed")
end

return CatapultLaunchService
