local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")
local Timer = require("BabyStorm.Core.Timer")
local MathX = require("Util.MathX")

-- 设施交互子状态基类。生命周期严格嵌在 InteractingFacilityState 内：
--   宿主状态 enter 时构造并 enter，宿主 exit 时 exit——子状态绝不跨宿主存活。
--
-- 契约（对齐 StateBase 语义）：
--   get_intent()        返回宿主要 set_intent 的意图四字段（每种交互显式声明，不许残留）。
--   enter(duration)     启动驱动/动画/碰撞开关；duration 是本次交互时长（等待型可忽略）。
--   exit()              停掉自己名下的一切（Driver、动画、碰撞、Timer），必须幂等。
--   handle_event(event) 外部事件（经 agent:handle_event → 宿主状态转发）。
--   is_timed()          true = 宿主按 duration 挂 Timer 自动结算；等待型（滑板/床/投石车）返回 false。
--
-- 子状态可以拥有 Driver 与 Timer（owner = self），但**不得**直调移动/动画引擎 API——
-- 位移只经 Core/Drivers，动画只经 AnimationSystem.force_play/release。
---@class InteractionBase
---@field agent BabyAgent
---@field facility BabyFacilityRecord
---@field def BabyNeedDef
local InteractionBase = Class("BabyInteractionBase")

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function InteractionBase:Ctor(agent, facility)
    self.agent = agent
    self.facility = facility
    self.def = facility.def
end

---意图四字段。缺省：停步 + 待机 + 无锁（普通座位语义）。
---@return { move_mode: string, anim_base: string, anim_overlay: string|nil, action_lock: boolean }
function InteractionBase:get_intent()
    return {
        move_mode = Intent.MoveMode.Stop,
        anim_base = Intent.AnimBase.Idle,
        action_lock = false,
    }
end

---@param duration Fixed 本次交互时长（秒）
function InteractionBase:enter(duration)
end

---每 tick 推进（宿主状态 update 转发；需要暂停/续跑语义的倒计时用它，纯延时用 Timer）。
---@param dt Fixed
function InteractionBase:update(dt)
end

-- 基类兜底：取消子状态名下全部定时器。子类 override 后必须调 super.exit。
function InteractionBase:exit()
    Timer.cancel_all(self)
end

---@param event table
function InteractionBase:handle_event(event)
end

---@return boolean
function InteractionBase:is_timed()
    return true
end

-- ============================================================
-- 共享工具：坐姿跟随 / 坐姿动画 / 碰撞开关
-- ============================================================

---按 def 的 seat_* 配置构造 FollowDriver spec（宝宝硬粘到设施座位点）。
---历史 _sync_seat 用原生 set_position 按帧硬粘，故 smooth=false。
---朝向：seat_follow_orientation=true 时跟随朝向源实时朝向（可叠加 seat_rotation 偏移；
---朝向源默认设施本体，投石车经 facility.orient_unit 换成投臂）；否则用固定 seat_rotation。
---@return FollowSpec
function InteractionBase:_seat_follow_spec()
    local def = self.def
    local spec = {
        unit = self.agent.unit,
        target = self.facility.unit,
        offset = MathX.to_vector3(def.seat_offset),
        smooth = false,
    }
    if def.seat_follow_orientation then
        spec.orient = "target"
        spec.orient_target = self.facility.orient_unit
        spec.orient_offset = MathX.to_quaternion(def.seat_rotation)
    else
        spec.orient = "fixed"
        spec.fixed_rotation = MathX.to_quaternion(def.seat_rotation)
    end
    return spec
end

---强制播放坐姿动画（force_play 可覆盖 AI 的站立/待机动画）。
---一次播够整段时长（duration nil = 0.0，即由 release 显式停止的既有用法）。
---@param duration Fixed|nil
function InteractionBase:_play_seat_anim(duration)
    if self.def.seat_anim_id then
        self.agent.animation:force_play({
            mode = "anim_key",
            id = self.def.seat_anim_id,
            duration = duration or 0.0,
        }, "facility")
    end
end

function InteractionBase:_release_anim()
    self.agent.animation:release("facility")
end

---开/关宝宝与某单位之间的碰撞。上座关（宝宝被硬粘到座位点，开着碰撞会互相顶、
---把设施推歪、还会让宝宝因受力做出踉跄动作），离座恢复。
---@param other Unit|LifeEntity|nil
---@param enable boolean
function InteractionBase:_set_collision_with(other, enable)
    if self.agent.unit and other then
        GameAPI.enable_collision_between_units(self.agent.unit, other, enable)
    end
end

return InteractionBase
