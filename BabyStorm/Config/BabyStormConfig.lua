local Prefab = require("Data.Prefab")

---@class BabyArenaConfig
---@field area_name string
---@field ground_ray_up Fixed
---@field ground_ray_down Fixed

---@class BabyRuntimeConfig
---@field prefab_id integer
---@field count integer
---@field patrol_interval Fixed
---@field patrol_threshold Fixed
---@field ai_move_threshold Fixed
---@field pickup_radius Fixed
---@field pickup_check_interval Fixed
---@field pickup_timeout Fixed
---@field pickup_move_speed_ratio Fixed
---@field satisfied_react_time Fixed
---@field need_timeout_min_seconds integer
---@field need_timeout_max_seconds integer
---@field timeout_action_id integer
---@field timeout_action_seconds integer
---@field bubble_show_seconds Fixed
---@field reject_hold_delay Fixed
---@field reject_throw_delay Fixed
---@field status_height Fixed

---@class BabyScoringConfig
---@field satisfy_score integer
---@field wrong_item_penalty integer

---@class BabyRoundConfig
---@field duration_seconds integer

---@class BabyDifficultyConfig
---@field satisfy_per_chaos_level integer
---@field max_chaos_level integer

---@class BabyNeedDef
---@field id string
---@field resolver "equipment"|"facility"
---@field item_key integer|nil
---@field item_name string|nil
---@field facility_id string|nil
---@field facility_name string|nil
---@field area_name string|nil
---@field action_text string
---@field need_text string
---@field matched_text string
---@field satisfied_text string
---@field interact_begin_event string|nil
---@field interact_end_event string|nil
---@field interact_min_seconds integer|nil
---@field interact_max_seconds integer|nil
---@field seat_offset Fixed[]|nil
---@field seat_rotation Fixed[]|nil
---@field seat_socket integer|nil
---@field seat_anim_id integer|nil
---@field need_timeout_min_seconds integer|nil
---@field need_timeout_max_seconds integer|nil
---@field timeout_action_seconds integer|nil

---@class BabyStormConfig
---@field arena BabyArenaConfig
---@field baby BabyRuntimeConfig
---@field scoring BabyScoringConfig
---@field round BabyRoundConfig
---@field difficulty BabyDifficultyConfig
---@field needs BabyNeedDef[]

---@type BabyStormConfig
local Config = {}

Config.arena = {
    area_name = "tutorial_area",
    ground_ray_up = 50.0,
    ground_ray_down = 100.0,
}

Config.baby = {
    prefab_id = (Prefab.character and Prefab.character["宝宝蛋"]) or 1073741937,
    count = 3,
    patrol_interval = 4.0,
    patrol_threshold = 4.0,
    ai_move_threshold = 0.5,
    pickup_radius = 4.0,
    pickup_check_interval = 0.25,
    pickup_timeout = 5.0,
    pickup_move_speed_ratio = 2.0,
    satisfied_react_time = 3.0,
    need_timeout_min_seconds = 20,
    need_timeout_max_seconds = 30,
    timeout_action_id = 23,
    timeout_action_seconds = 10,
    bubble_show_seconds = 999999.0,
    reject_hold_delay = 1.0, -- 捡到错误物品后，拿在手上多久再丢出去（秒）；call_delay_time 需要 Fixed，必须写成小数
    reject_throw_delay = 2.0, -- 丢掉错误物品到表现不满意之间的间隔（秒）；call_delay_time 需要 Fixed，必须写成小数
    status_height = 1.5,
}

Config.scoring = {
    satisfy_score = 10,
    wrong_item_penalty = 0,
}

Config.round = {
    duration_seconds = 180,
}

Config.difficulty = {
    satisfy_per_chaos_level = 5,
    max_chaos_level = 5,
}

Config.needs = {
    {
        id = "milkshake",
        resolver = "equipment",
        item_key = (Prefab.equipment and Prefab.equipment["草莓奶昔_自定义"]) or 1073774699,
        item_name = "草莓奶昔",
        action_text = "喝奶昔",
        need_text = "想要喝奶昔",
        matched_text = "去喝奶昔",
        satisfied_text = "喝到奶昔了",
    },
    {
        id = "icecream",
        resolver = "equipment",
        item_key = (Prefab.equipment and Prefab.equipment["冰激凌_自定义"]) or 1073786889,
        item_name = "冰淇淋",
        action_text = "吃冰淇淋",
        need_text = "想要吃冰淇淋",
        matched_text = "去吃冰淇淋",
        satisfied_text = "吃到冰淇淋了",
    },
    {
        id = "cake",
        resolver = "equipment",
        item_key = (Prefab.equipment and Prefab.equipment["提拉米苏_自定义"]) or 1073795131,
        item_name = "提拉米苏",
        action_text = "吃蛋糕",
        need_text = "想要吃蛋糕",
        matched_text = "去吃蛋糕",
        satisfied_text = "吃到蛋糕了",
    },
    {
        id = "swing",
        resolver = "facility",
        facility_id = "winter_swing",
        facility_name = "冬日序曲秋千0",
        area_name = "通用触发区域0",
        action_text = "荡秋千",
        need_text = "想要荡秋千",
        matched_text = "去荡秋千",
        satisfied_text = "荡完秋千了",
        interact_begin_event = "BABY_SWING_INTERACT_BEGIN",
        interact_end_event = "BABY_SWING_INTERACT_END",
        interact_min_seconds = 20,
        interact_max_seconds = 60,
        seat_offset = { 1, 1.2, 1 }, -- 临时可见偏移，验证绑定后改回真实座位偏移（原 { 1, -4, 1 } Y 为负会沉到地下）
        seat_rotation = { 0, -90, 0 },
        seat_anim_id = 21013,
    },
}

return Config



