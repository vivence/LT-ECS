
local _DEBUG_ON = typesys.DEBUG_ON

local print = _DEBUG_ON and print or function() end
local assert = assert

-------------

local proto_info = {} -- system类型协议信息映射表，system type为键，proto为值
local type_mt = {} -- system类型metatable

-- [语法糖] 可以用system.XXX {}语法定义一个system类型
type_mt.__call = function(t, proto)
	if nil ~= proto_info[t] then
		-- 不能重定义
		error(string.format("redifined system: %s", t._type_name))
	end

	local cs = proto._components
	assert(nil ~= cs)

	print("\n------define system:", t._type_name, "begin--------")

	-- 检查系统用的组件组是否都是合法的组件类型
	for i=1, #cs do
		c = cs[i]
		assert(component.checkType(c))
		print("component:", component.getTypeName(c))
	end

	proto_info[t] = proto

	print("------define system:", t._type_name, "end--------\n")
	return t
end

system = {}

-- 获取系统的组件组
function system.getComponents(s)
	return proto_info[s]._components
end

-- 通过组件组获取系统类型
function system.getTypeByComponentGroup(cs)
	for t, proto in pairs(proto_info) do
		if proto._components == cs then
			return t
		end
	end
	return nil
end

-- 启动system定义类型的点“.”操作语法
setmetatable(system, {
	__index = function(t, name)
		local new_t = setmetatable({
			_type_name = name
		}, type_mt)
		t[name] = new_t
		return new_t
	end
})


