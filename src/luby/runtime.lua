local luby = {}

luby.nesting = {}
luby.last_eval = nil

luby.class = function (name, parent, decl)
	--print('Class.new:', name, parent, decl)
	if parent and (not luby[parent]) then
		luby.raise("throw:NameError:uninitialized constant:"..parent)
	end
	local scope = (luby.nesting[#luby.nesting] or luby.Object)
	local ok, c = pcall(scope.const_get, scope, name)
	if ok and c then
		c:class_eval(decl)
	else
		c = luby.Class:new(luby[parent] or luby.Object, decl)
		scope:const_set(name, c)
	end
	return luby.last_eval
end
luby.module = function (name, decl)
	local scope = (luby.nesting[#luby.nesting] or luby.Object)
	local ok, m = pcall(scope.const_get, scope, name)
	if m then
		m:class_eval(decl)
	else
		m = luby.Module:new(decl)
		scope:const_set(name, m)
	end
	return luby.last_eval
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
lookup = function (c, cache, k, protect_level)
if lookup_log then print('lookup', rawget(c, "__name") or "<<under creation>>", k) end
	-- search from method cache
	local level
	local v = rawget(cache, k)
	if v then 
		level = (rawget(rawget(c, "__cached_protect_levels"), k) or METHOD_PROTECTION_LEVEL.PUBLIC)
		return v, level, true
	end
	k = (rawget(rawget(c, "__aliases"), k) or k)
	v = rawget(rawget(c, "__methods"), k)
if lookup_log then 
	for k,v in pairs(rawget(c, "__methods")) do
		print(rawget(c, "__name") or "<<under creation>>",k,v)
	end
end
if lookup_log then print('result', rawget(c, "__name") or "<<under creation>>", k,v,#c.__mixin) end
	if v then
		level = (rawget(rawget(c, "__protect_levels"), k) or METHOD_PROTECTION_LEVEL.PUBLIC)
		return v, level, false
	end
	local last = #c.__mixin
	local from_cache
	for idx,m in ipairs(c.__mixin) do
		cache = rawget(m, "__cache")
		if idx == last then 
			v,level,from_cache = lookup(m, cache, k, protect_level)
		else
			v,level,from_cache = lookup(m, cache, k, METHOD_PROTECTION_LEVEL.PUBLIC)
		end
		if v then 
			if not from_cache then
				rawset(cache, k, v)
				rawset(rawget(m, "__cached_protect_levels"), k, level)
			end
			return v, level, false
		end
	end
	return nil
end
local indexer = function (self, k, protect_level)
	-- print("indexer:", k)
	local c = rawget(self, "__class")
	local cache = rawget(c, "__cache")
	local v, level, from_cache = lookup(c, cache, k, protect_level)
	if v then
		if level > protect_level then
			-- TODO NameError should be thrown
			luby.raise("todo: NameError:protect level violation:"..k..":"..level..":"..protect_level) 
		end
		if not from_cache then
			rawset(cache, k, v)
			rawset(rawget(c, "__cached_protect_levels"), k, level)
		end
	else
		v = lookup(c, cache, "method_missing", METHOD_PROTECTION_LEVEL.PRIVATE)
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

local public_indexer = function (self, k)
	return indexer(self, k, METHOD_PROTECTION_LEVEL.PUBLIC)
end

local atbyte = string.byte('@')
luby.self_indexer = function (self, k)
	if string.byte(k) == atbyte then
		if string.byte(k, 2) == atbyte then
			return rawget(self, k)
		else
			return nil
		end
	end
	return indexer(self, k, METHOD_PROTECTION_LEVEL.PRIVATE)
end

-- define method/constant from lua ruby class code. ignore all method protection
luby.define_method = function (klass, symbol, proc)
	local v = luby.self_indexer(klass, "define_method")
	return v(klass, symbol, proc)
end
luby.const_set = function (klass, symbol, body)
	local v = luby.self_indexer(klass, "const_set")
	return v(klass, symbol, body)
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
	}, { __index = public_indexer }) 
end

-- literal creation
luby.array = function (t) return t end
luby.hash = function (t) return t end
luby.range = function (a, b) return a, b end
luby.regex = function (pattern) return pattern end

-- initialize lua types as some literal ruby object
luby.objectize_lua_primitives = function ()
	local String = luby.Object:const_get("String")
	debug.setmetatable("", { __index = function (self, k)
		return lookup(String, k)
	end})

	local Numeric = luby.Object:const_get("Numeric")
	debug.setmetatable(0, { __index = function (self, k)
		return lookup(Numeric, k)
	end})

	local TrueClass = luby.Object:const_get("TrueClass")
	local FalseClass = luby.Object:const_get("FalseClass")
	debug.setmetatable(true, { __index = function (self, k)
		return lookup(self and TrueClass or FalseClass, k)
	end})

	local NilClass = luby.Object:const_get("NilClass")
	debug.setmetatable(nil, { __index = function (self, k)
		return lookup(NilClass, k)
	end})

	local Proc = luby.Object:const_get("Proc")
	debug.setmetatable(function() end, { __index = function (self, k)
		return lookup(luby.Proc, k)
	end})
end

return luby