---AUTTO EXPORT BY EGGITOR PLUGIN, PLEASE DO NOT EDIT

return {
	["新手引导"] = {
		acceptEvent = "",
		failEvent = "",
		id = 1,
		rewards = {},
		tasks = {
			{
				context = "举起想要吃东西的宝宝蛋",
				id = 1,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_LIFT_BABY_WANTS_ITEM",
						type = 1,
					},
				},
			},
			{
				context = "将宝宝蛋带到想要的物品处对准物品并放下",
				id = 2,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 4,
						triggerEvent = "TASK_DELIVER_BABY_TO_ITEM",
						type = 1,
					},
				},
			},
			{
				context = "是宝宝想要的物品吗?",
				id = 9,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_BABY_SATISFIED_ITEM",
						type = 1,
					},
					{
						finishEvent = "",
						id = 2,
						triggerEvent = "TASK_BABY_WRONG_ITEM",
						type = 1,
					},
				},
			},
			{
				context = "不是宝宝想要的物品",
				id = 26,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_BABY_NOT_WANTED_ITEM",
						type = 1,
					},
				},
			},
			{
				context = "宝宝生气了(有几率不能抱起,需要带物品给宝宝)",
				id = 17,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_DELIVER_ITEM_TO_BABY",
						type = 1,
					},
				},
			},
			{
				context = "宝宝很开心",
				id = 20,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_BABY_HAPPY",
						type = 1,
					},
				},
			},
			{
				context = "举起想要去玩的宝宝蛋",
				id = 25,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_LIFT_BABY_WANTS_FACILITY",
						type = 1,
					},
				},
			},
			{
				context = "将宝宝蛋带到想要去的地方并放下",
				id = 15,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_DELIVER_BABY_TO_FACILITY",
						type = 1,
					},
				},
			},
			{
				context = "是宝宝想要去玩的地方吗?",
				id = 29,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_BABY_SATISFIED_FACILITY",
						type = 1,
					},
				},
			},
		},
		type = 1,
	},
}
