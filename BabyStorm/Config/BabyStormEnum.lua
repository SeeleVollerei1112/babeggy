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
    PlayRps = 8,    -- 猜拳小游戏（配对→抛骰→顶撞→判分，由 RpsCoordinator 触发）
    BallRally = 9,  -- 顶球小游戏（发球→玩家顶回→回合循环，由 BallRallyCoordinator 触发）
    PlayingToy = 10, -- 把玩玩具（捡到玩具玩一会儿再放下；有需求则玩完结算满足）
    Wandering = 11,  -- 漫游：Idle 站够了起身逛一段，逛够了回 Idle（起身那一刻掷骰决定要不要顺路捡玩具）
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
    [Enum.BabyState.PlayRps] = "PlayRps",
    [Enum.BabyState.BallRally] = "BallRally",
    [Enum.BabyState.PlayingToy] = "PlayingToy",
    [Enum.BabyState.Wandering] = "Wandering",
}

---@param state_id integer
---@return string
function Enum.get_state_name(state_id)
    return Enum.StateName[state_id] or tostring(state_id)
end

return Enum

