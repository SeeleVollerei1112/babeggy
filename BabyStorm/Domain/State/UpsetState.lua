local Class = require("BaseClass")
local StateBase = require("BabyStorm.Domain.State.StateBase")

---@class UpsetState: StateBase
local UpsetState = Class("BabyUpsetState", StateBase)

---@param agent BabyAgent
function UpsetState:Ctor(agent)
    UpsetState.super.Ctor(self, agent)
end

---@param context BabyStateContext|nil
function UpsetState:enter(context)
    UpsetState.super.enter(self, context)
    local agent = self.agent
    local wrong_item = context and context.item or nil

    agent:set_busy(true)
    agent:set_status("不是想要的")
    agent.view_model:add_stress(1)
    if wrong_item then
        agent.services.task:emit_wrong_item(agent, wrong_item)
    end
    agent.services.score:penalize_wrong(agent.last_role)

    LuaAPI.call_delay_time(1.0, function()
        if agent:is_in_state(agent.enum.BabyState.Upset) then
            agent:enter_idle()
        end
    end)
end

return UpsetState
