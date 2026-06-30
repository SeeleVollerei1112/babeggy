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
---@field trigger_radius Fixed
---@field min_x Fixed
---@field max_x Fixed
---@field min_z Fixed
---@field max_z Fixed
---@field floor_y Fixed
---@field ball_ground_origin_offset Fixed
---@field arc_height_ratio Fixed
---@field arc_peak_min Fixed
---@field arc_peak_max Fixed
---@field flight_hang Fixed
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
---@field min_throw_distance Fixed
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
---@field celebrate_hold_seconds Fixed
---@field rally_max_min integer
---@field rally_max_max integer
---@field debug_draw boolean

---@class BabyRpsConfig
---@field enabled boolean
---@field dice_names string[]
---@field trigger_radius Fixed
---@field throw_duration Fixed
---@field throw_height Fixed
---@field landing_offset Fixed
---@field landing_height Fixed

---@class BabyFightDirDef
---@field dir Fixed[]
---@field label string

---@class BabyFightConfig
---@field enabled boolean
---@field engage_radius Fixed
---@field target_tolerance Fixed
---@field joystick_deadzone Fixed
---@field segment_seconds Fixed
---@field release_grace Fixed
---@field required_segments integer
---@field session_timeout Fixed
---@field directions BabyFightDirDef[]

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
---@field ball_catch_score integer

---@class BabyRoundConfig
---@field duration_seconds integer

---@class BabyDifficultyConfig
---@field satisfy_per_chaos_level integer
---@field max_chaos_level integer

---@class BabyNeedDef
---@field id string
---@field resolver "equipment"|"facility"|"ball_rally"|"rps"|"fight"
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
---@field rps BabyRpsConfig
---@field fight BabyFightConfig
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
    -- 触发半径：宝宝持「玩沙滩球」需求且沙滩球(处于自由静止状态)落在此半径内才开顶球。
    -- 因为宝宝平时几乎不位移、球又是单一定点物体，默认给到“整屋”尺度(≈场地对角线)，
    -- 等价于“需求驱动 + 球在场上可用即触发”，球随后会被吸到发球宝宝头顶。
    -- 若日后让宝宝可走动、或想做成“玩家把球抱到宝宝身边才触发”，把它调小即可。
    trigger_radius = 4.0,

    -- “方块-可变形53”的 AABB 为 X[-166.579,-97.297]、Z[-0.068,55.932]。
    -- 这里四边内缩 3 单位，包含球半径和玩家站位余量。
    min_x = -163.579,
    max_x = -100.297,
    min_z = 2.932,
    max_z = 52.932,
    floor_y = 2.384,
    ball_ground_origin_offset = 0.45,

    -- 运动学参数化弧线（见 BallRallyService._drive_ball_kinematic）：弧高与时长解耦。
    -- 弧高随本次水平投掷距离自动缩放（远→高、近→低，避免“飞很远却很平”或“近距离高高抛起”的违和）：
    --   peak = clamp(arc_height_ratio * 水平距离, arc_peak_min, arc_peak_max)。
    arc_height_ratio = 0.3,
    arc_peak_min = 2.5,
    arc_peak_max = 11.0,
    -- flight_hang：空中“两端快、中间慢”的程度，0=匀速，1=顶点近乎悬停；越大顶点停留感越强、越好对接球时机。
    -- 调小 → 中段更快（用户反馈“中间太慢”）。
    flight_hang = 0.4,
    initial_delay = 1.5,
    hold_seconds = 1.0,
    release_timeout = 0.8,
    flight_time_min = 3.0,
    flight_time_max = 4.0,
    return_time_min = 2.5,
    return_time_max = 3.5,
    max_horizontal_speed = 11.0,
    target_jitter_min = 5.0,
    target_jitter_max = 12.0,
    -- 落点离发球宝宝的最小水平距离：太近的投球看起来很怪，低于此值会被沿方向推远。
    min_throw_distance = 12.0,
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
    catch_height = 1.5,
    catch_radius = 2.0,
    serve_ball_height = 1.5,
    marker_half_size = 1.2,
    -- 落点仍使用内缩安全区；飞行时允许举球挂点略微越过安全线，但不会越出真实地板。
    boundary_tolerance = 2.0,
    indicator_sfx_key = 20678,
    indicator_sfx_scale = 1.0,
    -- 一局顶球的“回合上限”：玩家成功顶到这么多次即算完成（满分结束）；中途漏接则提前结束（按已顶次数计分）。
    -- 每局在 [min,max] 间随机，给点变化。
    rally_max_min = 4,
    rally_max_max = 5,
    -- 顶满收尾时，宝宝把球举到头顶庆祝多少秒后再落球结算。
    celebrate_hold_seconds = 3.0,
    debug_draw = false,
}

Config.rps = {
    enabled = true,
    dice_names = { "手势骰子3", "手势骰子2" },
    -- 任意一个骰子到宝宝身边即可触发宝宝举起；玩家举另一个时也要进入同一范围。
    trigger_radius = 3.0,
    throw_duration = 1.8,
    throw_height = 4.0,
    landing_offset = 0.8,
    -- 骰子约 2x2x2，枢轴在底面；随机侧面朝上时需先把枢轴抬高再恢复重力。
    landing_height = 1.1,
}

Config.fight = {
    enabled = true,
    -- 玩家走进此水平半径内即可对好斗宝宝「拉架」，并被定身（禁止走动 buff）以专心转轮盘。
    engage_radius = 3.0,
    -- 轮盘方向与当前目标方向的对齐阈值：dot >= 此值算对准（≈0.6 约 53°，方便对准）。
    target_tolerance = 0.6,
    -- 轮盘输入向量模长低于此值视为「没在拨」，不计进度（避免松手也累积）。
    joystick_deadzone = 0.3,
    -- 对准目标方向持续这么久（秒）算完成一段。
    segment_seconds = 0.6,
    -- 已上场的拉架玩家连续这么久（秒）没在拨轮盘则解除定身放他走，避免被困住。
    release_grace = 1.2,
    -- 需要按顺序完成这么多段（即把轮盘依次转到几个指定方向）才把好斗宝宝拉开。
    required_segments = 4,
    -- 整场拉架的兜底超时（秒）：超时则放弃本需求、换下一个，避免卡死。
    session_timeout = 30.0,
    -- 候选目标方向（世界坐标 XZ）。按段数顺序循环取，确定性、不依赖随机。
    directions = {
        { dir = { 0, 0, 1 },  label = "前" },
        { dir = { 1, 0, 0 },  label = "右" },
        { dir = { 0, 0, -1 }, label = "后" },
        { dir = { -1, 0, 0 }, label = "左" },
    },
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
    -- 顶球玩法每成功顶回一次的额外奖励分（满足该需求另算 satisfy_score 基础分）。
    -- “接的越多，加的分越多”：总分 = satisfy_score + 成功顶球次数 * ball_catch_score。
    ball_catch_score = 5,
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
        -- 顶球玩法需求：由 BallRallyService 扫描接管（宝宝持此需求且场上有可用沙滩球即开局）。
        -- resolver = "ball_rally" 不走物品/设施解析：宝宝既不会去捡、玩家也不用抱去设施，
        -- 只是挂着倒计时等待顶球开局；接不到即结束并按 satisfy_score + 顶球次数 计分。
        id = "beach_ball",
        resolver = "ball_rally",
        item_name = "沙滩球",
        action_text = "顶球",
        need_text = "想要玩沙滩球",
        matched_text = "去顶球",
        satisfied_text = "玩到沙滩球了",
    },
    {
        id = "rock_paper_scissors",
        resolver = "rps",
        item_name = "手势骰子",
        action_text = "猜拳",
        need_text = "想要玩猜拳",
        matched_text = "一起举起骰子",
        satisfied_text = "猜拳完成啦",
    },
    {
        -- 好斗宝宝蛋：在原地打闹，需要玩家走近「拉架」。resolver = "fight" 由 FightService 接管，
        -- 不走物品/设施解析。玩家站进 engage_radius 会被定身（禁止走动 buff），转动轮盘
        -- 依次朝指定方向完成若干段即把宝宝拉开 → 满足。详见 FightService。
        id = "aggressive",
        resolver = "fight",
        action_text = "拉架",
        need_text = "好斗宝宝在打闹",
        matched_text = "转动轮盘拉架",
        satisfied_text = "被拉开啦",
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
