-- 全工程唯一的随机数入口(帧同步确定性)。
-- 随机源只用 GameAPI.random_int(引擎保证联机同步、无取模偏差)。
-- 禁止在业务代码直接使用 LuaAPI.rand / GameAPI.random_int——历史上五处手写副本
-- 取值分辨率各不相同(0~200 / 0~1000 / 0~10000),已全部收编于此。
local Rand = {}

-- Fixed 随机的分辨率:万分之一,与历史实现中最细的一档(BallRally)一致。
local RESOLUTION = 10000

---[min, max] 闭区间随机整数。max < min 时按 min 处理。
---@param min_value integer
---@param max_value integer
---@return integer
function Rand.int(min_value, max_value)
    if max_value < min_value then
        max_value = min_value
    end
    return GameAPI.random_int(min_value, max_value)
end

---[min, max] 区间随机定点数。max < min 时按 min 处理。
---@param min_value Fixed
---@param max_value Fixed
---@return Fixed
function Rand.fixed(min_value, max_value)
    if max_value < min_value then
        max_value = min_value
    end
    return min_value + (max_value - min_value) * (GameAPI.random_int(0, RESOLUTION) / 10000.0)
end

---[-1, 1] 随机定点数(横向偏移、抖动等)。
---@return Fixed
function Rand.signed()
    return Rand.fixed(-1.0, 1.0)
end

---[1, count] 随机下标(洗牌/抽签)。返回真整数,可安全用作 table 键。
---@param count integer
---@return integer
function Rand.index(count)
    if count <= 1 then
        return 1
    end
    return GameAPI.random_int(1, count)
end

return Rand
