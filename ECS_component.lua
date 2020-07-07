
--[[
定义一个组件：
XXX = component.def.XXX {
	__name = "", 组件名，主要用于显示
}
--]]

local error = error
local print = print
-- local print = function()end

-------------

local _proto_info_map = {} -- component类型协议信息映射表，type为键，proto为值
local _type_def_mt = {} -- component类型定义metatable

-- 类型定义语法糖，用于实现component.def.XXX {}语法
-- 此语法可以将{}作为proto传递给__call函数
_type_def_mt.__call = function(t, proto)

	if nil == proto.__name then
		proto.__name = t.__type_name
	end

	print("\n------定义组件开始：", t.__type_name, proto.__name, "--------")

	-- 检查定义的字段是否合法，只允许：number,string,boolean,typesys类型
	for field_name, v in pairs(proto) do
		if type(field_name) ~= "string" then
			error("<组件定义错误> 字段名类型错误："..type(field_name))
		end

		if "__name" == field_name then
			if type(field_name) ~= "string" then
				error("<组件定义错误> __name字段值类型错误："..type(field_name))
			end
		else
			local vt = type(field_name)
			if "__" == string.sub(field_name, 1, 2) then
				error("<组件定义错误> “__”为系统保留前缀，不允许使用："..field_name)
			end

			if "number" == vt then
				print("number类型字段：", field_name, "缺省值：", v)
			elseif "string" == vt then
				print("string类型字段：", field_name, "缺省值：", v)
			elseif "boolean" == vt  then
				print("boolean类型字段：", field_name, "缺省值：", v)
			elseif vt == "table" and typesys.isType(v) then
				print("typesys类型字段：", v.__type_name)
			else
				error("<组件定义错误> 字段值类型错误："..field_name)
			end
		end
	end

	_proto_info_map[t] = proto

	print("------组件定义结束：", t.__type_name, proto.__name, "--------\n")
	return t
end

component = {}

-- 将component的字段填充到entity中，命名规则是：<组件类型名>_<字段名>
function component.fillFieldsToEntity(t, e)
	local info = _proto_info_map[t]
	for k, v in pairs(info) do
		if "__name" ~= k then
			k = string.format("%s_%s", t.__type_name, k)
			e[k] = v
		end
	end
end

-- 检查是否是组件类型
function component.isType(t)
	return nil ~= _proto_info_map[t]
end

-- 获取组件类型名
function component.getTypeName(t)
	local info = _proto_info_map[t]
	return info.__name
end

-- 类型定义语法糖，用于实现component.def.XXX语法
-- 此语法可以将XXX作为name传递给__index函数，而t就是component
component.def = setmetatable({},{
	__index = function(t, name)
		if nil ~= rawget(component, name) then
			error("<组件定义错误> 组件名已存在："..name)
		end
		local new_t = setmetatable({
			__type_name = name
		}, _type_def_mt)
		rawset(component, name, new_t)
		return new_t
	end
})

setmetatable(component, {
	__index = function(t, k)
		error("<component访问错误> 不存在："..k)
	end,
	__newindex = function(t, k, v)
		error("<component访问错误> 不存在："..k)
	end
})
