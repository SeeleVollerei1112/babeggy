local Class = require("BaseClass")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

-- 好斗宝宝蛋「拉架」玩法的驱动服务（与 RpsService / BallRallyService 同构：
-- 一个会话单例，由 manager 每 tick 调 update(dt)）。
--
-- 流程：
--   1. _scan：找一个持「好斗(fight)」需求、处于 Idle 的宝宝，且附近有玩家 → 开局。
--   2. 开局：宝宝进入 Fighting 状态打闹，取消耐心倒计时（会话自带兜底超时）。
--   3. _update_session：把就近玩家定身（BUFF_FORBID_MOVE，对应用户说的「禁止走动 buff」），
--      读其轮盘方向（Character.get_joystick_direction），对准当前目标方向即累计进度；
--      每对准 segment_seconds 算完成一段，按顺序换下一个目标方向；完成 required_segments 段
--      即把宝宝拉开 → finish_fight（满足）。玩家离开则解除定身、进度清零。
--   4. 兜底超时：放弃本需求，换下一个，避免卡死。
--
-- 只有本服务真正读轮盘/加禁动 buff；宝宝侧的移动/动画仍由其子系统按 Fighting 意图 reconcile。
local FightService = Class("FightService")

local State = {
    Idle = "idle",
    Engaged = "engaged",
}

---@param config BabyStormConfig
---@param triggers TriggerRegistry
function FightService:Ctor(config, triggers)
    self.cfg = config.fight
    self.triggers = triggers
    self.agents = nil
    self.state = State.Idle
    self.agent = nil
    self.engaged_unit = nil      -- 当前被定身的拉架玩家单位
    self.engaged_role = nil
    self.target_index = 1        -- 当前要求的目标方向序号
    self.seg_progress = 0.0      -- 当前段对准目标方向已累计时长
    self.segments_done = 0       -- 已完成段数
    self.non_aligned = 0.0       -- 已上场玩家连续没对准的时长（达 release_grace 解除定身）
    self.elapsed = 0.0           -- 会话总时长（兜底超时）
end

---@param agents BabyAgent[]
---@return boolean
function FightService:start(agents)
    if not (self.cfg and self.cfg.enabled) then
        return false
    end
    self.agents = agents
    Log.info("fight ready")
    return true
end

---@param dt Fixed
function FightService:update(dt)
    if not (self.cfg and self.cfg.enabled) then
        return
    end
    if self.state == State.Idle then
        self:_scan()
    else
        self:_update_session(dt)
    end
end

-- 找一个好斗宝宝 + 附近玩家开局。
function FightService:_scan()
    if not self.agents then
        return
    end
    for index = 1, #self.agents do
        local agent = self.agents[index]
        if agent and not agent.destroyed
            and agent:is_in_state(agent.enum.BabyState.Idle)
            and agent.services.resolver:is_fight_need(agent.current_need)
        then
            local unit = self:_nearest_player(agent)
            if unit then
                self:_begin_session(agent)
                return
            end
        end
    end
end

---@param agent BabyAgent
function FightService:_begin_session(agent)
    self.agent = agent
    self.engaged_unit = nil
    self.engaged_role = nil
    self.target_index = 1
    self.seg_progress = 0.0
    self.segments_done = 0
    self.elapsed = 0.0

    -- 取消耐心倒计时：拉架是长互动，避免被需求超时打断（与秋千/猜拳一致）。
    agent:cancel_need_countdown()
    agent:enter_state(agent.enum.BabyState.Fighting, {
        status_text = self:_prompt_text(),
    }, true)
    self.state = State.Engaged
    Log.info("fight begin", agent.index)
end

---@param dt Fixed
function FightService:_update_session(dt)
    local agent = self.agent
    if not (agent and not agent.destroyed and agent:is_in_state(agent.enum.BabyState.Fighting)) then
        self:_abort()
        return
    end

    self.elapsed = self.elapsed + dt
    if self.elapsed >= self.cfg.session_timeout then
        Log.info("fight timeout", agent.index)
        self:_giveup()
        return
    end

    -- 尚无拉架者：等某个就近玩家「主动把轮盘拨向目标方向」才上场并定身。
    -- 不在仅靠近时就定身，避免路过的玩家被无辜困住。
    if not self.engaged_unit then
        local unit, role = self:_nearest_player(agent)
        if unit and self:_joystick_aligned(unit) then
            self.engaged_unit = unit
            self.engaged_role = role
            self.seg_progress = 0.0
            self.non_aligned = 0.0
            self:_set_rooted(unit, true)
        else
            agent:set_status(self:_prompt_text())
            return
        end
    end

    -- 已有拉架者（被定身）：对准目标方向累计进度；长时间不拨则放他走。
    if self:_joystick_aligned(self.engaged_unit) then
        self.non_aligned = 0.0
        self.seg_progress = self.seg_progress + dt
        if self.seg_progress >= self.cfg.segment_seconds then
            self.seg_progress = 0.0
            self.segments_done = self.segments_done + 1
            if self.segments_done >= self.cfg.required_segments then
                self:_finish()
                return
            end
            self.target_index = self.target_index % #self.cfg.directions + 1
        end
    else
        self.non_aligned = self.non_aligned + dt
        self.seg_progress = self.seg_progress - dt
        if self.seg_progress < 0.0 then
            self.seg_progress = 0.0
        end
        if self.non_aligned >= self.cfg.release_grace then
            -- 放弃拉架：解除定身放人走，等下一个拉架者（进度保留已完成段）。
            self:_set_rooted(self.engaged_unit, false)
            self.engaged_unit = nil
            self.engaged_role = nil
        end
    end
    agent:set_status(self:_prompt_text())
end

-- 取当前目标方向（单位向量）与玩家轮盘方向比对，水平 dot >= 阈值算对准。
---@param unit Unit|LifeEntity|nil
---@return boolean
function FightService:_joystick_aligned(unit)
    if not (unit and unit.get_joystick_direction) then
        return false
    end
    local ok, dir = pcall(function() return unit.get_joystick_direction() end)
    if not (ok and dir) then
        return false
    end
    local jx, jz = dir.x or 0.0, dir.z or 0.0
    local jlen = math.sqrt(jx * jx + jz * jz)
    if jlen < self.cfg.joystick_deadzone then
        return false
    end
    local target = self.cfg.directions[self.target_index]
    local tx, tz = target.dir[1], target.dir[3]
    local tlen = math.sqrt(tx * tx + tz * tz)
    if tlen < 0.0001 then
        return false
    end
    local dot = (jx * tx + jz * tz) / (jlen * tlen)
    return dot >= self.cfg.target_tolerance
end

-- 找离宝宝最近、且在 engage_radius 内的玩家控制单位。
---@param agent BabyAgent
---@return Unit|LifeEntity|nil, Role|nil
function FightService:_nearest_player(agent)
    local baby_pos = agent.unit and agent.unit.get_position and agent.unit.get_position() or nil
    if not baby_pos then
        return nil, nil
    end
    local radius_sq = self.cfg.engage_radius * self.cfg.engage_radius
    local roles = GameAPI and GameAPI.get_all_valid_roles and GameAPI.get_all_valid_roles() or {}
    local best_unit, best_role, best_sq = nil, nil, nil
    for index = 1, #roles do
        local role = roles[index]
        local unit = role and role.get_ctrl_unit and role.get_ctrl_unit() or nil
        local pos = unit and unit.get_position and unit.get_position() or nil
        if pos then
            local dist_sq = UnitUtil.distance_xz_sq(baby_pos, pos)
            if dist_sq <= radius_sq and (not best_sq or dist_sq < best_sq) then
                best_unit, best_role, best_sq = unit, role, dist_sq
            end
        end
    end
    return best_unit, best_role
end

-- 定身/解除：加减禁止走动 buff（计数型，按需幂等；这里每个会话只对单一玩家加减一次）。
---@param unit Unit|LifeEntity|nil
---@param rooted boolean
function FightService:_set_rooted(unit, rooted)
    if not unit then
        return
    end
    if rooted then
        if unit.add_state then
            pcall(function() unit.add_state(Enums.BuffState.BUFF_FORBID_MOVE) end)
        end
    else
        if unit.remove_state then
            pcall(function() unit.remove_state(Enums.BuffState.BUFF_FORBID_MOVE) end)
        end
    end
end

---@return string
function FightService:_prompt_text()
    if not self.engaged_unit then
        return "好斗宝宝在打闹！靠近拉架！"
    end
    local dir = self.cfg.directions[self.target_index]
    local label = dir and dir.label or "?"
    return "拉架！把轮盘转向[" .. label .. "] ("
        .. tostring(self.segments_done) .. "/" .. tostring(self.cfg.required_segments) .. ")"
end

function FightService:_finish()
    local agent = self.agent
    local role = self.engaged_role
    self:_set_rooted(self.engaged_unit, false)
    self:_clear()
    if agent and not agent.destroyed then
        agent:finish_fight(role)
    end
    Log.info("fight finished")
end

-- 超时放弃：解除定身、换下一个需求、回 Idle，避免卡死在没人拉架的好斗需求上。
function FightService:_giveup()
    local agent = self.agent
    self:_set_rooted(self.engaged_unit, false)
    self:_clear()
    if agent and not agent.destroyed then
        agent:choose_next_need()
        agent:enter_idle()
    end
end

-- 异常中止（宝宝被销毁/离开 Fighting）：仅解除定身并复位会话。
function FightService:_abort()
    self:_set_rooted(self.engaged_unit, false)
    self:_clear()
end

function FightService:_clear()
    self.state = State.Idle
    self.agent = nil
    self.engaged_unit = nil
    self.engaged_role = nil
    self.target_index = 1
    self.seg_progress = 0.0
    self.segments_done = 0
    self.non_aligned = 0.0
    self.elapsed = 0.0
end

function FightService:destroy()
    self:_set_rooted(self.engaged_unit, false)
    self:_clear()
    self.agents = nil
    Log.info("fight destroyed")
end

return FightService
