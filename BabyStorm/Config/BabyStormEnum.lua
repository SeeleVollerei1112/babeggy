local Enum = {}

Enum.BabyStateLayer = {
    Core = 1,
}

Enum.BabyState = {
    Idle = 1,
    Carried = 2,
    SeekingItem = 3,
    Satisfied = 4,
    Upset = 5,
}

Enum.StateName = {
    [Enum.BabyState.Idle] = "Idle",
    [Enum.BabyState.Carried] = "Carried",
    [Enum.BabyState.SeekingItem] = "SeekingItem",
    [Enum.BabyState.Satisfied] = "Satisfied",
    [Enum.BabyState.Upset] = "Upset",
}

function Enum.get_state_name(state_id)
    return Enum.StateName[state_id] or tostring(state_id)
end

return Enum
