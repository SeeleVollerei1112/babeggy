local Class = require("BaseClass")

---@class RandomBag
---@field _source any[]
---@field _bag any[]
local RandomBag = Class("RandomBag")

---@param items any[]|nil
function RandomBag:Ctor(items)
    self._source = items or {}
    self._bag = {}
end

---@param count integer
---@return integer
function RandomBag:_rand_index(count)
    return math.tointeger((LuaAPI.rand() % count) + 1)
end

---@private
function RandomBag:_refill()
    self._bag = {}
    for index = 1, #self._source do
        self._bag[index] = self._source[index]
    end

    for index = #self._bag, 2, -1 do
        local swap_index = self:_rand_index(index)
        self._bag[index], self._bag[swap_index] = self._bag[swap_index], self._bag[index]
    end
end

---@return any|nil
function RandomBag:take()
    if #self._bag <= 0 then
        self:_refill()
    end
    return table.remove(self._bag)
end

return RandomBag
