local Class = require("BaseClass")
local Intent = require("BabyStorm.Domain.BabyIntent")
local InteractionBase = require("BabyStorm.Domain.Interaction.InteractionBase")
local FollowDriver = require("BabyStorm.Core.Drivers.FollowDriver")
local Timer = require("BabyStorm.Core.Timer")
local Rand = require("Util.Rand")
local Log = require("Util.Log")

-- 婴儿床：宝宝上床——坐姿 AnimKey 21013 + 每帧硬粘到床位 + 锁移动 + 关碰撞，
-- 换尿布/擦屁股玩法（子需求随机、取物持有、长按进度、歪床/扶正）全部在本子状态内完成：
--   * 会话数据写 facility.crib_session（View/Coordinator 只读的黑板，字段见 CribCareSession）。
--   * 长按进度由 CribCoordinator 校验后经 handle_event(crib_press_begin/end) 驱动，
--     推进用 Timer.every(owner=self)；取物提示经 handle_event(crib_item_taken) 续命歪床倒计时。
--   * 歪床倒计时的暂停/续跑语义（按压不倒计时/松手重置/走开不重置/取物重置）见各方法注释。
--   * 结算（完成/歪床）经 agent:complete_facility_interaction / fail_facility_interaction，
--     由宿主 InteractingFacilityState:exit 统一收尾（本状态 exit 只清 crib_session 黑板）。
---@class CribCareSession
---@field agent BabyAgent
---@field sub BabyCribSubType
---@field progress number
---@field interacted boolean
---@field pressing_role RoleID|integer|nil
---@field last_role Role|nil
---
---@class CribInteraction: InteractionBase
---@field _follow FollowDriver
---@field _idle_remaining Fixed
---@field _press_timer TimerHandle|nil
local CribInteraction = Class("BabyCribInteraction", InteractionBase)

---@param agent BabyAgent
---@param facility BabyFacilityRecord
function CribInteraction:Ctor(agent, facility)
    CribInteraction.super.Ctor(self, agent, facility)
    self._follow = FollowDriver.New()
    self._idle_remaining = 0.0
    self._press_timer = nil
end

function CribInteraction:get_intent()
    return {
        move_mode = Intent.MoveMode.Scripted, -- 位移由 FollowDriver 接管
        anim_base = Intent.AnimBase.Idle,     -- 躺姿走 force_play 外部层
        action_lock = true,
    }
end

---@param _duration Fixed
function CribInteraction:enter(_duration)
    self:_set_collision_with(self.facility.unit, false)
    self:_play_seat_anim(nil)
    self._follow:start(self:_seat_follow_spec())

    local cfg = self.agent.config.crib
    local sub = cfg.sub_types[Rand.index(#cfg.sub_types)]
    ---@type CribCareSession
    self.facility.crib_session = {
        agent = self.agent,
        sub = sub,
        progress = 0.0,
        interacted = false,
        pressing_role = nil,
        last_role = nil,
    }
    self.agent:set_status(sub.need_text)
    self._idle_remaining = cfg.idle_tilt_seconds or 25.0
    Log.info("crib begin", self.def.id, "baby", self.agent.index, "sub", sub.key)
end

-- 歪床倒计时：仅当会话存在、未在照顾中、且当前没人按住换洗按钮时才递减
-- （按住不倒计时；松手时在 handle_event 里重置为满值；玩家走开时只清按压，倒计时
-- 从剩余值继续——三条时序都是原实现的刻意设计，不在这里重置）。
---@param dt Fixed
function CribInteraction:update(dt)
    local session = self.facility.crib_session
    if session and not session.interacted and not session.pressing_role then
        self._idle_remaining = self._idle_remaining - dt
        if self._idle_remaining <= 0 then
            self:_on_idle_tilt()
        end
    end
end

---@param event table
function CribInteraction:handle_event(event)
    if event.type == "crib_press_begin" then
        self:_on_press_begin(event.role, event.role_id)
    elseif event.type == "crib_press_end" then
        self:_on_press_end(event.role_id)
    elseif event.type == "crib_item_taken" then
        self:_on_item_taken(event.sub_key)
    end
end

-- Coordinator 已做过“贴近本床 + 手持匹配道具”校验，这里只管会话记账与起长按定时器。
-- 幂等：正在按住时重复的 down（如按钮连点）不重启定时器，避免进度翻倍推进。
---@param role Role|nil
---@param role_id RoleID|integer|nil
function CribInteraction:_on_press_begin(role, role_id)
    local session = self.facility.crib_session
    if not session or session.pressing_role then
        return
    end
    session.pressing_role = role_id
    session.interacted = true
    session.last_role = role
    self._press_timer = Timer.every(self, 0.1, function()
        self:_press_tick()
    end)
end

-- 松手：原 _on_action_up 的重置语义——清进度、清按压、把歪床倒计时重置为满值。
---@param role_id RoleID|integer|nil
function CribInteraction:_on_press_end(role_id)
    local session = self.facility.crib_session
    if not (session and session.pressing_role == role_id) then
        return
    end
    if self._press_timer then
        Timer.cancel(self._press_timer)
        self._press_timer = nil
    end
    session.progress = 0.0
    session.pressing_role = nil
    session.interacted = false
    local cfg = self.agent.config.crib
    self._idle_remaining = cfg.idle_tilt_seconds or 25.0
end

-- 取到对应道具算“开始照顾”：重置歪床倒计时，给玩家走回床边的时间（原 _reset_idle_for_sub）。
---@param sub_key string
function CribInteraction:_on_item_taken(sub_key)
    local session = self.facility.crib_session
    if session and session.sub and session.sub.key == sub_key and not session.interacted then
        local cfg = self.agent.config.crib
        self._idle_remaining = cfg.idle_tilt_seconds or 25.0
    end
end

-- 长按进度推进：先校验按压玩家仍贴近本床，不贴近则中断长按（不重置歪床倒计时，
-- 原语义——玩家可能是暂时被顶开，从剩余值继续给机会）。
function CribInteraction:_press_tick()
    local session = self.facility.crib_session
    if not session or not session.pressing_role then
        Timer.cancel(self._press_timer)
        self._press_timer = nil
        return
    end
    if not self.agent.services.crib:is_role_near_bed(session.pressing_role, self.facility) then
        Timer.cancel(self._press_timer)
        self._press_timer = nil
        session.pressing_role = nil
        session.progress = 0.0
        session.interacted = false
        return
    end

    local cfg = self.agent.config.crib
    local max = cfg.progress_max or 100
    local duration = session.sub.duration_seconds or 5.0
    session.progress = session.progress + max / duration * 0.1
    if session.progress >= max then
        self:_complete_care()
    end
end

-- 原实现是先清 session 再 complete、事件在 complete 之后发——保持原顺序。
-- complete_facility_interaction 会同步切到 Satisfied，触发本对象的 exit()（清 crib_session
-- 黑板/停驱动/停动画/恢复碰撞），随后仍用本函数保留的局部引用把结算事件发出去。
function CribInteraction:_complete_care()
    local session = self.facility.crib_session
    if not session then
        return
    end
    if self._press_timer then
        Timer.cancel(self._press_timer)
        self._press_timer = nil
    end
    self.agent.services.crib:consume_held(session.pressing_role)
    -- 换下来的脏尿布：以换洗玩家为原点抛到身边，落地/滚动沿路留赃物（DirtyDiaperProp 自理）。
    self.agent.services.dirty_diaper:throw_from(session.last_role)
    if session.last_role then
        self.agent.last_role = session.last_role
    end
    self.facility.crib_session = nil
    Log.info("crib care complete", self.def.id, "baby", self.agent.index, "sub", session.sub.key)
    self.agent:complete_facility_interaction(self.facility)
    self.agent.services.crib:emit_action_event(session.sub.complete_event, session.pressing_role, self.facility, session)
end

-- 超时无人照顾：床级歪倒归 Coordinator（床是设施单位，不是宝宝的动画/移动），
-- 宝宝这边走“交互被打断”的既有流程（回 Upset，需求重新计时）。
function CribInteraction:_on_idle_tilt()
    Log.info("crib idle tilt", self.def.id, "baby", self.agent.index)
    self.agent.services.crib:tilt_bed(self.facility)
    self.agent:fail_facility_interaction(self.facility)
end

-- 吸尘器用来清理宝宝的脏尿布, 但宝宝在换洗时会把脏尿布扔到地上，吸尘器可以清理它,
-- 举起吸尘器时算作启动吸尘器,触发事件PICK_UP_TRASHCAN播放吸气特效,PUT_DOWN_TRASHCAN放下吸尘器触发,会触发关闭吸气特效.玩家举起吸尘器会吸附周围的脏尿布,到指定距离后脏尿布这个单位被销毁

function CribInteraction:exit()
    self.facility.crib_session = nil
    self._follow:stop()
    self:_release_anim()
    self:_set_collision_with(self.facility.unit, true)
    Log.info("crib end", self.def.id, "baby", self.agent.index)
    CribInteraction.super.exit(self)
end

---@return boolean
function CribInteraction:is_timed()
    return false
end

return CribInteraction
