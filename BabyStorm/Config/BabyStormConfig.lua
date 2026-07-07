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
---@field ball_names string[]
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
---@field wait_player_timeout Fixed
---@field pairing_fidget_interval Fixed
---@field pairing_fidget_radius Fixed
---@field throw_duration Fixed
---@field throw_height Fixed
---@field settle_min_time Fixed
---@field settle_rest_speed Fixed
---@field settle_rest_frames integer
---@field settle_ground_tolerance Fixed
---@field settle_face_up_tolerance Fixed
---@field settle_timeout Fixed
---@field baby_bonk_max integer
---@field baby_bonk_first_delay Fixed
---@field baby_bonk_interval Fixed
---@field baby_bonk_move_time Fixed
---@field baby_bonk_offset Fixed
---@field giveup_wander_min Fixed
---@field giveup_wander_max Fixed
---@field giveup_move_interval Fixed

---@class BabyCribSubType
---@field key string
---@field item_prefab integer
---@field hold_socket string|nil
---@field hold_offset Fixed[]|nil
---@field hold_scale Fixed[]|nil
---@field need_text string
---@field action_text string
---@field satisfied_text string
---@field duration_seconds Fixed
---@field complete_event string

---@class BabyCribConfig
---@field enabled boolean
---@field cabinet_pos Fixed[]
---@field cabinet_show_radius Fixed
---@field progress_show_radius Fixed
---@field poll_interval Fixed
---@field progress_max integer
---@field reset_progress_max integer
---@field reset_duration_seconds Fixed
---@field idle_tilt_seconds Fixed
---@field tilt_axis "x"|"z"
---@field tilt_degrees Fixed
---@field reset_complete_event string
---@field sub_types BabyCribSubType[]
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
---@field rps_win_score integer
---@field rps_draw_score integer
---@field rps_lose_score integer

---@class BabyRoundConfig
---@field duration_seconds integer

---@class BabyDifficultyConfig
---@field satisfy_per_chaos_level integer
---@field max_chaos_level integer

---@class BabyNeedDef
---@field id string
---@field resolver "equipment"|"facility"|"ball_rally"|"rps"
---@field item_key integer|nil
---@field item_name string|nil
---@field facility_id string|nil
---@field facility_name string|nil
---@field facility_names string[]|nil
---@field area_name string|nil
---@field contact_area_name string|nil
---@field contact_radius Fixed|nil
---@field facility_kind "swing"|"vehicle"|"swing_seat"|"crib"|nil
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
---@field seat_follow_orientation boolean|nil
---@field swing_force_magnitude Fixed|nil
---@field swing_push_dir Fixed[]|nil
---@field swing_force_interval Fixed|nil
---@field swing_max_speed Fixed|nil
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
---@field crib BabyCribConfig
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
    -- 场上可用于顶球的沙滩球集合：任一颗“自由静止”的球落在持需求宝宝的触发半径内即可开局，
    -- 就近选一颗接管。加/减球只需增删这里的名字。
    ball_names = { "沙滩球1", "沙滩球2" },
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
    -- 约 4~5 个蛋仔的距离，进一步放宽，配对更容易凑上。
    trigger_radius = 6.0,
    -- 基础交互（宝宝举起自己的骰子）就已经满足需求；猜拳配对是额外加分项，不强制玩家参与
    -- （同顶球玩法设计）。宝宝举起后这么久玩家还没能一起举稳配对骰子，直接按满足收尾。
    -- 放宽等待时长，给玩家更充裕的时间跑过来配对。
    wait_player_timeout = 25.0,
    -- 配对期间的“小步挪动”：玩家进入配对范围（靠近宝宝且举着配对骰子）后，宝宝在自身周围
    -- 小半径内随机走动 + 面向玩家转向，减少干等的 AI 生硬感；配对达成（进入就绪）即冻回原地。
    -- 半径足够小，保证宝宝始终在玩家的配对范围（trigger_radius）内、不会走开导致配对失败。
    pairing_fidget_interval = 1.2, -- 每隔多久换一个小目标点（秒，必须小数）
    pairing_fidget_radius = 0.9,   -- 小步走动半径（单位）
    -- 抛掷：原生抛掷是“沿朝向向前抛”（力是标量、无方向），做不出垂直，所以由脚本把两颗骰子
    -- 从当前握持位置纯垂直升到顶点（不加水平偏移、不人为旋转）。到达顶点后才交还物理——
    -- 这样骰子才有一段真实重力下的空中时间，可以被顶/被撞，而不是刚交还物理就已经贴地。
    throw_duration = 0.6,    -- 上抛用时（秒）：从举起处升到顶点，动作要干脆，不要慢悠悠。
    throw_height = 3.5,      -- 顶点比举起处高多少（真正的“抛多高”，不是弧线装饰）。
    -- 落地结算（轮询静止）：交还物理后等两颗骰子真正落地、最终静止才结算。
    settle_min_time = 0.4,   -- 交还物理后至少等这么久才开始判静止（先让它建立下落速度）。
    settle_rest_speed = 0.3, -- 线速度模长低于此值视为“静止”。
    settle_rest_frames = 8,  -- 连续这么多帧都静止才算落定（防抖）。
    -- 骰子卡在角色头顶/身上时速度也会趋近 0，所以静止判定还要求“骰子贴近它正下方的真实地面”。
    -- 每颗骰子各自向下取脚下地面高度（射线）做参考，骰子中心高出该地面超过此容差就视为
    -- “还没真正落地”，不计入静止帧数——从而杜绝“骰子悬在半空/卡在头顶就被判落定”。
    settle_ground_tolerance = 0.1,
    -- 落地面判定容差：静止后取“最贴近竖直”的那条骰子本地轴，其与世界竖直方向的余弦
    -- 必须 ≥ 此值才算“一个完整面朝上/贴地”，从而判定该面对应的手势。
    --   完整一面朝上 ≈ 1.0；停在棱上 ≈ 0.707；停在角上 ≈ 0.577。
    -- 低于此值（棱/角立起，平地上极罕见）则本次不判胜负、只给基础满足分。0.95 ≈ 允许 ~18° 倾斜。
    settle_face_up_tolerance = 0.95,
    settle_timeout = 8.0, -- 兜底：超过这么久强制结算，避免卡死（即使一直卡头顶也不会卡死）。
    -- 宝宝自动顶撞：玩家侧不脚本化（玩家自己跳），宝宝侧随玩家抛出自动起跳顶骰子，可以顶好几下；
    -- 第一下原地直顶，第二下起（含最后一下）都带随机偏移斜顶，保证最后一下一定会带偏移。
    baby_bonk_max = 4,            -- 宝宝最多顶几次后停手，让骰子落地。
    baby_bonk_first_delay = 0.15, -- 交还物理后多久开始第一次顶（随玩家抛出一起跳顶）。
    baby_bonk_interval = 0.6,     -- 两次顶之间的间隔（秒）。
    baby_bonk_move_time = 0.18,   -- 每次顶前朝骰子方向走位的时长（秒），制造翻面所需的偏移。
    baby_bonk_offset = 0.6,       -- 第二下起跳顶撞的随机横向偏移系数（贴边斜顶 → 空中翻滚）。
    -- 玩家超时未响应：宝宝抱着骰子闲逛一会儿（找人玩的感觉），逛够了才放下骰子按满足收尾。
    giveup_wander_min = 5.0,      -- 闲逛时长下限（秒）。
    giveup_wander_max = 10.0,     -- 闲逛时长上限（秒），实际时长在 [min,max] 间随机。
    giveup_move_interval = 2.0,   -- 每隔多久换一个随机目标点（秒），做出到处走动的效果。
}

Config.crib = {
    enabled = true,
    -- 柜子场景 UI 绑定到该单位；坐标用于玩家距离判定。
    cabinet_unit_name = "木制边柜3",
    cabinet_pos = { -157.339, 2.555, 6.502 },
    cabinet_ui_offset = { 0, 1.5, 0 },
    cabinet_show_radius = 4.0,
    progress_show_radius = 4.0,
    poll_interval = 0.2,
    progress_max = 100,
    reset_progress_max = 100,
    reset_duration_seconds = 3.0,
    idle_tilt_seconds = 25.0,
    tilt_axis = "z",
    tilt_degrees = 22.0,
    reset_complete_event = "BABY_CRIB_RESET_COMPLETE",
    sub_types = {
        {
            key = "diaper",
            item_prefab = (Prefab.unit and Prefab.unit["尿布"]) or 1073745932,
            hold_socket = "socket_head",
            hold_offset = { 0, 0.8, 0 },
            hold_scale = { 0.3, 0.3, 0.3 },
            need_text = "要换尿布啦",
            action_text = "换尿布",
            satisfied_text = "换好尿布啦~",
            duration_seconds = 8.0,
            complete_event = "BABY_CRIB_DIAPER_COMPLETE",
        },
        {
            key = "tissue",
            item_prefab = (Prefab.unit and Prefab.unit["纸巾"]) or 1073737845,
            hold_socket = "socket_head",
            hold_offset = { 0, 0.8, 0 },
            hold_scale = { 0.3, 0.3, 0.3 },
            need_text = "要擦屁屁啦",
            action_text = "擦屁股",
            satisfied_text = "擦干净啦~",
            duration_seconds = 5.0,
            complete_event = "BABY_CRIB_TISSUE_COMPLETE",
        },
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
    -- 猜拳玩法额外加分：双方一起跑完配对+抛骰+顶撞并落地判出胜负后，按“玩家视角”的输赢分档追加
    -- （基础满足分另算）。玩家未响应的独自满足、或骰子没干净落面无法判胜负时，都只给基础满足分、
    -- 不追加这份分（见 BabyAgent:finish_rps / RpsService:_finish_settle / _finish_solo_satisfy）。
    rps_win_score = 8,  -- 玩家赢宝宝：满额加分
    rps_draw_score = 4, -- 平局：一半
    rps_lose_score = 0, -- 玩家输：不加分
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
        -- 秋千：把宝宝“绑定”到会摆动的座椅上（像绑滑板那样每帧硬粘 + 跟随朝向），
        -- 再周期性给座椅施力让它越摆越高。（旧版组件自摆的 winter_swing 已废弃删除，
        -- 现只保留本套 swing_seat。）
        id = "swing_seat",
        resolver = "facility",
        facility_kind = "swing_seat",
        facility_id = "swing_seat",
        -- 两个可互换的座椅：玩家把宝宝抱到任一座椅放下即触发，就近选空闲的那个。
        facility_names = { "秋千座椅1", "秋千座椅2" },
        contact_radius = 3.0, -- 放下宝宝时距座椅多近算“坐上”（XZ 水平半径）
        action_text = "荡秋千",
        need_text = "想要荡秋千",
        matched_text = "去荡秋千",
        satisfied_text = "荡完秋千了",
        interact_begin_event = "BABY_SWING_SEAT_BEGIN",
        interact_end_event = "BABY_SWING_SEAT_END",
        interact_min_seconds = 15,
        interact_max_seconds = 30,
        -- 绑定：每帧把宝宝硬粘到座椅座位点，并跟随座椅实时朝向一起前后倾（复用 _seat_agent/_sync_seat）。
        seat_offset = { 0, 0.5, 0 },    -- 宝宝相对座椅的座位偏移（按座椅模型微调）
        seat_rotation = { 0, 90, 0 },   -- 在座椅朝向上叠加的固定角度偏移（度）
        seat_follow_orientation = true, -- true=跟随座椅实时朝向（宝宝跟着秋千摆）；false=用固定 seat_rotation
        seat_anim_id = 21013,           -- 坐姿动画（复用秋千坐姿 AnimKey）
        -- 摆动：每隔 swing_force_interval 给座椅施一次力。顺着座椅当前运动方向推（“泵”能量），
        -- 自然越摆越高、不依赖相位；接近静止时按 swing_push_dir 起摆；速度超过 swing_max_speed 不再加力。
        swing_force_magnitude = 12.0,
        swing_push_dir = { 1, 0, 0 }, -- 起摆方向（世界坐标，按秋千实际摆动轴改成 x 或 z）
        swing_force_interval = 0.2,   -- 施力间隔（秒，必须小数）
        swing_max_speed = 4.0,        -- 摆动水平速度上限，超过则本拍不加力，避免越摆越飞
    },
    {
        -- 婴儿床：玩家把宝宝抱到床上放下 → 躺姿(动作49)绑床 → 随机弹出「换尿布/擦屁股」子需求。
        -- 玩家去尿布柜取对应道具、走到床边长按 progress_btn 换洗完成。整个玩法由 CribService 驱动，
        -- 这里只声明它是一条 crib 型设施需求（放下即触发、就近选空闲的一张床）。
        id = "crib_care",
        resolver = "facility",
        facility_kind = "crib",
        facility_id = "crib",
        -- 两张可互换的婴儿床：抱到任一张放下即触发，就近选空闲（未歪、未被占用）的那张。
        facility_names = { "儿童单人床0", "儿童单人床1" },
        contact_radius = 3.0, -- 放下宝宝时距床多近算“放上床”（XZ 水平半径）
        action_text = "上婴儿床",
        need_text = "想上婴儿床",
        matched_text = "抱上婴儿床",
        satisfied_text = "舒服多啦~",
        interact_begin_event = "BABY_CRIB_BEGIN",
        interact_end_event = "BABY_CRIB_END",
        -- 躺床姿势：复用 _seat_agent 每帧硬粘到床面 + force_play 保持躺姿动作。
        seat_offset = { 0, 0.4, 0 },     -- 宝宝相对床的躺位偏移（按床模型微调，绑到床“底面中心”上方）
        seat_rotation = { 0, 0, 0 },     -- 在床朝向上叠加的固定角度偏移（度）；宝宝朝向与床一致
        seat_follow_orientation = true,  -- true=朝向跟随床（与床方向一致），可叠加 seat_rotation
        seat_anim_id = 49,               -- 躺姿动作 id（不循环由 force_play 保持）；若 49 压不住待机可换成躺姿 AnimKey
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
