-- 公共定点数学工具。全部自 BallRallyService / FacilityService 平移,行为不变。
local MathX = {}

local TWO_PI = 6.2831853

---@param value Fixed
---@param min_value Fixed
---@param max_value Fixed
---@return Fixed
function MathX.clamp(value, min_value, max_value)
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

---@param a Fixed
---@param b Fixed
---@param t Fixed
---@return Fixed
function MathX.lerp(a, b, t)
    return a + (b - a) * t
end

-- 飞行进度缓动:两端快、中间慢(ease-out-in,顶点自带悬停感)。
-- hang ∈ [0,1] 控制中段变慢程度:0=匀速,1=顶点近乎悬停。
---@param s Fixed 线性进度 [0,1]
---@param hang Fixed|nil
---@return Fixed
function MathX.ease_out_in(s, hang)
    local shaped
    if s < 0.5 then
        shaped = s * (2.0 - 2.0 * s) -- 前半段 ease-out:起手快
    else
        local k = 2.0 * s - 1.0
        shaped = 0.5 + 0.5 * k * k -- 后半段 ease-in:落地快
    end
    return s + (shaped - s) * (hang or 0.0)
end

-- 纯减速缓动(ease-out):越接近终点越慢。骰子垂直上抛用。
---@param s Fixed 线性进度 [0,1]
---@return Fixed
function MathX.ease_out(s)
    return 1.0 - (1.0 - s) * (1.0 - s)
end

---把角度归一化到 [-pi, pi]
---@param a Fixed
---@return Fixed
function MathX.wrap_angle(a)
    a = math.fmod(a, TWO_PI)
    if a > TWO_PI * 0.5 then
        a = a - TWO_PI
    elseif a < -TWO_PI * 0.5 then
        a = a + TWO_PI
    end
    return a
end

---把 current 朝 desired 旋转,单步最多 max_delta(弧度)
---@param current Fixed
---@param desired Fixed
---@param max_delta Fixed
---@return Fixed
function MathX.approach_angle(current, desired, max_delta)
    local diff = MathX.wrap_angle(desired - current)
    if diff > max_delta then
        diff = max_delta
    elseif diff < -max_delta then
        diff = -max_delta
    end
    return MathX.wrap_angle(current + diff)
end

---配置数组 {x, y, z} → Vector3;nil 透传(配置项可选)。
---@param values Fixed[]|nil
---@return Vector3|nil
function MathX.to_vector3(values)
    if not values then
        return nil
    end
    return math.Vector3(values[1], values[2], values[3])
end

---配置数组 {角度x, 角度y, 角度z}(度) → Quaternion(弧度);nil 透传。
---@param values Fixed[]|nil
---@return Quaternion|nil
function MathX.to_quaternion(values)
    if not values then
        return nil
    end
    return math.Quaternion(
        math.deg_to_rad(values[1]),
        math.deg_to_rad(values[2]),
        math.deg_to_rad(values[3])
    )
end

return MathX
