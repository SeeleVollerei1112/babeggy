local UnitUtil = require("Util.UnitUtil")

local RoleUtil = {}

---@param role Role|any
---@return RoleID|integer|nil
function RoleUtil.get_role_id(role)
    if role and role.get_roleid then
        return role.get_roleid()
    end
    return nil
end

---@param unit Unit|LifeEntity|any
---@return Role|nil
function RoleUtil.get_role_by_unit(unit)
    if not unit then
        return nil
    end

    if unit.get_owner then
        local owner = unit.get_owner()
        if owner then
            return owner
        end
    end

    if unit.get_role_id then
        local role_id = unit.get_role_id()
        if role_id then
            return GameAPI.get_role(role_id)
        end
    end

    local roles = GameAPI.get_all_valid_roles() or {}
    for index = 1, #roles do
        local role = roles[index]
        local ctrl = role.get_ctrl_unit and role.get_ctrl_unit()
        if UnitUtil.same_unit(ctrl, unit) then
            return role
        end
    end

    return nil
end

return RoleUtil
