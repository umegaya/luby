local luby = {}

luby.class = function (name, parent, decl)
	if parent and (not luby[parent]) then
		luby.raise("throw:NameError:uninitialized constant:"..parent)
	end
	luby.Object:const_set(name, 
		luby.Class:new(parent ~= false and (luby[parent] or luby.Object) or parent, decl)
	)
end
luby.module = function (name, decl)
	luby.Object:const_set(name, luby.Module:new(decl))
end

-- ruby keyword 'super'
luby.super = function (callee)
	-- traverse inheritance tree and return function which is next candidate to call
end

luby.raise = function (what)
	error(what)
end

-- invalidate method cache when class or method modified
luby.clear_method_cache = function (object)
	object.__class.__cache = {}
end

-- traverse tree
luby.traverse_inheritance_tree = function (class, cb)
	local v = cb(class)
	if v then return v end
	for n,m in ipairs(class.__mixin) do
		v = luby.traverse_inheritance_tree(m, cb) 
		if v then return v end
	end
	return false
end

luby.traverse_inheritance_ladder = function (class, cb)
	while true do
		local v = cb(class)
		if v then return v end
		if #class.__mixin > 0 then
			class = class.__mixin[#class.__mixin]
		else
			break
		end
	end
	return false
end

-- search method and cache them
local METHOD_PROTECTION_LEVEL = {
	PUBLIC = 1,
	PROTECTED = 2,
	PRIVATE = 3,
}
luby.METHOD_PROTECTION_LEVEL = METHOD_PROTECTION_LEVEL

local lookup_log = false
local lookup
lookup = function (c, k, protect_level)
if lookup_log then print('lookup', c.__name, k) end
	-- search from method cache
	local cache = rawget(c, "__cache")
	local v = rawget(cache, k)
	if v then return v end
	v = rawget(rawget(c, "__methods"), k)
if lookup_log then 
	for k,v in pairs(rawget(c, "__methods")) do
		print(c.__name,k,v)
	end
end
if lookup_log then print('result', c.__name, k,v,#c.__mixin) end
	if v then
		local level = (rawget(rawget(c, "__protect_levels"), k) or METHOD_PROTECTION_LEVEL.PUBLIC)
		if level > protect_level then
			-- TODO NameError should be thrown
			luby.raise("todo: NameError:protect level violation:"..k..":"..level..":"..protect_level) 
		end
		rawset(cache, k, v)
		return v
	end
	local last = #c.__mixin
	for idx,m in ipairs(c.__mixin) do
		if idx == last then 
			v = lookup(m, k, protect_level)
		else
			v = lookup(m, k, METHOD_PROTECTION_LEVEL.PUBLIC)
		end
		if v then 
			rawset(cache, k, v)
			return v 
		end
	end
	return v
end
local indexer = function (self, k, protect_level)
	if k:byte() == ('@'):byte() then
		return nil
	end
	-- print("indexer:", k)
	local v = lookup(rawget(self, "__class"), k, 
		protect_level or METHOD_PROTECTION_LEVEL.PUBLIC)
	if not v then
		v = lookup(rawget(self, "__class"), "method_missing", METHOD_PROTECTION_LEVEL.PRIVATE)
		if v then
			return function (...)
				return v(self, k, ...)
			end
		else
			luby.raise("todo: NoMethodError:method_missing does not exist:")
		end
	end
	return v
end

luby.self_indexer = function (self, k)
	return indexer(self, k, METHOD_PROTECTION_LEVEL.PRIVATE)
end

-- uuid generator (TODO: modify for multithread env)
-- thread index and increment value?
local seed = 0
local uuid = function ()
	seed = (seed + 1)
	return seed
end

luby.allocator = function (self)
	return setmetatable({
		__uuid = uuid(),
		__class = self,
	}, { __index = indexer }) 
end
	
return luby