package.path = package.path ..';../?.lua;../../lua-typesys/?.lua;../../lua-typesys/Test/?.lua'

-- 1. header
require("TypeSystemHeader")
-- 2. external type
require("ExternalSample")
-- 3. my type

-- 4. ECS
require("ECSHeader")


-- 定义Transform组件
component.tf {
	_name = "Transform",
	position = Vector3,
	angles = Vector3,
	scale = Vector3,
}

-- 定义Move组件
component.mv {
	_name = "Move",
	speed = Vector3
}

-- 定义Resource组件
component.res {
	_name = "Resource",
	path = "",
	next_animtion = "",
}

---------------------------

-- 定义Move系统
local Move = system.Move {
	_components = {
		component.tf,
		component.mv
	}
}

-- 移动逻辑
function Move.proc(e, time, delta_time)
	print("move", e._id) -- 打印move
	e.res_next_animtion = "move" -- 设置资源的下一个动作
end

-- tick
function Move.update(time, delta_time)
	entity.foreachEntities(Move, Move.proc, time, delta_time)
end

---------------------------

-- 定义资源系统 
local Resource = system.Resource {
	_components = {
		component.res
	}
}

-- 资源逻辑
function Resource.proc(e, time, delta_time)
	if "" ~= e.res_next_animtion then
		-- 如果存在下一个动作，则打印动作名，并禁用移动组件
		print("play animation", e._id, e.res_next_animtion)
		e.res_next_animtion = "" -- 重置下一个动作为空
		entity.disableComponent(e, component.mv)
		print("disable move")
	else
		-- 如果不存在下一个动作，则启用移动组件
		entity.enableComponent(e, component.mv)
		print("enable move")
	end
end

-- tick
function Resource.update(time, delta_time)
	entity.foreachEntities(Resource, Resource.proc, time, delta_time)
end

-------------------------

-- 定义entity类型
Obj = entity.Obj {
	-- 组件默认都是禁用状态
	_components = {
		component.res,
		component.tf,
		component.mv
	},
	__pool_capacity = -1,
	__strong_pool = true,
}

-------------------------

local new = entity.new
local delete = entity.delete

-- 创建entities
local objs = {}
for i=1, 1 do
	local e = entity.new(Obj)
	objs[i] = e
	entity.enableAllComponents(e)
	-- entity.enableComponent(e, component.res)
	-- entity.enableComponent(e, component.tf)
	-- entity.enableComponent(e, component.mv)
end

-- 测试运行5帧
for i=1, 5 do
	print("[loop]", i)
	Move.update(i, 0)
	Resource.update()
end

for i=#objs, 1, -1 do
	local e = objs[i]
	objs[i] = nil
	delete(e)
end

