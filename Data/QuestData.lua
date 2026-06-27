---AUTTO EXPORT BY EGGITOR PLUGIN, PLEASE DO NOT EDIT

return {
	["新手引导"] = {
		acceptEvent = "",
		failEvent = "",
		id = 1,
		rewards = {},
		tasks = {
			{
				context = "举起宝宝蛋",
				id = 1,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_LIFT_BABY",
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
				context = "宝宝挑选物品中",
				id = 6,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_BABY_PICK_ITEM",
						type = 1,
					},
				},
			},
			{
				context = "是宝宝想要的吗?",
				id = 9,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_BABY_SATISFIED",
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
						triggerEvent = "",
						type = 1,
					},
				},
			},
		},
		type = 1,
	},
}
