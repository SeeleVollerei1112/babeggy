local bret = require 'behavior.behavior_ret'

local M = {
	name = 'ExampleAction',
	type = 'Action',
	desc = '范例描述',
}

function M.run(node, env)
	local owner = env.owner
	return bret.SUCCESS
end

return M
		