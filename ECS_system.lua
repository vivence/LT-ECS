
--[[
定义一个系统：
XXX = system.def.XXX {
	__components = {
		component.aaa,
		component.bbb
	}, 组件组，用于匹配实体
}
--]]

local error = error
local print = print
-- local print = function()end

-------------

local _proto_info_map = {} -- system类型协议信息映射表，type为键，proto为值
local _type_def_mt = {} -- system类型定义metatable

-- 类型定义语法糖，用于实现system.def.XXX {}语法
-- 此语法可以将{}作为proto传递给__call函数
_type_def_mt.__call = function(t, proto)
	
	print("\n------定义系统开始：", t.__type_name, "--------")

	local cs = proto.__components

	-- 检查系统用的组件组是否都是合法的组件类型
	for i=1, #cs do
		c = cs[i]
		if not component.isType(c) then
			error("<系统定义错误> 组件类型不存在")
		end
		print("组件：", component.getTypeName(c))
	end

	_proto_info_map[t] = proto

	print("------系统定义结束：", t.__type_name, "--------\n")
	return t
end

system = {}

-- 获取系统的组件组
function system.getComponents(s)
	return _proto_info_map[s].__components
end

-- 通过组件组获取系统类型
function system.getTypeByComponentGroup(cs)
	for t, proto in pairs(_proto_info_map) do
		if proto.__components == cs then
			return t
		end
	end
	return nil
end

-- 类型定义语法糖，用于实现system.def.XXX语法
-- 此语法可以将XXX作为name传递给__index函数，而t就是system
system.def = setmetatable({},{
	__index = function(t, name)
		if nil ~= rawget(system, name) then
			error("<系统定义错误> 系统名已存在："..name)
		end
		local new_t = setmetatable({
			__type_name = name
		}, _type_def_mt)
		rawset(system, name, new_t)
		return new_t
	end
})

setmetatable(system, {
	__index = function(t, k)
		error("<system访问错误> 不存在："..k)
	end,
	__newindex = function(t, k, v)
		error("<system访问错误> 不存在："..k)
	end
})


