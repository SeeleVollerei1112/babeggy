local Enum = {}

---@class BabyStormEnum
---@field BabyStateLayer table<string, integer>
---@field BabyState table<string, integer>
---@field StateName table<integer, string>

---@type table<string, integer>
Enum.BabyStateLayer = {
    Core = 1,
}

---@type table<string, integer>
Enum.BabyState = {
    Idle = 1,
    Carried = 2,
    SeekingItem = 3,
    Satisfied = 4,
    Upset = 5,
    InteractingFacility = 6,
    Cry = 7, -- 需求超时哭闹（原 Timeout，按「行为状态描述目的」重命名）
    Mischief = 8, -- 需求倒计时低于阈值时主动捣乱（去就近点打翻东西）
}

---@type table<integer, string>
Enum.StateName = {
    [Enum.BabyState.Idle] = "Idle",
    [Enum.BabyState.Carried] = "Carried",
    [Enum.BabyState.SeekingItem] = "SeekingItem",
    [Enum.BabyState.Satisfied] = "Satisfied",
    [Enum.BabyState.Upset] = "Upset",
    [Enum.BabyState.InteractingFacility] = "InteractingFacility",
    [Enum.BabyState.Cry] = "Cry",
    [Enum.BabyState.Mischief] = "Mischief",
}

---@param state_id integer
---@return string
function Enum.get_state_name(state_id)
    return Enum.StateName[state_id] or tostring(state_id)
end

return Enum

