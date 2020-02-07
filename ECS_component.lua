
local _DEBUG_ON = typesys.DEBUG_ON

local print = _DEBUG_ON and print or function() end
local assert = assert

local NO_NAME = "[no name]"

-------------

local proto_info = {} -- component类型协议信息映射表，component type为键，proto为值
local type_mt = {} -- component类型metatable

-- [语法糖] 可以用component.XXX {}语法定义一个component类型
type_mt.__call = function(t, proto)
	if nil ~= proto_info[t] then
		-- 不能重复定义
		error(string.format("redifined component: %s", t._type_name))
	end

	print("\n------define component:", string.format("%s(%s)", t._type_name, proto._name or NO_NAME), "begin--------")

	-- 检查定义的字段是否合法，只允许：number,string,boolean,typesys类型（包括注册的外部类型）
	for k,v in pairs(proto) do
		assert(type(k) == "string")
		if "_name" == k then
			assert("string" == type(v))
		else
			local vt = type(v)
			if "number" == vt then
				print("number:", k, "=", v)
			elseif "string" == vt then
				print("string:", k, "=", v)
			elseif "boolean" == vt  then
				print("boolean:", k, "=", v)
			elseif vt == "table" and typesys.checkType(v) then
				print(string.format("%s:", typesys.getTypeName(v)), k)
			else
				error(string.format("Invalid field %s with type %s", k, vt))
			end
		end
	end

	proto_info[t] = proto

	print("------define component:", string.format("%s[%s]", t._type_name, proto._name or NO_NAME), "end--------\n")
	return t
end

component = {}

-- 将component的字段填充到entity中，命名规则是：<组件类型名>_<字段名>
function component.fillFieldsToEntity(t, e)
	local info = proto_info[t]
	for k,v in pairs(info) do
		if "_name" ~= k then
			k = string.format("%s_%s", t._type_name, k)
			e[k] = v
			if _DEBUG_ON then
				if "table" == type(v) then
					print(string.format("%s:", v._type_name or NO_NAME), k)
				else
					print(string.format("%s:", type(v)), k, "=", v)
				end
			end
		end
	end
end

-- 检查是否是组件类型
function component.checkType(t)
	return nil ~= proto_info[t]
end

-- 获取组件类型名
function component.getTypeName(t)
	local info = proto_info[t]
	return info._name or NO_NAME
end

-- 启动component定义类型的点“.”操作语法
setmetatable(component,{
	__index = function(t, name)
		local new_t = setmetatable({
			_type_name = name
		}, type_mt)
		t[name] = new_t
		return new_t
	end
})


