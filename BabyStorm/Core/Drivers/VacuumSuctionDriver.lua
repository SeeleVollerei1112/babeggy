local Class = require("BaseClass")
local Timer = require("BabyStorm.Core.Timer")

local FRAME_DT = math.tofixed(1) / math.tofixed(30)

---@class VacuumSuctionSpec
---@field source Unit|Obstacle
---@field cleaners table
---@field pull_radius Fixed
---@field destroy_radius Fixed
---@field pull_speed Fixed

-- 手持吸尘器的连续吸附驱动：移动各清理源登记的地面单位，进入销毁距离后交还其拥有者回收。
---@class VacuumSuctionDriver
---@field _spec VacuumSuctionSpec|nil
local VacuumSuctionDriver = Class("VacuumSuctionDriver")

function VacuumSuctionDriver:Ctor()
    self._spec = nil
end

---@param spec VacuumSuctionSpec
---@return boolean
function VacuumSuctionDriver:start(spec)
    self:stop()
    if not (spec and spec.source and spec.source.get_position and spec.cleaners and #spec.cleaners > 0) then
        return false
    end

    self._spec = spec
    Timer.every_frame(self, 1, function()
        self:_step()
    end)
    return true
end

function VacuumSuctionDriver:stop()
    Timer.cancel_all(self)
    self._spec = nil
end

---@return boolean
function VacuumSuctionDriver:is_active()
    return self._spec ~= nil
end

---@private
function VacuumSuctionDriver:_step()
    local spec = self._spec
    if not spec then
        return
    end

    local ok, center = pcall(function() return spec.source.get_position() end)
    if not (ok and center) then
        self:stop()
        return
    end

    for cleaner_index = 1, #spec.cleaners do
        local cleaner = spec.cleaners[cleaner_index]
        local targets = cleaner:get_vacuum_targets()
        for target_index = 1, #targets do
            self:_pull(targets[target_index], center, spec, cleaner)
        end
    end
end

---@private
---@param target Obstacle|Unit
---@param center Vector3
---@param spec VacuumSuctionSpec
---@param cleaner table
function VacuumSuctionDriver:_pull(target, center, spec, cleaner)
    local ok_lifted, lifted = pcall(function() return target.is_lifted_status() end)
    if ok_lifted and lifted then
        return
    end

    local ok, pos = pcall(function() return target.get_position() end)
    if not (ok and pos) then
        return
    end

    local dx = center.x - pos.x
    local dy = center.y - pos.y
    local dz = center.z - pos.z
    local distance_squared = dx * dx + dy * dy + dz * dz
    local destroy_radius = spec.destroy_radius
    if distance_squared <= destroy_radius * destroy_radius then
        cleaner:clean_unit(target)
        return
    end
    if distance_squared > spec.pull_radius * spec.pull_radius then
        return
    end

    local distance = math.sqrt(distance_squared)
    local step = math.min(spec.pull_speed * FRAME_DT, distance - destroy_radius)
    local scale = step / distance
    local target_pos = math.Vector3(
        pos.x + dx * scale,
        pos.y + dy * scale,
        pos.z + dz * scale
    )
    pcall(function() target.set_position(target_pos) end)
end

return VacuumSuctionDriver
