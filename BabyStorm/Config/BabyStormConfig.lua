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
---@field item_scan_interval Fixed
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
---@field facility_kind "swing"|"vehicle"|nil
---@field vehicle_drive_mode "kinematic"|"physics"|nil
---@field vehicle_speed Fixed|nil
---@field vehicle_seat_offset Fixed[]|nil
---@field vehicle_enter_delay Fixed|nil
---@field vehicle_move_segment Fixed|nil
---@field vehicle_reach_radius Fixed|nil
---@field vehicle_turn_speed Fixed|nil
---@field vehicle_accel Fixed|nil
---@field vehicle_arrive_radius Fixed|nil
---@field vehicle_ride_anim_key integer|nil
---@field vehicle_ride_anim_id integer|nil
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
    item_scan_interval = 0.5, -- 空闲/巡逻时多久就近扫描一次当前需求的物品（秒，必须小数）
    pickup_check_interval = 0.25,
    pickup_timeout = 5.0,
    pickup_move_speed_ratio = 2.0,
    satisfied_react_time = 3.0,
    need_timeout_min_seconds = 20,
    need_timeout_max_seconds = 30,
    timeout_action_id = 23,
    timeout_action_seconds = 10,
    bubble_show_seconds = 999999.0,
    reject_hold_delay = 1.0,  -- 捡到错误物品后，拿在手上多久再丢出去（秒）；call_delay_time 需要 Fixed，必须写成小数
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
    {
        id = "baby_car",
        resolver = "facility",
        facility_kind = "vehicle",
        facility_id = "baby_car",
        facility_name = "雪地滑板0", -- TODO: 改成场景里载具单位的实际名字
        area_name = "tutorial_area", -- TODO: 改成限定小车巡游范围的触发区名字（可与秋千区不同）
        action_text = "开小车",
        need_text = "想要开小车",
        matched_text = "去开小车",
        satisfied_text = "开够小车了",
        interact_begin_event = "BABY_VEHICLE_RIDE_BEGIN",
        interact_end_event = "BABY_VEHICLE_RIDE_END",
        interact_min_seconds = 20,
        interact_max_seconds = 40,
        -- kinematic：用 set_position 挪车+粘宝宝，适配“雪地滑板”这类非可骑乘单位（默认，立即可用）
        -- physics：try_enter_vehicle + VehicleComp 驱动，仅当该单位是真·可骑乘载具时才用
        vehicle_drive_mode = "kinematic",
        vehicle_speed = 3.0,                 -- 运动学模式下的最大移动速度（单位/秒）
        vehicle_seat_offset = { 0, 0.5, 0 }, -- 宝宝相对载具的座位偏移（让宝宝坐在车上方）
        vehicle_reach_radius = 2.0,          -- 距目标多近算到达，然后换下一个随机点
        vehicle_turn_speed = 3.0,            -- 转向角速度上限（弧度/秒）：越大转弯越快、越小越平缓
        vehicle_accel = 6.0,                 -- 加/减速度（单位/秒²）：起步加速、到点/转弯缓停的快慢
        vehicle_arrive_radius = 5.0,         -- 进入此半径开始线性减速，实现到点缓停
        -- 骑行动作两条路（优先用 anim_key）：
        --   vehicle_ride_anim_key：AnimKey（座位动画那种大编号，如秋千 21013），走 force_play
        --     强制播放，能长期保持动态骑行姿势、不被待机顶掉（首选，需要从编辑器取到骑行 AnimKey）
        --   vehicle_ride_anim_id：全身动作预设（小编号，如哭闹 23、49），走 play_body_anim_by_id，
        --     引擎约 1 秒后会强制切回待机、无法长期保持，仅作占位
        vehicle_ride_anim_key = nil, -- TODO: 填入宝宝骑滑板姿势的 AnimKey
        vehicle_ride_anim_id = 49,   -- 全身动作预设（占位，无法长期保持）
        vehicle_enter_delay = 0.4,   -- physics 模式：上车后多久开始巡游（秒，必须小数）
        vehicle_move_segment = 0.3,  -- physics 模式：每隔多久重新对准方向（秒，必须小数）
    },
}

return Config
