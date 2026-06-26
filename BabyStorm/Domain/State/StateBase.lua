local Class = require("BaseClass")
local Enum = require("BabyStorm.Config.BabyStormEnum")
local Log = require("Util.Log")

---@class StateBase
---@field agent BabyAgent
---@field _state_id integer
---@field _active boolean
local StateBase = Class("BabyStateBase")

---@param agent BabyAgent
function StateBase:Ctor(agent)
    self.agent = agent
    self._state_id = 0
    self._active = false
end

---@param state_id integer
function StateBase:init(state_id)
    self._state_id = state_id
end

---@param context BabyStateContext|nil
function StateBase:enter(context)
    self._active = true
    Log.info("baby", self.agent.index, "enter", Enum.get_state_name(self._state_id))
end

---@param context BabyStateContext|nil
function StateBase:exit(context)
    self._active = false
end

---@return integer
function StateBase:get_state_id()
    return self._state_id
end

---@return boolean
function StateBase:is_active()
    return self._active
end

return StateBase
