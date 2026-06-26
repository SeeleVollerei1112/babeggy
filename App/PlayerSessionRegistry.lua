local Class = require("BaseClass")
local RoleUtil = require("Util.RoleUtil")

---@class PlayerSession
---@field role Role
---@field role_id RoleID|integer
---@field satisfied_count integer
---@field wrong_count integer
---@field score_awarded integer

---@class PlayerSessionRegistry
---@field _sessions table<RoleID|integer, PlayerSession>
---@field _ordered_role_ids (RoleID|integer)[]
local PlayerSessionRegistry = Class("PlayerSessionRegistry")

---@return nil
function PlayerSessionRegistry:Ctor()
    self._sessions = {}
    self._ordered_role_ids = {}
end

---@param role Role
---@param role_id RoleID|integer
---@return PlayerSession
function PlayerSessionRegistry:_create_session(role, role_id)
    return {
        role = role,
        role_id = role_id,
        satisfied_count = 0,
        wrong_count = 0,
        score_awarded = 0,
    }
end

---@param role Role
---@return PlayerSession|nil
function PlayerSessionRegistry:add_role(role)
    local role_id = RoleUtil.get_role_id(role)
    if not role_id then
        return nil
    end

    local session = self._sessions[role_id]
    if session then
        session.role = role
        return session
    end

    session = self:_create_session(role, role_id)
    self._sessions[role_id] = session
    self._ordered_role_ids[#self._ordered_role_ids + 1] = role_id
    table.sort(self._ordered_role_ids)
    return session
end

---@param role Role|nil
---@return PlayerSession|nil
function PlayerSessionRegistry:find(role)
    local role_id = RoleUtil.get_role_id(role)
    if not role_id then
        return nil
    end
    return self._sessions[role_id]
end

---@return nil
function PlayerSessionRegistry:sync_all()
    local roles = GameAPI.get_all_valid_roles() or {}
    local alive = {}

    for index = 1, #roles do
        local role = roles[index]
        local role_id = RoleUtil.get_role_id(role)
        if role_id then
            alive[role_id] = true
            self:add_role(role)
        end
    end

    for index = #self._ordered_role_ids, 1, -1 do
        local role_id = self._ordered_role_ids[index]
        if not alive[role_id] then
            self._sessions[role_id] = nil
            table.remove(self._ordered_role_ids, index)
        end
    end
end

---@param callback fun(session:PlayerSession, role_id:RoleID|integer)
function PlayerSessionRegistry:for_each(callback)
    for index = 1, #self._ordered_role_ids do
        local role_id = self._ordered_role_ids[index]
        local session = self._sessions[role_id]
        if session then
            callback(session, role_id)
        end
    end
end

---@return integer
function PlayerSessionRegistry:count()
    return #self._ordered_role_ids
end

---@return nil
function PlayerSessionRegistry:clear()
    self._sessions = {}
    self._ordered_role_ids = {}
end

return PlayerSessionRegistry
