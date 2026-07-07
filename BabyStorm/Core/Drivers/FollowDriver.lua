local Class = require("BaseClass")
local Timer = require("BabyStorm.Core.Timer")

-- 硬粘跟随驱动:每步把单位钉到参考单位的(局部偏移)位置,可选朝向跟随。
-- 合并两处历史实现——
--   * FacilityService._sync_seat(座椅/床:绑定 API 挪不动活体单位,只能按帧定位)
--   * FacilityService._snap_baby_to_rider/_follow_rider_orientation(滑板骑手跟随)
--
-- 朝向语义(来自滑板调参经验):位置参考骑手、朝向参考滑板本体——玩家身上叠了
-- 转身/动作的倾,照搬会失真;板本体的朝向才是板真实的倾。因此 orient_target
-- 允许与 target 不同。用 *_smooth 接口让引擎在逻辑帧之间插值,跟随不一卡一卡。
--
-- 调用方约定:销毁单位前必须先 stop()(Driver 内不做单位存活防御)。
--
---@class FollowSpec
---@field unit Unit|LifeEntity            -- 被粘的单位(宝宝)
---@field target Unit                     -- 位置参考(座椅/床/骑手)
---@field offset Vector3|nil              -- target 局部偏移(随其朝向旋转)
---@field orient "target"|"fixed"|"none"|nil -- 朝向模式,默认 "none"
---@field orient_target Unit|nil          -- 朝向参考单位,默认 = target(滑板传板本体)
---@field orient_offset Quaternion|nil    -- 叠加朝向偏移(局部右乘)
---@field fixed_rotation Quaternion|nil   -- orient = "fixed" 时的固定朝向
---@field smooth boolean|nil              -- 用 *_smooth 接口,默认 true
---@field frames integer|nil              -- 驱动步长(逻辑帧),默认 1

---@class FollowDriver
---@field _spec FollowSpec|nil
local FollowDriver = Class("FollowDriver")

function FollowDriver:Ctor()
    self._spec = nil
end

---@param spec FollowSpec
function FollowDriver:start(spec)
    self:stop()
    if spec.smooth == nil then
        spec.smooth = true
    end
    self._spec = spec
    Timer.every_frame(self, spec.frames or 1, function()
        self:_step()
    end)
end

function FollowDriver:stop()
    Timer.cancel_all(self)
    self._spec = nil
end

---@return boolean
function FollowDriver:is_active()
    return self._spec ~= nil
end

---@private
function FollowDriver:_step()
    local spec = self._spec
    if not spec then
        return
    end
    local unit = spec.unit
    local target = spec.target

    -- 位置:优先局部偏移(随参考单位朝向走),退化为参考单位世界坐标。
    local pos
    if spec.offset then
        pos = target.get_local_offset_position(spec.offset)
    else
        pos = target.get_position()
    end
    if pos then
        if spec.smooth and unit.set_position_smooth then
            unit.set_position_smooth(pos)
        else
            unit.set_position(pos)
        end
    end

    -- 朝向
    local rot = nil
    if spec.orient == "target" then
        local source = spec.orient_target or target
        rot = source.get_orientation()
        if rot and spec.orient_offset then
            rot = rot * spec.orient_offset
        end
    elseif spec.orient == "fixed" then
        rot = spec.fixed_rotation
    end
    if rot then
        if spec.smooth and unit.set_orientation_smooth then
            unit.set_orientation_smooth(rot)
        else
            unit.set_orientation(rot)
        end
    end
end

return FollowDriver
