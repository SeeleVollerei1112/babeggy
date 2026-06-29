local Prefab = require("Data.Prefab")

---@class BabyArenaConfig
---@field area_name string
---@field ground_ray_up Fixed
---@field ground_ray_down Fixed
---@field fallback_min_x Fixed
---@field fallback_max_x Fixed
---@field fallback_min_z Fixed
---@field fallback_max_z Fixed
---@field fallback_y Fixed

---@class BabyBallRallyConfig
---@field enabled boolean
---@field ball_name string
---@field server_baby_index integer
---@field min_x Fixed
---@field max_x Fixed
---@field min_z Fixed
---@field max_z Fixed
---@field floor_y Fixed
---@field ball_ground_origin_offset Fixed
---@field gravity Fixed
---@field initial_delay Fixed
---@field hold_seconds Fixed
---@field release_timeout Fixed
---@field flight_time_min Fixed
---@field flight_time_max Fixed
---@field return_time_min Fixed
---@field return_time_max Fixed
---@field max_horizontal_speed Fixed
---@field target_jitter_min Fixed
---@field target_jitter_max Fixed
---@field jump_prompt_lead Fixed
---@field jump_hit_window Fixed
---@field miss_grace Fixed
---@field player_catch_radius Fixed
---@field player_catch_height Fixed
---@field player_box_margin Fixed
---@field catch_height Fixed
---@field catch_radius Fixed
---@field serve_ball_height Fixed
---@field marker_half_size Fixed
---@field boundary_tolerance Fixed
---@field indicator_sfx_key integer
---@field indicator_sfx_scale Fixed
---@field rally_round_min integer
---@field rally_round_max integer
---@field baby_jump_lead Fixed
---@field debug_draw boolean

---@class BabyRuntimeConfig
---@field prefab_id integer
---@field count integer
---@field patrol_interval Fixed
---@field patrol_threshold Fixed
---@field ai_move_threshold Fixed
---@field contact_radius Fixed
---@field item_pickup_radius Fixed
---@field item_scan_interval Fixed
---@field drop_move_hold_seconds Fixed
---@field pickup_check_interval Fixed
---@field pickup_timeout Fixed
---@field pickup_move_speed_ratio Fixed
---@field satisfied_react_time Fixed
---@field need_timeout_min_seconds integer
---@field need_timeout_max_seconds integer
---@field timeout_action_id integer
---@field timeout_action_seconds integer
---@field timeout_reject_lift_chance_percent integer
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
---@field contact_area_name string|nil
---@field contact_radius Fixed|nil
---@field facility_kind "swing"|"vehicle"|nil
---@field vehicle_drive_mode "kinematic"|"physics"|"player_bound"|nil
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
---@field vehicle_onboard_radius Fixed|nil
---@field vehicle_follow_offset Fixed[]|nil
---@field vehicle_follow_rotation Fixed[]|nil
---@field vehicle_passenger_model integer|nil
---@field vehicle_passenger_socket string|nil
---@field vehicle_passenger_offset Fixed[]|nil
---@field vehicle_passenger_rotation Fixed[]|nil
---@field vehicle_passenger_scale Fixed[]|nil
---@field vehicle_passenger_drop_offset Fixed[]|nil
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
---@field ball_rally BabyBallRallyConfig
---@field needs BabyNeedDef[]

---@type BabyStormConfig
local Config = {}

Config.arena = {
    area_name = "tutorial_area",
    ground_ray_up = 50.0,
    ground_ray_down = 100.0,
    -- “方块-可变形53”内缩 3 单位后的安全区。即使触发区尚未创建，
    -- 宝宝也能在实际地板范围内生成，后续可无缝切回 tutorial_area。
    fallback_min_x = -163.579,
    fallback_max_x = -100.297,
    fallback_min_z = 2.932,
    fallback_max_z = 52.932,
    fallback_y = 2.6,
}

Config.ball_rally = {
    enabled = true,
    ball_name = "沙滩球1",
    server_baby_index = 1,

    -- “方块-可变形53”的 AABB 为 X[-166.579,-97.297]、Z[-0.068,55.932]。
    -- 这里四边内缩 3 单位，包含球半径和玩家站位余量。
    min_x = -163.579,
    max_x = -100.297,
    min_z = 2.932,
    max_z = 52.932,
    floor_y = 2.384,
    ball_ground_origin_offset = 0.45,

    -- 运动学弧线高度参数：球由脚本按解析抛物线驱动（见 BallRallyService._drive_ball_kinematic），
    -- 不再依赖引擎真实重力，落点精确等于标识点。此值只决定弧线高低，纯手感，可自由调。
    gravity = 17.0,
    initial_delay = 1.5,
    hold_seconds = 1.0,
    release_timeout = 0.8,
    flight_time_min = 2.8,
    flight_time_max = 3.6,
    return_time_min = 2.0,
    return_time_max = 2.8,
    max_horizontal_speed = 11.0,
    target_jitter_min = 5.0,
    target_jitter_max = 12.0,
    jump_prompt_lead = 1.2,
    -- 玩家起跳后这么久内都算“在起跳窗口”，期间只要球落入落点盒就顶回。
    jump_hit_window = 0.9,
    miss_grace = 1.0,
    -- 玩家侧“落点盒”：刻意比预警标识(marker_half_size)大，宽容接球。
    --   判定 = 球下落进入盒(水平半径 player_catch_radius + 高度 player_catch_height)
    --          且玩家站在盒附近(半径 + player_box_margin) + 处于起跳窗口。
    -- 不再依赖球与玩家的物理碰撞，从根本上规避“落点漂移导致接不到/不匹配”。
    player_catch_radius = 3.0,
    -- 天井判定：球下落到 floor_y + 此值以下即可触发（不是窄区间，不会因 10Hz 漏帧错过）。
    -- 取略高值，保证下落终盘(速度快)也有 ≥1 个 tick 的判定机会。
    player_catch_height = 3.5,
    player_box_margin = 1.5,
    baby_jump_lead = 0.55,
    catch_height = 1.5,
    catch_radius = 2.0,
    serve_ball_height = 1.5,
    marker_half_size = 1.2,
    -- 落点仍使用内缩安全区；飞行时允许举球挂点略微越过安全线，但不会越出真实地板。
    boundary_tolerance = 2.0,
    indicator_sfx_key = 20678,
    indicator_sfx_scale = 1.0,
    rally_round_min = 3,
    rally_round_max = 4,
    debug_draw = false,
}

Config.baby = {
    prefab_id = (Prefab.character and Prefab.character["宝宝蛋"]) or 1073741937,
    count = 3,
    patrol_interval = 4.0,
    patrol_threshold = 4.0,
    ai_move_threshold = 0.5,
    -- 设施接触和物品强制拾取兜底距离；不要与设施巡游区域混用。
    contact_radius = 1.5,
    -- 物品允许在稍远处触发 AI 走近拾取；设施仍只使用 contact_radius。
    item_pickup_radius = 3.0,
    item_scan_interval = 0.5, -- 空闲/巡逻时多久就近扫描一次当前需求的物品（秒，必须小数）
    drop_move_hold_seconds = 1.0,
    pickup_check_interval = 0.25,
    pickup_timeout = 5.0,
    pickup_move_speed_ratio = 2.0,
    satisfied_react_time = 3.0,
    need_timeout_min_seconds = 20,
    need_timeout_max_seconds = 30,
    timeout_action_id = 23,
    timeout_action_seconds = 10,
    timeout_reject_lift_chance_percent = 30,
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
        action_text = "奶昔",
        need_text = "想要喝奶昔",
        matched_text = "去喝奶昔",
        satisfied_text = "喝到奶昔了",
    },
    {
        id = "icecream",
        resolver = "equipment",
        item_key = (Prefab.equipment and Prefab.equipment["冰激凌_自定义"]) or 1073786889,
        item_name = "冰淇淋",
        action_text = "冰淇淋",
        need_text = "想要吃冰淇淋",
        matched_text = "去吃冰淇淋",
        satisfied_text = "吃到冰淇淋了",
    },
    {
        id = "cake",
        resolver = "equipment",
        item_key = (Prefab.equipment and Prefab.equipment["提拉米苏_自定义"]) or 1073795131,
        item_name = "提拉米苏",
        action_text = "蛋糕",
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
        contact_area_name = "通用触发区域0",
        action_text = "荡秋千",
        need_text = "想要荡秋千",
        matched_text = "去荡秋千",
        satisfied_text = "荡完秋千了",
        interact_begin_event = "BABY_SWING_INTERACT_BEGIN",
        interact_end_event = "BABY_SWING_INTERACT_END",
        interact_min_seconds = 20,
        interact_max_seconds = 60,
        seat_offset = { 1, 1.2, 1 }, -- 临时可见偏移，验证绑定后改回真实座位偏移（原 { 1, -4, 1 } Y 为负会沉到地下）
        seat_rotation = { 0, -180, 0 },
        seat_anim_id = 21013,
    },
    {
        id = "baby_car",
        resolver = "facility",
        facility_kind = "vehicle",
        facility_id = "baby_car",
        facility_name = "雪地滑板0", -- TODO: 改成场景里载具单位的实际名字
        area_name = "tutorial_area", -- TODO: 改成限定小车巡游范围的触发区名字（可与秋千区不同）
        contact_radius = 3.0, -- 仅控制滑板的 XZ 水平交互半径，不影响其他设施和物品
        action_text = "滑滑板",
        need_text = "想要滑滑板",
        matched_text = "去滑滑板",
        satisfied_text = "滑完了",
        interact_begin_event = "BABY_VEHICLE_RIDE_BEGIN",
        interact_end_event = "BABY_VEHICLE_RIDE_END",
        interact_min_seconds = 20,
        interact_max_seconds = 40,
        -- player_bound：玩家上板后，把滑板单位反向绑定到宝宝挂点上
        --   引擎限制：只能把模型/单位挂到宝宝的挂点上，不能把宝宝绑到玩家/物体身上，
        --   所以方向是「滑板 -> 宝宝 socket_origin」，再用偏移把滑板摆到宝宝头顶。
        -- kinematic：用 set_position 挪车+粘宝宝，宝宝自己骑滑板在区域里巡游（当前采用）
        -- physics：try_enter_vehicle + VehicleComp 驱动，仅当该单位是真·可骑乘载具时才用
        vehicle_drive_mode = "kinematic",
        -- 轮询判定“玩家站在板上”的水平半径（单位）。板被骑时带着玩家一起跑，
        -- 半径要小，只圈住真正站在板上的人、不误圈旁边路过的玩家。按板尺寸微调。
        vehicle_onboard_radius = 1.0,
        -- 跟随时宝宝相对玩家的位置/朝向偏移（上板期间宝宝与玩家/滑板的碰撞已关闭，不会顶歪板）。
        -- vehicle_follow_offset：玩家“局部坐标系”下的偏移，会跟着玩家朝向走。Y 抬高、X/Z 侧移。
        -- 朝向：宝宝直接同步“滑板本体”的完整朝向，跟着滑板一起倾斜（pitch/roll），贴在板上。
        -- vehicle_follow_rotation：在滑板朝向上叠加的固定角度偏移(度, pitch/yaw/roll)，默认 {0,0,0}=和滑板一致。
        vehicle_follow_offset = { 0, 1.0, 0 },
        vehicle_follow_rotation = { 0, 0, 0 },
        -- 玩家上板后宝宝跟随玩家滑行。装饰滑板模型（可选）：
        --   填了 vehicle_passenger_model（滑板模型 UnitKey）就把它挂到宝宝身上当装饰；
        --   留空则只跟随、不挂模型。绝不要绑“玩家正踩着的真机关”，否则会把板抢走、瞬间下板。
        vehicle_passenger_model = nil,              -- TODO: 填装饰滑板模型 UnitKey；nil = 只跟随不挂模型
        vehicle_passenger_socket = "socket_origin", -- 装饰滑板挂到宝宝的底面中心点挂点
        vehicle_passenger_offset = { 0, 0, 0 },     -- 装饰滑板相对挂点的偏移（按模型微调）
        vehicle_passenger_rotation = { 0, 0, 0 },   -- 装饰滑板朝向（角度，按需微调）
        vehicle_passenger_scale = { 1, 1, 1 },      -- 装饰滑板缩放
        vehicle_passenger_drop_offset = { 1.2, 0.2, 0 },
        vehicle_speed = 3.0,                        -- 运动学模式下的最大移动速度（单位/秒）
        vehicle_seat_offset = { 0, 0.2, 0 },        -- 宝宝相对载具的座位偏移（让宝宝坐在车上方）
        vehicle_reach_radius = 2.0,                 -- 距目标多近算到达，然后换下一个随机点
        vehicle_turn_speed = 3.0,                   -- 转向角速度上限（弧度/秒）：越大转弯越快、越小越平缓
        vehicle_accel = 6.0,                        -- 加/减速度（单位/秒²）：起步加速、到点/转弯缓停的快慢
        vehicle_arrive_radius = 5.0,                -- 进入此半径开始线性减速，实现到点缓停
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
