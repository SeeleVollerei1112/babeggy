local Class = require("BaseClass")
local Enum = require("BabyStorm.Config.BabyStormEnum")
local BallProp = require("BabyStorm.Services.Props.BallProp")
local Timer = require("BabyStorm.Core.Timer")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

-- 顶球配对薄协调器：只负责“找一个想玩顶球的空闲宝宝 + 一颗自由静止的球”，
-- 配对成功后把流程整个交给 BallRallyState（发球→顶回→回合循环→满回合庆祝全在状态内）。
-- 球引擎事件经 BallProp 转发到当前会话宝宝的 handle_event，本协调器不持有会话细节。
--
-- 遗留（原 `_first_player` 单人问题的最小修法）：本协调器只在 start() 时对当时已存在的
-- 玩家单位注册跳跃事件；中途加入的玩家不会被注册跳跃事件，需要 Phase 6 或后续处理。
---@class BallRallyCoordinator
---@field cfg BabyBallRallyConfig
---@field prop BallProp
---@field sessions PlayerSessionRegistry|nil
---@field agents BabyAgent[]|nil
---@field _session_agent BabyAgent|nil
local BallRallyCoordinator = Class("BallRallyCoordinator")

---@param config BabyStormConfig
---@param triggers TriggerRegistry
---@param sessions PlayerSessionRegistry|nil
function BallRallyCoordinator:Ctor(config, triggers, sessions)
    self.cfg = config.ball_rally
    self.triggers = triggers
    self.sessions = sessions
    self.prop = BallProp.New(config, triggers)
    self.agents = nil
    self._session_agent = nil
end

---@param agents BabyAgent[]
---@return boolean
function BallRallyCoordinator:start(agents)
    if not (self.cfg and self.cfg.enabled) then
        return false
    end
    if not self.prop:init() then
        return false
    end
    self.agents = agents
    self.prop:set_listener(function(event)
        if self._session_agent then
            self._session_agent:handle_event(event)
        end
    end)

    self:_register_existing_players_jump()
    Timer.every(self, 0.5, function() self:_scan() end)
    return true
end

-- 玩家起跳只负责“开窗”；是否顶到由落点盒判定（BallRallyState._try_player_volley）。
-- 只覆盖启动时已存在的玩家，见文件头注释。
function BallRallyCoordinator:_register_existing_players_jump()
    local function register(player_unit)
        if not player_unit then
            return
        end
        self.triggers:unit(player_unit, { EVENT.SPEC_LIFEENTITY_JUMP }, function()
            if self._session_agent then
                self._session_agent:handle_event({ type = "player_jump", unit = player_unit })
            end
        end)
    end

    if self.sessions then
        self.sessions:for_each(function(session)
            register(session.role and session.role.get_ctrl_unit())
        end)
    else
        local roles = GameAPI.get_all_valid_roles() or {}
        for index = 1, #roles do
            register(roles[index] and roles[index].get_ctrl_unit())
        end
    end
end

-- 找就近空闲、想玩顶球的宝宝，配对一颗自由静止的球，随后选离宝宝最近的玩家开局。
function BallRallyCoordinator:_scan()
    if self._session_agent then
        if self._session_agent:is_in_state(Enum.BabyState.BallRally) then
            return -- 上一局仍在进行
        end
        self._session_agent = nil
    end
    if not self.agents then
        return
    end

    local radius_sq = self.cfg.trigger_radius * self.cfg.trigger_radius
    local balls = self.prop:balls()
    for index = 1, #balls do
        local ball = balls[index]
        if self.prop:is_free(ball) then
            local ok, ball_pos = pcall(function() return ball.get_position() end)
            if ok and ball_pos then
                local agent = self:_find_ball_need_agent(ball_pos, radius_sq)
                if agent then
                    local role, player = self:_nearest_player_to(ball_pos)
                    if role and player then
                        self._session_agent = agent
                        agent:enter_state(Enum.BabyState.BallRally, {
                            ball_prop = self.prop,
                            ball = ball,
                            role = role,
                            player = player,
                        }, true)
                        Log.info("ball rally session paired", agent.index)
                    else
                        Log.warn("ball rally session aborted: no player")
                    end
                    return
                end
            end
        end
    end
end

---@param ball_pos Vector3
---@param radius_sq Fixed
---@return BabyAgent|nil
function BallRallyCoordinator:_find_ball_need_agent(ball_pos, radius_sq)
    local agents = self.agents
    for index = 1, #agents do
        local agent = agents[index]
        if agent and not agent.destroyed
            and agent:is_in_state(Enum.BabyState.Idle)
            and agent.services.resolver:is_ball_rally_need(agent.current_need)
        then
            local pos = agent.unit.get_position()
            if pos and UnitUtil.distance_xz_sq(pos, ball_pos) <= radius_sq then
                return agent
            end
        end
    end
    return nil
end

-- 选离球（发球宝宝）最近的玩家作为本局回合搭档，替代原实现“只认第一个玩家”。
---@param pos Vector3
---@return Role|nil, LifeEntity|Character|nil
function BallRallyCoordinator:_nearest_player_to(pos)
    local best_role, best_player, best_sq = nil, nil, nil
    local function consider(role)
        local player = role and role.get_ctrl_unit()
        if not player then
            return
        end
        local ok, player_pos = pcall(function() return player.get_position() end)
        if not (ok and player_pos) then
            return
        end
        local dist_sq = UnitUtil.distance_xz_sq(pos, player_pos)
        if not best_sq or dist_sq < best_sq then
            best_sq = dist_sq
            best_role = role
            best_player = player
        end
    end

    if self.sessions then
        self.sessions:for_each(function(session)
            consider(session.role)
        end)
    else
        local roles = GameAPI.get_all_valid_roles() or {}
        for index = 1, #roles do
            consider(roles[index])
        end
    end
    return best_role, best_player
end

function BallRallyCoordinator:destroy()
    Timer.cancel_all(self)
    self.prop:destroy()
end

return BallRallyCoordinator
