local Class = require("BaseClass")
local Log = require("Util.Log")

---@alias TriggerCallback fun(event_name:string, actor:any, data:any)
---@alias TriggerEventSpec any[]

---@class TriggerRecord
---@field kind "global"|"unit"
---@field unit Unit|LifeEntity|Equipment|nil
---@field handle any

---@class TriggerRegistry
---@field _handles TriggerRecord[]
local TriggerRegistry = Class("TriggerRegistry")

---@return nil
function TriggerRegistry:Ctor()
    self._handles = {}
end

---@param event_spec TriggerEventSpec
---@param callback TriggerCallback
---@return any
function TriggerRegistry:global(event_spec, callback)
    local handle = LuaAPI.global_register_trigger_event(event_spec, callback)
    if handle then
        self._handles[#self._handles + 1] = {
            kind = "global",
            handle = handle,
        }
    end
    return handle
end

---@param unit Unit|LifeEntity|Equipment|nil
---@param event_spec TriggerEventSpec
---@param callback TriggerCallback
---@return any
function TriggerRegistry:unit(unit, event_spec, callback)
    if not unit then
        return nil
    end

    local handle = LuaAPI.unit_register_trigger_event(unit, event_spec, callback)
    if handle then
        self._handles[#self._handles + 1] = {
            kind = "unit",
            unit = unit,
            handle = handle,
        }
    end
    return handle
end

---@return nil
function TriggerRegistry:destroy()
    for index = #self._handles, 1, -1 do
        local record = self._handles[index]
        local ok = true
        if record.kind == "global" and record.handle and LuaAPI.global_unregister_trigger_event then
            ok = pcall(function()
                LuaAPI.global_unregister_trigger_event(record.handle)
            end)
        elseif record.kind == "unit" and record.unit and record.handle and LuaAPI.unit_unregister_trigger_event then
            ok = pcall(function()
                LuaAPI.unit_unregister_trigger_event(record.unit, record.handle)
            end)
        end

        if not ok then
            Log.warn("failed to unregister trigger", record.kind, record.handle)
        end
    end
    self._handles = {}
end

return TriggerRegistry
