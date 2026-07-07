-- 统一定时器:业务代码唯一允许的时间来源。
-- 目标是消灭「无主 call_delay_time + token 守卫」惯用法:每个定时器必须挂在 owner 名下,
-- owner 退场(状态 exit / agent destroy / driver stop)时 cancel_all 一次清场,
-- 不再需要 token 比对来判断回调是否过期。
--
-- 三个原语:
--   once(owner, delay, fn)         一次性(call_delay_time)
--   every(owner, interval, fn)     周期(引擎 REPEAT_TIMEOUT 触发器,事件驱动;
--                                  适合 >= 0.1s 的逻辑节拍/传感轮询)
--   every_frame(owner, frames, fn) 帧级周期(call_delay_frame 自续;仅供 Core/Drivers
--                                  的连续运动使用,业务层不得调用)
--
-- 引擎坑位记录:
--   * call_delay_time 的间隔是 Fixed——传 Lua 整数会被当成 0 立即触发
--     (历史 bug:秋千互动"坐下即结束"),本模块统一 `+ 0.0` 强转。
--   * 帧同步沙盒禁止 table 作 table 键,owner 索引用数组线扫(量级为几十,足够)。
--   * 安全网:owner 带 destroyed == true 时回调自动失效(BabyAgent 等约定字段)。
local Timer = {}

---@class TimerHandle
---@field owner any
---@field fn fun()
---@field kind "once"|"every"|"every_frame"
---@field active boolean
---@field frames integer|nil     -- every_frame 的帧间隔
---@field trigger_id integer|nil -- every 的引擎触发器注册 ID

---@type TimerHandle[]
local records = {}

---@param owner any
---@return boolean
local function owner_dead(owner)
    return owner ~= nil and owner.destroyed == true
end

---@param record TimerHandle
local function remove_record(record)
    for index = #records, 1, -1 do
        if records[index] == record then
            table.remove(records, index)
            return
        end
    end
end

---@param record TimerHandle
local function expire(record)
    if not record.active then
        return
    end
    record.active = false
    if record.trigger_id then
        LuaAPI.global_unregister_trigger_event(record.trigger_id)
        record.trigger_id = nil
    end
    remove_record(record)
end

---一次性定时器。owner 必填。
---@param owner any
---@param delay Fixed
---@param fn fun()
---@return TimerHandle
function Timer.once(owner, delay, fn)
    ---@type TimerHandle
    local record = { owner = owner, fn = fn, kind = "once", active = true }
    records[#records + 1] = record
    LuaAPI.call_delay_time(delay + 0.0, function()
        if not record.active or owner_dead(record.owner) then
            expire(record)
            return
        end
        expire(record)
        fn()
    end)
    return record
end

---周期定时器(事件驱动,REPEAT_TIMEOUT)。owner 必填。
---@param owner any
---@param interval Fixed
---@param fn fun()
---@return TimerHandle
function Timer.every(owner, interval, fn)
    ---@type TimerHandle
    local record = { owner = owner, fn = fn, kind = "every", active = true }
    record.trigger_id = LuaAPI.global_register_trigger_event(
        { EVENT.REPEAT_TIMEOUT, interval + 0.0 },
        function()
            if not record.active or owner_dead(record.owner) then
                expire(record)
                return
            end
            fn()
        end
    )
    records[#records + 1] = record
    return record
end

---帧级周期定时器(call_delay_frame 自续)。仅供 Core/Drivers 使用。
---@param owner any
---@param frames integer 帧间隔(>= 1)
---@param fn fun()
---@return TimerHandle
function Timer.every_frame(owner, frames, fn)
    ---@type TimerHandle
    local record = {
        owner = owner,
        fn = fn,
        kind = "every_frame",
        active = true,
        frames = math.tointeger(frames) or 1,
    }
    records[#records + 1] = record

    local function schedule()
        LuaAPI.call_delay_frame(record.frames, function()
            if not record.active or owner_dead(record.owner) then
                expire(record)
                return
            end
            fn()
            -- fn 内部可能已 cancel 自己,续期前复查。
            if record.active then
                schedule()
            end
        end)
    end
    schedule()
    return record
end

---取消单个定时器。对已取消/已触发的句柄调用是 no-op。
---@param handle TimerHandle|nil
function Timer.cancel(handle)
    if handle then
        expire(handle)
    end
end

---取消 owner 名下全部定时器(状态 exit / destroy 时调用)。
---@param owner any
function Timer.cancel_all(owner)
    for index = #records, 1, -1 do
        local record = records[index]
        if record.owner == owner then
            expire(record)
        end
    end
end

---模块级清场(整个玩法 destroy 时兜底)。
function Timer.destroy_all()
    for index = #records, 1, -1 do
        expire(records[index])
    end
    records = {}
end

---调试:当前活跃定时器数量。
---@return integer
function Timer.count()
    return #records
end

return Timer
