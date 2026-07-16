local Class = require("BaseClass")
local Config = require("BabyStorm.Config.BabyStormConfig")
local ArenaService = require("BabyStorm.Services.ArenaService")
local NeedService = require("BabyStorm.Services.NeedService")
local NeedResolver = require("BabyStorm.Services.NeedResolver")
local ItemService = require("BabyStorm.Services.ItemService")
local FacilityRegistry = require("BabyStorm.Services.FacilityRegistry")
local ScoreService = require("BabyStorm.Services.ScoreService")
local TaskEventService = require("BabyStorm.Services.TaskEventService")
local DifficultyService = require("BabyStorm.Services.DifficultyService")
local RoundService = require("BabyStorm.Services.RoundService")
local BallRallyCoordinator = require("BabyStorm.Coordinators.BallRallyCoordinator")
local RpsCoordinator = require("BabyStorm.Coordinators.RpsCoordinator")
local CribCoordinator = require("BabyStorm.Coordinators.CribCoordinator")
local CribCareView = require("BabyStorm.View.CribCareView")
local DirtyDiaperProp = require("BabyStorm.Services.Props.DirtyDiaperProp")
local CatapultLaunchService = require("BabyStorm.Services.CatapultLaunchService")
local BabySceneView = require("BabyStorm.View.BabySceneView")
local BabyAgent = require("BabyStorm.Domain.BabyAgent")
local GameViewModel = require("BabyStorm.Domain.GameViewModel")
local TriggerRegistry = require("App.TriggerRegistry")
local Timer = require("BabyStorm.Core.Timer")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

---@class BabyServices
---@field arena ArenaService
---@field resolver NeedResolver
---@field need NeedService
---@field item ItemService
---@field facility FacilityRegistry
---@field score ScoreService
---@field task TaskEventService
---@field difficulty DifficultyService
---@field round RoundService
---@field ball_rally BallRallyCoordinator
---@field rps RpsCoordinator
---@field crib CribCoordinator
---@field crib_view CribCareView
---@field dirty_diaper DirtyDiaperProp
---@field catapult CatapultLaunchService
---@field view BabySceneView
---@field triggers TriggerRegistry
---@field game_view_model GameViewModel

---@class BabyStormDebugSnapshot
---@field started boolean
---@field baby_count integer
---@field chaos_level integer
---@field satisfied_count integer
---@field elapsed_seconds integer
---@field remaining_seconds integer
---@field player_count integer

---@class BabyAgentManager
---@field application GameApplication|nil
---@field config BabyStormConfig
---@field agents BabyAgent[]
---@field services BabyServices|nil
---@field started boolean
---@field triggers TriggerRegistry
local BabyAgentManager = Class("BabyAgentManager")

-- 统一 tick 间隔（秒）：约 3 个逻辑帧。行为状态 phase（Idle 扫描、Cry 倒计时、
-- PlayRps/BallRally 传感、CribInteraction 歪床倒计时等）仍需要 dt，这一个 tick
-- 给所有宝宝提供统一节拍；移动/动画的对齐已改为 invalidate() 时立即执行，不再靠本 tick 兜底。
local TICK_DT = 0.1

---@param application GameApplication|nil
function BabyAgentManager:Ctor(application)
    self.application = application
    self.config = Config
    self.agents = {}
    self.services = nil
    self.started = false
    self.triggers = TriggerRegistry.New()
end

---@return boolean
function BabyAgentManager:start()
    if self.started then
        return true
    end
    self.started = true

    local sessions = self.application and self.application.sessions or nil
    if sessions then
        sessions:sync_all()
    end

    local arena = ArenaService.New(self.config)
    if not arena:init() then
        self.started = false
        return false
    end

    local resolver = NeedResolver.New(self.config)
    local need = NeedService.New(self.config)
    local item = ItemService.New(self.config, arena)
    item:set_trigger_registry(self.triggers)
    item:set_need_resolver(resolver)
    local facility = FacilityRegistry.New(self.config)
    facility:set_need_resolver(resolver)
    -- 宝宝也是 character，注入“是否宝宝”判定，让滑板上板检测能把宝宝从玩家里排除
    facility:set_baby_unit_filter(function(unit)
        return self:_find_agent_by_unit(unit) ~= nil
    end)
    local game_view_model = GameViewModel.New()
    local score = ScoreService.New(self.config, sessions)
    local task = TaskEventService.New()
    local difficulty = DifficultyService.New(self.config, game_view_model)
    local round = RoundService.New(self.config, self.triggers, sessions, game_view_model)
    local ball_rally = BallRallyCoordinator.New(self.config, self.triggers, sessions)
    local rps = RpsCoordinator.New(self.config, self.triggers)
    local crib = CribCoordinator.New(self.config, self.triggers)
    local crib_view = CribCareView.New(self.config, crib, facility)
    local dirty_diaper = DirtyDiaperProp.New(self.config)
    local catapult = CatapultLaunchService.New(self.config, self.triggers)
    -- crib 通过 facility 注册表拿到所有床记录来路由 UI 事件、读/写歪床状态；
    -- 换洗流程整段由 CribInteraction 子状态驱动，本协调器只管 UI 路由、玩家手持道具、
    -- 床级歪倒/扶正——crib_view 只管场景 UI 表现，二者都不持有玩法判定。
    crib:set_facility_service(facility)
    -- catapult 需要 facility：发射时从 catapult 设施的 active_agent 找到骑在投臂上的宝宝。
    catapult:set_facility_service(facility)
    local view = BabySceneView.New(self.config)

    self.services = {
        arena = arena,
        resolver = resolver,
        need = need,
        item = item,
        facility = facility,
        score = score,
        task = task,
        difficulty = difficulty,
        round = round,
        ball_rally = ball_rally,
        rps = rps,
        crib = crib,
        crib_view = crib_view,
        dirty_diaper = dirty_diaper,
        catapult = catapult,
        view = view,
        triggers = self.triggers,
        game_view_model = game_view_model,
    }

    item:on_obtained(function(item_record, data)
        self:_on_item_obtained(item_record, data)
    end)
    item:init()
    facility:init()
    -- 床已在 facility:init() 注册，crib:start()/crib_view:start() 才能拿到每张床的记录。
    crib:start()
    crib_view:start()

    for index = 1, self.config.baby.count do
        self:_create_baby(index)
    end

    ball_rally:start(self.agents)
    rps:start(self.agents)
    catapult:start(self.agents)

    game_view_model:set_active_baby_count(#self.agents)
    round:start()

    self:_start_tick()

    Log.info("manager started")
    return true
end

-- 启动统一 tick 循环：每 TICK_DT 把 dt 派发给每个宝宝的 update。
function BabyAgentManager:_start_tick()
    Timer.every(self, TICK_DT, function()
        self:_tick()
    end)
end

function BabyAgentManager:_tick()
    local agents = self.agents
    for index = 1, #agents do
        local agent = agents[index]
        if agent and not agent.destroyed then
            agent:update(TICK_DT)
        end
    end
end

---@param index integer
---@return BabyAgent|nil
function BabyAgentManager:_create_baby(index)
    local unit = GameAPI.create_life_entity(
        self.config.baby.prefab_id,
        self.services.arena:random_point(),
        math.Quaternion(0, 0, 0),
        1.0,
        nil
    )

    if not unit then
        Log.warn("failed to create baby", index, self.config.baby.prefab_id)
        return nil
    end

    local agent = BabyAgent.New(index, unit, self.services, self.config)
    self.agents[#self.agents + 1] = agent
    agent:init()

    self.triggers:unit(unit, { EVENT.SPEC_LIFEENTITY_LIFTED_BEGIN }, function(event_name, actor, data)
        agent:on_lifted_begin(data)
    end)

    self.triggers:unit(unit, { EVENT.SPEC_LIFEENTITY_LIFTED_END }, function(event_name, actor, data)
        agent:on_lifted_end(data)
    end)

    return agent
end

---@param unit Unit|LifeEntity|nil
---@return BabyAgent|nil
function BabyAgentManager:_find_agent_by_unit(unit)
    if not unit then
        return nil
    end

    for index = 1, #self.agents do
        local agent = self.agents[index]
        if UnitUtil.same_unit(agent.unit, unit) then
            return agent
        end
    end
    return nil
end

---@param item BabyItemRecord
---@param data table|nil
function BabyAgentManager:_on_item_obtained(item, data)
    if not (self.started and item and data) then
        return
    end

    local owner = data and data.owner or nil
    local agent = self:_find_agent_by_unit(owner)
    if not agent then
        return
    end
    -- 玩具豁免 reject：捡到玩具一律是「玩一会儿再放下」，是不是当前需求只影响收尾
    -- （与 BabyAgent:_resolve_pickup 同一条规则；两边都会到达，由 begin_toy_play 判重）。
    if item.def.playable then
        agent:begin_toy_play(item)
        return
    end
    if self.services and self.services.resolver and not self.services.resolver:item_matches_need(item, agent.current_need) then
        -- 拿到了不是宝宝想要的东西：先丢掉，再表示不满意
        agent:reject_wrong_item(item)
        return
    end
    agent:complete_item_obtained(item, data and data.count or 1)
end

---@return nil
function BabyAgentManager:destroy()
    if not self.started and not self.services then
        return
    end

    -- 统一 tick 循环挂在 manager 实例名下，一次性清场。
    Timer.cancel_all(self)

    if self.services and self.services.round then
        self.services.round:stop()
    end

    if self.services and self.services.ball_rally then
        self.services.ball_rally:destroy()
    end
    if self.services and self.services.rps then
        self.services.rps:destroy()
    end
    if self.services and self.services.crib_view then
        self.services.crib_view:destroy()
    end
    if self.services and self.services.crib then
        self.services.crib:destroy()
    end
    if self.services and self.services.dirty_diaper then
        self.services.dirty_diaper:destroy()
    end
    if self.services and self.services.catapult then
        self.services.catapult:destroy()
    end

    if self.triggers then
        self.triggers:destroy()
    end

    for index = #self.agents, 1, -1 do
        self.agents[index]:destroy()
    end
    self.agents = {}

    if self.services then
        if self.services.view then
            self.services.view:destroy()
        end
        if self.services.item then
            self.services.item:destroy()
        end
        if self.services.facility then
            self.services.facility:destroy()
        end
    end

    self.services = nil
    self.started = false
    self.triggers = TriggerRegistry.New()
    Log.info("manager destroyed")
end

---@return BabyStormDebugSnapshot
function BabyAgentManager:get_debug_snapshot()
    local snapshot = {
        started = self.started,
        baby_count = #self.agents,
        chaos_level = 0,
        satisfied_count = 0,
        elapsed_seconds = 0,
        remaining_seconds = 0,
        player_count = 0,
    }

    if self.services and self.services.difficulty then
        snapshot.chaos_level = self.services.difficulty:get_chaos_level()
        snapshot.satisfied_count = self.services.difficulty.satisfied_count
    end
    if self.services and self.services.round then
        snapshot.elapsed_seconds = self.services.round.elapsed_seconds
        snapshot.remaining_seconds = self.services.round.remaining_seconds
    end
    if self.application and self.application.sessions then
        snapshot.player_count = self.application.sessions:count()
    end

    return snapshot
end

return BabyAgentManager
