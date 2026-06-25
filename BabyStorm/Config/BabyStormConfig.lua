local Prefab = require("Data.Prefab")

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

Config.scene_ui = {
    reaction_canvas = Prefab.scene_eui and Prefab.scene_eui.reaction_bubble_canvas,
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
}

return Config
