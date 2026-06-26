---AUTTO EXPORT BY EGGITOR PLUGIN, PLEASE DO NOT EDIT

---@class QuestTargetDef
---@field finishEvent string
---@field id integer
---@field triggerEvent string
---@field type integer

---@class QuestTaskDef
---@field context string
---@field id integer
---@field startEvent string
---@field targets QuestTargetDef[]

---@class QuestDef
---@field acceptEvent string
---@field failEvent string
---@field id integer
---@field rewards any[]
---@field tasks QuestTaskDef[]
---@field type integer

---@type table<string, QuestDef>
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
				context = "将宝宝蛋带到想要的物品处对准物品并放下",
				id = 2,
				startEvent = "",
				targets = {
					{
						finishEvent = "",
						id = 1,
						triggerEvent = "TASK_BABY_PICK_ITEM",
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
		},
		type = 1,
	},
}
