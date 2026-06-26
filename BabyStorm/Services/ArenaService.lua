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
        Log.warn("missing trigger area:", area_name)
        if GlobalAPI and GlobalAPI.show_tips then
            GlobalAPI.show_tips("未找到触发区 " .. tostring(area_name), 3.0)
        end
        return false
    end
    return true
end

---@return Vector3
function ArenaService:random_point()
    if self.area and self.area.random_point then
        return self.area.random_point()
    end
    if self.area and self.area.get_customtriggerspaces_random_point then
        return self.area.get_customtriggerspaces_random_point()
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
