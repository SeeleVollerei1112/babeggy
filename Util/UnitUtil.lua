local UnitUtil = {}

---@param unit Unit|LifeEntity|Equipment|any
---@return integer|string|nil
function UnitUtil.get_id(unit)
    if unit and unit.get_id then
        return unit.get_id()
    end
    return nil
end

---@param a Unit|LifeEntity|Equipment|any
---@param b Unit|LifeEntity|Equipment|any
---@return boolean
function UnitUtil.same_unit(a, b)
    if a == b then
        return true
    end

    local a_id = UnitUtil.get_id(a)
    local b_id = UnitUtil.get_id(b)
    return a_id ~= nil and b_id ~= nil and a_id == b_id
end

---@param a Vector3
---@param b Vector3
---@return Fixed
function UnitUtil.distance_sq(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

return UnitUtil
