local luby = require ('runtime')

-- class body
local Module = {
	-- class 
	new = function (self, ...)
		local o = luby.allocator(self)
		o:initialize(...)
		return o
	end,
	constants = function (self, inherit)
		if inherit then
			local ret = {}
			luby.traverse_inheritance_tree(self, function (klass)
				for _,c in ipairs(klass:constants(false)) do
					table.insert(ret, c)
				end
			end)
			return luby.array(ret)
		else
			return rawget(self, "__constants")
		end
	end,
	nesting = function ()
	end,
	-- public 
	initialize = function (self, block)
		-- TODO : need to call Object.initialize?
		rawset(self, "__cache", {})
		rawset(self, "__included", {})
		rawset(self, "__mixin", {})
		rawset(self, "__methods", {})
		rawset(self, "__aliases", {})
		rawset(self, "__constants", {})
		rawset(self, "__protect_levels", {})
		rawset(self, "__cached_protect_levels", {})
		-- rawset(self, "__current_protect_level", false)
		if block then
			self:class_eval(block)
		end
	end,
	["<"] = function (self, other)
	end,
	["<="] = function (self, other)
	end,
	["<=>"] = function (self, other)
	end,
	["==="] = function (self, other)
	end,
	[">"] = function (self, other)
	end,
	[">="] = function (self, other)
	end,
	ancestors = function (self)
	end,
	autoload = function (self, name, feature)
	end,
	["autoload?"] = function (self, name)
	end,
	class_eval = function (self, code, fname, lineno)
		-- TODO: apply fname and lineno as stack trace
		table.insert(luby.nesting, self)
		luby.last_eval = code(self)
		table.remove(luby.nesting)
		return luby.last_eval
	end,
	const_get = function (self, symbol, inherit)
		local cache = rawget(self, "__cache")
		local c = rawget(cache, symbol)
		if c then return c end
		if inherit == nil then 
			inherit = true
		end
		c = (inherit and self:constants() or self.__constants)[symbol]
		if c then 
			rawset(cache, symbol, c)
			return c
		end
		return self:const_missing(symbol)
	end,
	const_set = function (self, symbol, body)
	-- print(self, symbol, body)
		rawset(rawget(self, "__constants"), symbol, body)
		if body["is_a?"](body, luby.Module) then
			rawset(body, "__name", symbol)
		end
		return body
	end,
	const_missing = function (self, symbol)
		luby.raise("todo: NameError: uninitialized constant "..symbol)
	end,
	name = function (self)
		return rawget(self, "__name")
	end,
	["singleton_class?"] = function (self)
		return (rawget(self, "__name") ~= nil)
	end,
	--[[
	class_variable_defined? 
	class_variables 
	const_defined? 
	constants 
	include? 
	included_modules 
	instance_method 
	instance_methods 
	module_eval 
	method_defined? 
	private_class_method
	private_instance_methods
	private_method_defined?
	protected_instance_methods
	protected_method_defined?
	public_class_method
	public_instance_method
	public_instance_methods
	public_method_defined?
	remove_class_variable
	to_s
	]]--
	-- private
	alias_method = function (self, alias, symbol)
		self.__aliases[alias] = symbol
	end,
	define_method = function (self, symbol, block)
		self.__methods[symbol] = block
		self.__protect_levels[symbol] = rawget(self, "__current_protect_level")
	end,
	include = function (self, mod)
		table.insert(self.__mixin, 1, mod)
		mod.included(self)
	end,
	included = function (klass)

	end,
	private = function (self, ...)
		local n_args = select('#', ...)
		if n_args == 0 then
			self.__current_protect_level = luby.METHOD_PROTECTION_LEVEL.PRIVATE
		else
			for i=1,n_args,1 do
				self.__protect_levels[select(i,...)] = luby.METHOD_PROTECTION_LEVEL.PRIVATE
			end
		end
	end,
	--[[
	append_features 
	attr 
	attr_accessor 
	attr_reader 
	attr_writer 
	class_exec 
	class_variable_get 
	class_variable_set 
	define_method 
	extend_object 
	extended 
	method_added 
	method_removed 
	method_undefined 
	module_exec 
	module_function 
	private 
	private_constant 
	protected 
	public 
	public_constant 
	remove_const 
	remove_method 
	singleton_class?
	undef_method
	]]--
}

return Module
