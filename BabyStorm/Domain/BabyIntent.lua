-- 行为层向移动/动画层下达的「意图」常量。
-- 行为状态只写这些意图，由 MovementSystem / AnimationSystem 在 reconcile 时执行。
-- 见 .claude/rules/baby-ai-architecture.md。
local BabyIntent = {}

---@enum BabyMoveMode
BabyIntent.MoveMode = {
    Stop = "Stop",                 -- 停在原地，不发任何移动指令
    Wander = "Wander",             -- 巡逻：MovementSystem 自行挑随机点
    MoveToTarget = "MoveToTarget", -- 走向 agent.move_target（坐标）
    PickupTarget = "PickupTarget", -- 走向并捡起 agent.pickup_target（装备）
    Carried = "Carried",           -- 被举起：引擎驱动，逻辑不主动移动
}

---@enum BabyAnimBase
BabyIntent.AnimBase = {
    Idle = "Idle",               -- 待机（引擎默认，不强制播放）
    Locomotion = "Locomotion",   -- 移动（引擎默认，不强制播放）
    Pickup = "Pickup",           -- 拾取（引擎默认动作，不强制播放）
    Cry = "Cry",                 -- 哭闹：需持续强制播放
    Happy = "Happy",             -- 开心
    CarriedPose = "CarriedPose", -- 被举起姿势（引擎驱动）
    Ride = "Ride",               -- 骑乘姿势：需持续强制播放
    Seat = "Seat",               -- 座位动作（如秋千）：需持续强制播放
}

---@enum BabyAnimOverlay
BabyIntent.AnimOverlay = {
    None = nil,
    Angry = "Angry",
    Confused = "Confused",
    Happy = "Happy",
}

return BabyIntent
