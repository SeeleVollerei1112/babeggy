local Class = require("BaseClass")
local Enum = require("BabyStorm.Config.BabyStormEnum")
local Log = require("Util.Log")

local StateBase = Class("BabyStateBase")

function StateBase:Ctor(agent)
    self.agent = agent
    self._state_id = 0
    self._active = false
end

function StateBase:init(state_id)
    self._state_id = state_id
end

function StateBase:enter(context)
    self._active = true
    Log.info("baby", self.agent.index, "enter", Enum.get_state_name(self._state_id))
end

function StateBase:exit(context)
    self._active = false
end

function StateBase:get_state_id()
    return self._state_id
end

function StateBase:is_active()
    return self._active
end

return StateBase
