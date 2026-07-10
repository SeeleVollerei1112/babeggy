local Class = require("BaseClass")
local Enum = require("BabyStorm.Config.BabyStormEnum")
local DiceProp = require("BabyStorm.Services.Props.DiceProp")
local Timer = require("BabyStorm.Core.Timer")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

-- 猜拳配对薄协调器：只负责“找一个想玩猜拳的宝宝 + 一颗没人举着的骰子”，
-- 配对成功后把流程整个交给 PlayRpsState（配对→抛骰→顶撞→判分全在状态内）。
-- 骰子引擎事件经 DiceProp 转发到当前会话宝宝的 handle_event，本协调器不持有会话细节。
---@class RpsCoordinator
---@field cfg BabyRpsConfig
---@field prop DiceProp
---@field agents BabyAgent[]|nil
---@field _session_agent BabyAgent|nil
local RpsCoordinator = Class("RpsCoordinator")

---@param config BabyStormConfig
---@param triggers TriggerRegistry
function RpsCoordinator:Ctor(config, triggers)
    self.cfg = config.rps
    self.prop = DiceProp.New(config, triggers)
    self.agents = nil
    self._session_agent = nil
end

---@param agents BabyAgent[]
---@return boolean
function RpsCoordinator:start(agents)
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
    Timer.every(self, 0.5, function() self:_scan() end)
    return true
end

-- 找就近空闲、想玩猜拳的宝宝，配对一颗没人举着的骰子并让它举起来。
function RpsCoordinator:_scan()
    if self._session_agent then
        if self._session_agent:is_in_state(Enum.BabyState.PlayRps) then
            return -- 上一局仍在进行
        end
        self._session_agent = nil
    end
    if not self.agents then
        return
    end

    local radius_sq = self.cfg.trigger_radius * self.cfg.trigger_radius
    for index = 1, #self.agents do
        local agent = self.agents[index]
        if agent and not agent.destroyed
            and agent:is_in_state(Enum.BabyState.Idle)
            and agent.services.resolver:is_rps_need(agent.current_need)
        then
            local pos = agent.unit.get_position()
            local nearest_index, nearest_sq = nil, nil
            for die_index = 1, self.prop:count() do
                if not self.prop:holder(die_index) then
                    local die_pos = self.prop:get(die_index).get_position()
                    local dist_sq = UnitUtil.distance_xz_sq(pos, die_pos)
                    if dist_sq <= radius_sq and (not nearest_sq or dist_sq < nearest_sq) then
                        nearest_index = die_index
                        nearest_sq = dist_sq
                    end
                end
            end
            if nearest_index then
                self._session_agent = agent
                agent:enter_state(Enum.BabyState.PlayRps, { dice = self.prop, baby_die_index = nearest_index }, true)
                Log.info("rps session paired", agent.index, "die", nearest_index)
                return
            end
        end
    end
end

function RpsCoordinator:destroy()
    Timer.cancel_all(self)
    self.prop:destroy()
end

return RpsCoordinator
