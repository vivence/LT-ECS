
local _DEBUG_ON = typesys.DEBUG_ON

local print = _DEBUG_ON and print or function() end
local assert = assert

------- [代码区段开始] table池 --------->
local table_pool = {}
local function _newTable()
	local n = #table_pool
	if 0 < n then
		local t = table_pool[n]
		table_pool[n] = nil
		return t
	end
	return {}
end
local function _deleteTable(t)
	for k in pairs(t) do
		t[k] = nil
	end
	table_pool[#table_pool+1] = t
end
------- [代码区段结束] table池 ---------<


local proto_info = {} -- entity类型协议信息映射表，entity type为键，proto为值
local type_mt = {} -- entity类型的metatable

-- entity组件信息映射表，entity id为键，componennt info为值
-- component info里存放了entity的component group里所有组件的enable状态
local entity_components = {}  -- e_id => ec_info(c => enabled)

-- 系统匹配的entities缓存，系统components group为键，entity id列表为值
local entities_cache = {} -- s_cs => es(e_id list)

-- 系统匹配的entities缓存查询表，entity type为键，系统components group查询表为值
-- （系统components group查询表：component为键，系统components group列表为值）
local cache_lookup = {} -- e_type => s_cs_map(c => s_cs)

local matching_system = nil -- 正在foreach的系统
local delay_entities_id = {} -- foreach时，暂存需要_refreshCache的entities，待foreach结束后再统一_refreshCache

entity = {}

-- [语法糖] 可以用entity.XXX {}语法定义一个entity类型
type_mt.__call = function(t, proto)
	assert(nil == proto.__super) -- 不支持继承

	-- 将entity类型转换成typesys类型，以便交由typesys管理
	t = typesys[t._type_name]
	entity[t._type_name] = t

	if nil ~= proto_info[t] then
		-- 不能重定义
		error(string.format("redifined entity: %s", t._type_name))
	end
	local e_cs = proto._components
	assert(nil ~= e_cs) -- entity存在的意义就是一定要要组件组

	print("\n------define entity:", t._type_name, "begin--------")

	local e_proto = {__pool_capacity = proto.__pool_capacity, __strong_pool = proto.__strong_pool}
	for i=1, #e_cs do
		c = e_cs[i]
		assert(component.checkType(c))
		print("component:", component.getTypeName(c))

		-- 将component的域填充到entity中，请注意查看其填充的命名规则，详见component的定义
		component.fillFieldsToEntity(c, e_proto)
	end

	-- 将类型协议放入到映射表中，以供后续查询entity的组件池等信息
	proto_info[t] = proto

	-- 触发typesys的类型定义，交由typesys管理
	t(e_proto)

	print("------define entity:", t._type_name, "end--------\n")
	return t
end

------- [代码区段开始] 将typesys中entity要用到的接口放到entity中，以对使用者隐藏typesys的存在 --------->
local getObjectByID = typesys.getObjectByID
local getType = typesys.getType
local getTypeName = typesys.getTypeName
local checkType = typesys.checkType
local new = typesys.new
local delete = typesys.delete

entity.getObjectByID = getObjectByID
entity.getType = getType
entity.getTypeName = getTypeName
entity.checkType = checkType
entity.new = new
entity.delete = delete
------- [代码区段结束] 将typesys中entity要用到的接口放到entity中，以对使用者隐藏typesys的存在 ---------<

------- [代码区段开始] 内部函数 --------->
-- 构建entity的组件信息，可设置初始化enable状态（默认为false）
local function _buildComponentsInfo(e, init)
	init = init or false

	local id = e._id
	local ec_info = entity_components[id]
	if nil == ec_info then
		ec_info = {}
		entity_components[id] = ec_info
	end

	-- 为每个组件设置初始化enable状态
	local e_proto = proto_info[getType(e)]
	local e_cs = e_proto._components
	for i=1, #e_cs do
		c = e_cs[i]
		ec_info[c] = init
	end
	return ec_info
end

-- 检查entity的组件状态 ，是否匹配系统组件组当中的所有组件，且为enable状态
local function _checkComponents(ec_info, s_cs)
	for i=1, #s_cs do
		if not ec_info[s_cs[i]] then
			return false
		end
	end
	return true
end

-- 保证entities缓存中包含e_id
local function _makesureCacheIncludeEntity(es, e)
	local e_id = e._id
	for i=1, #es do
		if es[i] == e_id then
			return
		end
	end
	es[#es+1] = e_id
end

-- 保证entities缓存中不包含e_id
local function _makesureCacheExcludeEntity(es, e)
	local e_id = e._id
	for i=1, #es do
		if es[i] == e_id then
			table.remove(es, i)
			return
		end
	end
end

-- 执行保证entities缓存过程（_makesureCacheIncludeEntity，_makesureCacheExcludeEntity）
local function _doMakesureCacheProc(s_cs_list, e, proc)
	local es = nil
	local s_cs = nil
	for i=1, #s_cs_list do
		s_cs = s_cs_list[i]
		es = entities_cache[s_cs]
		proc(es, e)
	end
end

-- 刷新entity缓存的组件enable状态，如果有系统正在foreach，那么刷新将被延迟到foreach结束
local function _refreshCache(e, c, enabled)
	if nil ~= matching_system then
		-- 记录信息，并延迟
		local refresh_info = delay_entities_id[e._id]
		if nil == refresh_info then
			refresh_info = _newTable() 
			delay_entities_id[e._id] = refresh_info
		end
		if nil == c then -- 如果指定的组件为nil，那么将标志为刷新所有组件enable状态
			refresh_info.all = enabled
		elseif nil == refresh_info.all then
			refresh_info[c] = enabled -- 设置组件将要刷新的enable状态
		end
		return
	end

	local e_type = getType(e)
	local s_cs_map = cache_lookup[e_type]
	if nil == s_cs_map then
		-- 不存在缓存
		return
	end

	if nil == c then
		-- 刷新所有组件的enable状态
		if enabled then
			-- 保证此entity所匹配的所有系统中，每个系统的组件组对应的entity缓存表里包含e_id
			for _,s_cs_list in pairs(s_cs_map) do
				_doMakesureCacheProc(s_cs_list, e, _makesureCacheIncludeEntity)
			end
		else
			-- 保证此entity所匹配的所有系统中，每个系统的组件组对应的entity缓存表里不包含e_id
			for _,s_cs_list in pairs(s_cs_map) do
				_doMakesureCacheProc(s_cs_list, e, _makesureCacheExcludeEntity)
			end
		end
	else
		-- 仅刷新一个组件的enable状态
		local s_cs_list = s_cs_map[c]
		if nil == s_cs_list then
			-- 此组件对应的系统组件组不存在
			return
		end

		if enabled then
			-- 保证此组件所匹配的所有系统中，每个系统的组件组对应的entity缓存表里包含e_id
			_doMakesureCacheProc(s_cs_list, e, _makesureCacheIncludeEntity)
		else
			-- 保证此组件所匹配的所有系统中，每个系统的组件组对应的entity缓存表里不包含e_id
			_doMakesureCacheProc(s_cs_list, e, _makesureCacheExcludeEntity)
		end
	end
end

-- 构建系统匹配的entities缓存查询表
local function _buildCacheLookup(e, s_cs)
	local e_type = getType(e)
	local s_cs_map = cache_lookup[e_type]
	if nil == s_cs_map then
		s_cs_map = {}
		cache_lookup[e_type] = s_cs_map
	end

	-- 将系统组件组当中所有组件映射一个系统组件组列表，这个列表中要包含此系统组件组
	local c = nil
	local s_cs_list = nil
	local added = nil
	for i=1, #s_cs do
		c = s_cs[i]
		s_cs_list = s_cs_map[c]
		if nil == s_cs_list then
			s_cs_list = {}
			s_cs_map[c] = s_cs_list
		end

		-- 防止重复添加
		added = false
		for j=1, #s_cs_list do
			if s_cs_list[j] == s_cs then
				added = true
				break
			end
		end

		-- 确保列表中包含此系统组件组
		if not added then
			s_cs_list[#s_cs_list+1] = s_cs
		end
	end
end
------- [代码区段结束] 内部函数 ---------<

-- 判断组件是否enabled
function entity.isComponentEnabled(e, c)
	local ec_info = entity_components[e._id]
	if nil == ec_info then
		return false -- no component enabled
	end
	return ec_info[c]
end

-- 激活entity单个组件
function entity.enableComponent(e, c)
	local ec_info = entity_components[e.id]
	if nil == ec_info then
		ec_info = _buildComponentsInfo(e)
	end
	ec_info[c] = true
	_refreshCache(e, c, true) -- 刷新缓存
end

-- 禁用entity单个组件
function entity.disableComponent(e, c)
	local ec_info = entity_components[e._id]
	if nil == ec_info then
		return
	end
	ec_info[c] = false
	_refreshCache(e, c, false) -- 刷新缓存
end

-- 激活entity所有组件
function entity.enableAllComponents(e)
	_buildComponentsInfo(e, true)
	_refreshCache(e, nil, true) -- 刷新缓存
end

-- 禁用entity所有组件
function entity.disableAllComponents(e)
	_buildComponentsInfo(e, false)
	_refreshCache(e, nil, false) -- 刷新缓存
end

-- 系统遍历所有匹配的entities
function entity.foreachEntities(s, proc, ...)
	assert(nil == matching_system) -- foreach过程中不允许再次foreach
	matching_system = s -- 设置当前正在foreach的系统

	-- 获取系统匹配的entities
	local s_cs = system.getComponents(s)
	-- 1.先尝试从缓存中拿取
	local es = entities_cache[s_cs] 
	-- 2.缓存不存在时，执行匹配算法，并建立缓存
	if nil == es then
		es = {}
		local i = 1
		for e_id, ec_info in pairs(entity_components) do
			local e = getObjectByID(e_id)
			if nil ~= e and _checkComponents(ec_info, s_cs) then
				es[i] = e_id
				i = i+1
				_buildCacheLookup(e, s_cs)
			end
		end
		entities_cache[s_cs] = es
	end

	-- 遍历匹配的所有entity并执行proc
	for i=#es, 1, -1 do
		local e_id = es[i]
		local e = getObjectByID(e_id)
		if nil == e then
			es[i] = nil
		else
			proc(e, ...)
		end
	end

	matching_system = nil

	-- 延迟刷新缓存
	local e = nil
	for e_id, refresh_info in pairs(delay_entities_id) do
		delay_entities_id[e_id] = nil
		e = getObjectByID(e_id)
		if e then
			if nil ~= refresh_info.all then
				_refreshCache(e, nil, refresh_info.all)
			else
				for c, enabled in pairs(refresh_info) do
					_refreshCache(e, c, enabled)
				end
			end
		end
		_deleteTable(refresh_info)
	end
end

-- 打印缓存
function entity.printCache()
	local print = _G.print
	for s_cs, es in pairs(entities_cache) do
		local s_type = system.getTypeByComponentGroup(s_cs)
		print(string.format("\n--------- %s caches ----------", s_type._type_name))
		for i=1, #es do
			local e_id = es[i]
			local e = getObjectByID(e_id)
			if nil ~= e then
				print(e._type_name, e_id)
			end
		end
		print(string.format("------------------------------\n"))
	end
end

-- 打印缓存查询表
function entity.printCacheLookup()
	local print = _G.print
	for e_type, s_cs_map in pairs(cache_lookup) do
		print(string.format("\n--------- %s lookup ----------", e_type._type_name))
		for c, s_cs_list in pairs(s_cs_map) do
			print(string.format("--- %s map ---", c._type_name))
			for i=1, #s_cs_list do
				local s_cs = s_cs_list[i]
				local s_type = system.getTypeByComponentGroup(s_cs)
				print(s_type._type_name)
			end
			print(string.format("--------------"))
		end
		print(string.format("------------------------------\n"))
	end
end

-- 启动entity定义类型的点“.”操作语法
setmetatable(entity,{
	__index = function(t, name)
		local new_t = setmetatable({
			_type_name = name
		}, type_mt)
		t[name] = new_t
		return new_t
	end
})





