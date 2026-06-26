local bret = require 'behavior.behavior_ret'

---@class BehaviorTreeActionNode
---@field name string
---@field type string
---@field desc string
---@field run fun(node:any, env:table):integer

---@type BehaviorTreeActionNode
local M = {
	name = 'ExampleAction',
	type = 'Action',
	desc = '范例描述',
}

---@param node any
---@param env table
---@return integer
function M.run(node, env)
	local owner = env.owner
	return bret.SUCCESS
end

return M
