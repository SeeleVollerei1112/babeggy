local Class = require("BaseClass")
local Log = require("Util.Log")

---@class ArenaService
---@field config BabyStormConfig
---@field area Unit|nil
local ArenaService = Class("ArenaService")

---@param config BabyStormConfig
function ArenaService:Ctor(config)
    self.config = config
    self.area = nil
end

---@return boolean
function ArenaService:init()
    local area_name = self.config.arena.area_name
    self.area = LuaAPI.query_unit(area_name)
    if not self.area then
        local arena = self.config.arena
        if arena.fallback_min_x and arena.fallback_max_x and arena.fallback_min_z and arena.fallback_max_z then
            Log.warn("missing trigger area, using configured bounds:", area_name)
            return true
        end
        Log.warn("missing trigger area:", area_name)
        return false
    end
    return true
end

---@param min_value Fixed
---@param max_value Fixed
---@return Fixed
local function random_fixed(min_value, max_value)
    local raw
    if GameAPI and GameAPI.random_int then
        raw = GameAPI.random_int(0, 10000)
    else
        raw = LuaAPI.rand and LuaAPI.rand() or 0
        if raw < 0 then
            raw = -raw
        end
        raw = raw % 10001
    end
    return min_value + (max_value - min_value) * (raw / 10000.0)
end

---@return Vector3
function ArenaService:random_point()
    if self.area and self.area.random_point then
        return self.area.random_point()
    end
    if self.area and self.area.get_customtriggerspaces_random_point then
        return self.area.get_customtriggerspaces_random_point()
    end
    local arena = self.config.arena
    if arena.fallback_min_x and arena.fallback_max_x and arena.fallback_min_z and arena.fallback_max_z then
        return math.Vector3(
            random_fixed(arena.fallback_min_x, arena.fallback_max_x),
            arena.fallback_y or 1.0,
            random_fixed(arena.fallback_min_z, arena.fallback_max_z)
        )
    end
    return math.Vector3(0, 1, 0)
end

---@param point Vector3
---@return Vector3
function ArenaService:ground_point(point)
    local arena = self.config.arena
    local start_pos = math.Vector3(point.x, point.y + arena.ground_ray_up, point.z)
    local end_pos = math.Vector3(point.x, point.y - arena.ground_ray_down, point.z)
    local best_y = nil

    -- 用单位射线打已摆放的 OBSTACLE 组件取地面高度。
    -- 注：raycast_test 物理射线在本环境会内部报错（mask 取值未知），暂不使用。
    if GameAPI.raycast_unit then
        pcall(function()
            GameAPI.raycast_unit(start_pos, end_pos, { Enums.UnitType.OBSTACLE }, function(unit, hit_pos, normal)
                if hit_pos and (not best_y or hit_pos.y > best_y) then
                    best_y = hit_pos.y
                end
            end)
        end)
    end

    if best_y then
        return math.Vector3(point.x, best_y, point.z)
    end
    return point
end

---@return Vector3
function ArenaService:random_ground_point()
    return self:ground_point(self:random_point())
end

return ArenaService
