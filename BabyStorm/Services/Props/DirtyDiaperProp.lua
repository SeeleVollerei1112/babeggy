local Class = require("BaseClass")
local Timer = require("BabyStorm.Core.Timer")
local Rand = require("Util.Rand")
local MathX = require("Util.MathX")
local UnitUtil = require("Util.UnitUtil")
local Log = require("Util.Log")

local TWO_PI = 6.2831853

-- 脏尿布道具能力层：换洗完成时以玩家为原点把脏尿布抛到身后，触地即在脚下留一块赃物贴花；
-- 之后玩家每把它蹭动 trail_step、或每放下一次，再带出一块。一坨总共只脏 decal_max 块，
-- 用完就收工（跟踪定时器一并释放）。被举着的时候不脏地——抱着走一路掉赃物不合理。
-- 只管这坨脏东西自己的引擎接口（创建/物理开关/初速/贴花创建/回收），不做任何玩法判定——
-- “什么时候该抛”由 CribInteraction 在换洗结算时决定。
--
-- 位移全程是引擎真实物理，脚本不驱动：飞行的抛物线由引擎算（实测水平速度精确恒定，很干净），
-- 落地后尿布就趴在那儿——引擎会在触地那一帧把组件速度整个清零（实测落地前一帧还有 4.57m/s，
-- 下一帧三个分量全为 0、位置只挪 3mm），所以它自己不会滚，赃物全靠玩家去踢/搬它带出来。
---@class BabyDiaperPile
---@field diaper Obstacle|Unit|nil
---@field units (Obstacle|Unit)[]
---@field track_handle TimerHandle|nil
---
---@class DirtyDiaperProp
---@field cfg BabyDirtyDiaperConfig
---@field floor_y Fixed
---@field _piles BabyDiaperPile[]
---@field _decal_seq integer
local DirtyDiaperProp = Class("DirtyDiaperProp")

---@param config BabyStormConfig
function DirtyDiaperProp:Ctor(config)
    self.cfg = config.dirty_diaper
    self.floor_y = config.arena.floor_y
    self._piles = {}
    self._decal_seq = 0
end

-- ============================================================
-- 抛出
-- ============================================================

---以玩家为出发点抛出一坨脏尿布。role 为空（玩家已断线）时静默跳过。
---@param role Role|nil
function DirtyDiaperProp:throw_from(role)
    local cfg = self.cfg
    if not (cfg and cfg.enabled and role) then
        return
    end
    local player = role.get_ctrl_unit and role.get_ctrl_unit() or nil
    local player_pos = player and player.get_position and player.get_position() or nil
    if not player_pos then
        Log.warn("dirty diaper throw skipped: no player unit")
        return
    end

    local scale = MathX.to_vector3(cfg.scale) or math.Vector3(0.3, 0.3, 0.3)
    local spawn = player_pos + (MathX.to_vector3(cfg.spawn_offset) or math.Vector3(0.0, 1.0, 0.0))
    local ok, diaper = pcall(function()
        return GameAPI.create_obstacle(cfg.prefab, spawn, math.Quaternion(0.0, 0.0, 0.0), scale, nil)
    end)
    if not (ok and diaper) then
        Log.warn("dirty diaper create failed", cfg.prefab, tostring(diaper))
        return
    end

    local ok_setup = pcall(function()
        -- 保持预设自带的可举起：玩家能把脏尿布捡走扔掉。绝不在这里 set_lifted_enabled(false)
        -- ——历史 bug：关掉后编辑器里配的可举起失效，玩家点举起按钮毫无反应。
        diaper.set_physics_active(true)
        diaper.enable_gravity()
        -- 抛得快，开 CCD 防止穿地板飞出世界。
        diaper.enable_unit_ccd()
    end)
    if not ok_setup then
        pcall(function() GameAPI.destroy_unit(diaper) end)
        Log.warn("dirty diaper setup failed")
        return
    end

    ---@type BabyDiaperPile
    local pile = { diaper = diaper, units = { diaper }, track_handle = nil }
    self._piles[#self._piles + 1] = pile
    self:_trim_piles()
    self:_kick(diaper, self:_throw_dir(player))
    self:_track(pile, diaper, spawn)
end

---给出初速（抛出的那一下）。
---延后 kick_delay 再给：刚 create_obstacle 出来的组件，物理体要过一两帧才就绪，
---同帧 set_linear_velocity 会被引擎吞掉——表现为尿布不飞、直接掉在玩家脚下。
---@param diaper Obstacle|Unit
---@param dir Vector3
function DirtyDiaperProp:_kick(diaper, dir)
    local cfg = self.cfg
    local speed = cfg.throw_speed or 6.0
    local spin = cfg.throw_spin or 0.0
    Timer.once(self, cfg.kick_delay or 0.05, function()
        -- 尿布可能在这一两帧里已被玩家踢飞/引擎回收，保留 pcall。
        pcall(function()
            diaper.set_linear_velocity(math.Vector3(dir.x * speed, cfg.throw_up_speed or 4.0, dir.z * speed))
            -- 旋转轴取行进方向的水平垂线：空中是往前翻着飞，而不是原地打转。
            diaper.set_angular_velocity(math.Vector3(dir.z * spin, 0.0, -dir.x * spin))
        end)
    end)
end

---抛出方向：玩家正后方的水平单位向量（脏尿布往身后甩，不挡玩家视线、不砸在脸前）。
---朝向读不到或近乎垂直时退化为随机水平方向。
---@param player Unit|LifeEntity
---@return Vector3
function DirtyDiaperProp:_throw_dir(player)
    -- 玩家可能已断线，朝向读取保留 pcall。
    local ok, facing = pcall(function() return player.get_direction() end)
    local x, z
    if ok and facing then
        x, z = -facing.x, -facing.z -- 取反 = 身后
    end
    if not x or (x * x + z * z) < 0.01 then
        x, z = Rand.signed(), Rand.signed()
    end

    -- 左右抖一点，连续两次换洗不会把尿布叠在同一条线上。
    local jitter = self.cfg.side_jitter or 0.0
    local rx = x + z * Rand.signed() * jitter
    local rz = z - x * Rand.signed() * jitter
    local length = math.sqrt(rx * rx + rz * rz)
    if length < 0.01 then
        return math.Vector3(1.0, 0.0, 0.0)
    end
    return math.Vector3(rx / length, 0.0, rz / length)
end

-- ============================================================
-- 跟踪：触地 / 放下 / 蹭动够远 时盖赃物
-- ============================================================

---@param pile BabyDiaperPile
---@param diaper Obstacle|Unit
---@param spawn Vector3
function DirtyDiaperProp:_track(pile, diaper, spawn)
    local track = {
        last_pos = spawn,
        moved = 0.0,        -- 上一块贴花之后累计挪动的水平距离
        stamps = 0,         -- 已盖的贴花块数（第 1 块 = 落地，之后 = 被玩家蹭/放下带出来的）
        descended = false,  -- 见 _track_tick：落地判定要先看到明显下落
        was_lifted = false, -- 上一 tick 是否被举着，用来抓“放下”的下降沿
    }
    pile.track_handle = Timer.every(self, self.cfg.track_interval or 0.1, function()
        self:_track_tick(pile, diaper, track)
    end)
end

-- 落地首块的判据：先看到明显下落（descended），之后某一 tick 不再下落 = 碰到地面了。
-- 不能只看「不下落」——抛物线的上升段同样不下落，会在出手瞬间就误判。
---@param pile BabyDiaperPile
---@param diaper Obstacle|Unit
---@param track table
function DirtyDiaperProp:_track_tick(pile, diaper, track)
    local cfg = self.cfg
    -- 尿布可能被玩家丢出界/踢飞而被引擎销毁，位置读取保留 pcall。
    local ok, pos = pcall(function() return diaper.get_position() end)
    if not (ok and pos) then
        self:_finish_track(pile)
        return
    end

    -- 被玩家举着：不盖赃物，也不累计位移（放下后重新算，免得一放下就立刻满里程）。
    if self:_is_lifted(diaper) then
        track.was_lifted = true
        track.last_pos = pos
        return
    end

    if track.was_lifted then
        -- “放下”的下降沿：搁哪儿哪儿脏一块，立刻出，不等它落地。
        track.was_lifted = false
        self:_stamp(pile, track, pos)
    elseif track.stamps == 0 then
        if pos.y - track.last_pos.y < -(cfg.land_drop_epsilon or 0.05) then
            track.descended = true
        elseif track.descended then
            self:_stamp(pile, track, pos)
        end
    else
        track.moved = track.moved + self:_dist_xz(pos, track.last_pos)
        if track.moved >= (cfg.trail_step or 4.0) then
            self:_stamp(pile, track, pos)
        end
    end
    track.last_pos = pos
end

---@param pile BabyDiaperPile
---@param track table
---@param pos Vector3
function DirtyDiaperProp:_stamp(pile, track, pos)
    self:_spawn_decal(pile, pos)
    track.stamps = track.stamps + 1
    -- 每块贴花都把里程清零：一次挪动只掉一块，要再掉得重新挪够 trail_step。
    track.moved = 0.0

    -- 一坨尿布总共就这么多块（落地那块也算在内），用完就收工：跟踪定时器一并释放，
    -- 之后再怎么踢它、放下它都不会再脏地。
    if track.stamps >= (self.cfg.decal_max or 3) then
        self:_finish_track(pile)
    end
end

---@param diaper Obstacle|Unit
---@return boolean
function DirtyDiaperProp:_is_lifted(diaper)
    -- 尿布可能已被丢出界销毁，读取保留 pcall（同 BallProp:is_free）。
    local ok, lifted = pcall(function() return diaper.is_lifted_status() end)
    return ok and lifted or false
end

---@param pile BabyDiaperPile
function DirtyDiaperProp:_finish_track(pile)
    Timer.cancel(pile.track_handle)
    pile.track_handle = nil
end

-- ============================================================
-- 贴花
-- ============================================================

---在 center 附近盖一块赃物贴花（随机贴纸/朝向/大小）。
---两个反直觉点，都是踩坑换来的：
---  * 贴纸是「装饰物」不是「组件」，只能用 create_decoration 建——obstacle 预设表里查不到
---    这些 key（用 create_obstacle 每次都报 not find prefab unit key 200455 返回 nil，
---    一地赃物全没出来）。装饰物天生无物理无碰撞，正合贴花所需。
---  * 高度只取地面平面 floor_y，绝不用尿布自己的 y：它被举着时在蛋仔头顶、被踢时在半空，
---    跟着它走就会把赃物盖到头顶/空中。（本环境 raycast_unit 打不中任何东西，测不了真实地面。）
---@param pile BabyDiaperPile
---@param center Vector3
function DirtyDiaperProp:_spawn_decal(pile, center)
    local cfg = self.cfg
    local keys = cfg.decal_keys
    if not (keys and #keys > 0) then
        return
    end
    -- 每块贴花错开一丁点高度：两块叠在一起时，等高会让顶面共面、渲染器在两者间反复跳
    -- （表现为一片赃物在“抽搐”）。层高远小于贴片自身厚度（0.1×scale），看不出高低差，
    -- 但足以打破共面。序号在全局滚动，不同尿布之间叠上也照样错开。
    self._decal_seq = (self._decal_seq + 1) % (cfg.decal_layers or 8)
    local spread = cfg.decal_spread or 0.15
    local pos = math.Vector3(
        center.x + Rand.signed() * spread,
        self.floor_y + (cfg.decal_y_offset or 0.02) + self._decal_seq * (cfg.decal_layer_step or 0.004),
        center.z + Rand.signed() * spread
    )

    local scale = Rand.fixed(cfg.decal_scale_min or 0.12, cfg.decal_scale_max or 0.22)
    local ok, decal = pcall(function()
        return GameAPI.create_decoration(
            keys[Rand.index(#keys)],
            pos,
            math.Quaternion(0.0, Rand.fixed(0.0, TWO_PI), 0.0),
            math.Vector3(scale, scale, scale),
            nil
        )
    end)
    if not (ok and decal) then
        Log.warn("dirty diaper decal create failed")
        return
    end
    pile.units[#pile.units + 1] = decal
end

---@param a Vector3
---@param b Vector3
---@return Fixed
function DirtyDiaperProp:_dist_xz(a, b)
    local dx = a.x - b.x
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dz * dz)
end

-- ============================================================
-- 回收
-- ============================================================

---返回仍在场上的脏尿布本体快照；地面贴花不参与手持吸尘器吸附。
---@return (Obstacle|Unit)[]
function DirtyDiaperProp:get_diapers()
    local diapers = {}
    for index = 1, #self._piles do
        local diaper = self._piles[index].diaper
        if diaper then
            diapers[#diapers + 1] = diaper
        end
    end
    return diapers
end

---@return (Obstacle|Unit)[]
function DirtyDiaperProp:get_vacuum_targets()
    return self:get_diapers()
end

---@param target Unit|nil
---@return boolean
function DirtyDiaperProp:is_cleanable(target)
    if not target then
        return false
    end
    for pile_index = 1, #self._piles do
        local pile = self._piles[pile_index]
        for unit_index = 1, #pile.units do
            if UnitUtil.same_unit(pile.units[unit_index], target) then
                return true
            end
        end
    end
    return false
end

---精确清除接触到的一块：尿布本体被清除时停止继续盖贴花；已有贴花保留待扫。
---@param target Unit|nil
---@return boolean
function DirtyDiaperProp:clean_unit(target)
    if not target then
        return false
    end
    for pile_index = #self._piles, 1, -1 do
        local pile = self._piles[pile_index]
        for unit_index = #pile.units, 1, -1 do
            if UnitUtil.same_unit(pile.units[unit_index], target) then
                self:_clean_unit_at(pile, unit_index)
                if #pile.units == 0 then
                    table.remove(self._piles, pile_index)
                end
                Log.info("dirty diaper mess cleaned by robot")
                return true
            end
        end
    end
    return false
end

---清除机器人清洁半径内的尿布/贴花。贴花是无碰撞 Decoration，只能用距离传感清理。
---@param center Vector3|nil
---@param radius Fixed
---@return integer
function DirtyDiaperProp:clean_near(center, radius)
    if not center then
        return 0
    end
    local radius_squared = radius * radius
    local cleaned = 0

    for pile_index = #self._piles, 1, -1 do
        local pile = self._piles[pile_index]
        for unit_index = #pile.units, 1, -1 do
            local unit = pile.units[unit_index]
            local ok, pos = pcall(function() return unit.get_position() end)
            if not ok then
                self:_clean_unit_at(pile, unit_index)
            elseif pos and UnitUtil.distance_xz_sq(center, pos) <= radius_squared then
                self:_clean_unit_at(pile, unit_index)
                cleaned = cleaned + 1
            end
        end
        if #pile.units == 0 then
            table.remove(self._piles, pile_index)
        end
    end

    if cleaned > 0 then
        Log.info("dirty diaper mess cleaned by robot", cleaned)
    end
    return cleaned
end

---@param pile BabyDiaperPile
---@param unit_index integer
function DirtyDiaperProp:_clean_unit_at(pile, unit_index)
    local unit = pile.units[unit_index]
    if UnitUtil.same_unit(unit, pile.diaper) then
        self:_finish_track(pile)
        pile.diaper = nil
    end
    pcall(function() GameAPI.destroy_unit(unit) end)
    table.remove(pile.units, unit_index)
end

---场上最多留 max_piles 坨，超出销毁最早的那坨（尿布 + 它带出的所有贴花）——
---一局里可以反复换洗，不清会无限堆组件。
function DirtyDiaperProp:_trim_piles()
    local max_piles = self.cfg.max_piles or 6
    while #self._piles > max_piles do
        self:_destroy_pile(self._piles[1])
        table.remove(self._piles, 1)
    end
end

---@param pile BabyDiaperPile
function DirtyDiaperProp:_destroy_pile(pile)
    -- 定时器跟着这坨走：被挤出场时一并取消，别留一个每 tick 去读已销毁单位的跟踪。
    self:_finish_track(pile)
    for index = 1, #pile.units do
        local unit = pile.units[index]
        -- 尿布可能已被丢出界销毁，destroy 兜底保留 pcall。
        pcall(function() GameAPI.destroy_unit(unit) end)
    end
    pile.units = {}
    pile.diaper = nil
end

function DirtyDiaperProp:destroy()
    Timer.cancel_all(self)
    for index = 1, #self._piles do
        self:_destroy_pile(self._piles[index])
    end
    self._piles = {}
    Log.info("dirty diaper piles destroyed")
end

return DirtyDiaperProp
