local Class = require("BaseClass")

local ViewModelBase = Class("ViewModelBase")

function ViewModelBase:Ctor()
    self._field_values = {}
    self._field_delegates = {}
    self._next_handle = 0
    self._batch_depth = 0
    self._pending_set = nil
    self._pending_order = nil
end

function ViewModelBase:add_field_changed_delegate(field_name, fn, owner)
    if type(field_name) ~= "string" or type(fn) ~= "function" then
        return nil
    end

    local list = self._field_delegates[field_name]
    if not list then
        list = {}
        self._field_delegates[field_name] = list
    end

    self._next_handle = self._next_handle + 1
    local handle = self._next_handle
    list[#list + 1] = { handle = handle, fn = fn, owner = owner, alive = true }
    return handle
end

function ViewModelBase:remove_field_changed_delegate(field_name, handle)
    local list = self._field_delegates[field_name]
    if not list then
        return false
    end

    for index = #list, 1, -1 do
        if list[index].handle == handle then
            list[index].alive = false
            table.remove(list, index)
            return true
        end
    end

    return false
end

function ViewModelBase:remove_all_delegates(owner)
    local count = 0
    for _, list in pairs(self._field_delegates) do
        for index = #list, 1, -1 do
            if list[index].owner == owner then
                list[index].alive = false
                table.remove(list, index)
                count = count + 1
            end
        end
    end
    return count
end

function ViewModelBase:broadcast_field_changed(field_name)
    local list = self._field_delegates[field_name]
    if not list or #list == 0 then
        return
    end

    local snapshot = {}
    for index = 1, #list do
        snapshot[index] = list[index]
    end

    for index = 1, #snapshot do
        local delegate = snapshot[index]
        if delegate.alive and delegate.fn then
            delegate.fn(self, field_name)
        end
    end
end

function ViewModelBase:begin_batch()
    self._batch_depth = self._batch_depth + 1
end

function ViewModelBase:end_batch()
    if self._batch_depth == 0 then
        return
    end

    self._batch_depth = self._batch_depth - 1
    if self._batch_depth > 0 then
        return
    end

    local order = self._pending_order
    self._pending_set = nil
    self._pending_order = nil

    if order then
        for index = 1, #order do
            self:broadcast_field_changed(order[index])
        end
    end
end

function ViewModelBase:batch(fn)
    self:begin_batch()
    local ok, err = pcall(fn)
    self:end_batch()
    if not ok then
        error(err)
    end
end

function ViewModelBase:_mark_pending(field_name)
    if not self._pending_set then
        self._pending_set = {}
        self._pending_order = {}
    end

    if not self._pending_set[field_name] then
        self._pending_set[field_name] = true
        self._pending_order[#self._pending_order + 1] = field_name
    end
end

function ViewModelBase:set_property(field_name, value)
    if value == nil or self._field_values[field_name] == value then
        return false
    end

    self._field_values[field_name] = value
    if self._batch_depth > 0 then
        self:_mark_pending(field_name)
    else
        self:broadcast_field_changed(field_name)
    end
    return true
end

function ViewModelBase:get_property(field_name)
    return self._field_values[field_name]
end

function ViewModelBase:set_property_silently(field_name, value)
    self._field_values[field_name] = value
end

function ViewModelBase:clear()
    self._field_delegates = {}
end

return ViewModelBase
