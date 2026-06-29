local Class = require("BaseClass")

---@class ViewBindingRecord
---@field vm ViewModelBase
---@field field string
---@field handle integer

---@class ViewBinding
---@field _bindings ViewBindingRecord[]
local ViewBinding = Class("ViewBinding")

---@return nil
function ViewBinding:Ctor()
    self._bindings = {}
end

---@param view_model ViewModelBase|nil
---@param field string|nil
---@param on_changed ViewModelDelegate|nil
---@param execute_on_bind boolean|nil
---@return integer|nil
function ViewBinding:bind_one_way(view_model, field, on_changed, execute_on_bind)
    if not (view_model and field and on_changed) then
        return nil
    end

    local handle = view_model:add_field_changed_delegate(field, on_changed, self)
    if handle then
        self._bindings[#self._bindings + 1] = { vm = view_model, field = field, handle = handle }
    end

    if execute_on_bind then
        on_changed(view_model, field)
    end
    return handle
end

---@param bindings any[][]
function ViewBinding:bind_all(bindings)
    for index = 1, #bindings do
        local binding = bindings[index]
        self:bind_one_way(binding[1], binding[2], binding[3], binding[4])
    end
end

---@return nil
function ViewBinding:destroy()
    -- 不能用 table（vm）作为 table 索引来去重（帧同步沙盒禁止 table/userdata 作键）。
    -- remove_all_delegates 是幂等的，重复调用无副作用，直接逐条调用即可。
    for index = #self._bindings, 1, -1 do
        local vm = self._bindings[index].vm
        if vm then
            vm:remove_all_delegates(self)
        end
    end
    self._bindings = {}
end

return ViewBinding
