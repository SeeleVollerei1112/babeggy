-- Lua调试插件
-- ---example
-- --@export_plugin
-- --@style style_type[插件样式]
-- --@desc func_desc[方法描述]
-- --@param var_name[变量名] var_type[变量类型] var_desc[变量描述]
-- --@param.var_name param_extra_data_key[变量额外数据key] param_extra_data_value[变量额外数据value]
-- --@return return_type[返回值类型]
-- function func_name(var_name)
-- 	func_body
-- end
-- 说明：
-- 1、插件样式
-- 当前支持样式: button
-- button 按钮 点击后执行方法
-- e.g.
-- ---@style button
-- 2、变量类型
-- 当前支持类型: integer, number, boolean, string, Vector3, RoleID, Color
-- 3、变量额外数据key
-- 当前支持key: style, enum
-- 3.1 style
-- ui_type value 支持 textField, dropDown, multiDropDown
-- e.g. 设置参数样式为文本框
-- ---@param unit_desc string 组件说明
-- ---@param.unit_desc style textField
-- e.g. 设置参数样式为下拉枚举
-- ---@param role_id RoleID 玩家ID
-- ---@param.role_id style dropDown
-- ---@param.role_id enum [(1, "玩家1"), (2, "玩家2")]
-- e.g. 设置参数样式为多选下拉枚举
-- ---@param number[] 生效状态
-- ---@param.effect_state style multiDropDown
-- ---@param.effect_state enum [(1, "状态1"), (2, "状态2")]
-- 3.2 enum
-- 配合 dropDown 使用, 设置枚举选项


---@export_plugin
---@style button
---@desc 设置蛋仔位置
---@param role_id RoleID 玩家ID
---@param position Vector3 位置
function SetPosition(role_id, position)
	local role = GameAPI.get_role(role_id)
	if not role then
		return
	end
	local unit = role.get_ctrl_unit()
	if not unit then
		return
	end
	unit.set_position(position)
end

---@export_plugin
---@style button
---@desc 一键结束
---@param role_id RoleID 玩家ID
---@param result boolean 是否胜利
function SetRoleGameResult(role_id, result)
	local role = GameAPI.get_role(role_id)
	if not role then
		return
	end
	if (result)	then
		role.win()
	else
		role.lose()
	end
end
