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
			return luby.to_a(ret)
		else
			return self.__constants
		end
	end,
	nesting = function ()
	end,
	-- public 
	initialize = function (self, block)
		-- TODO : need to call Object.initialize?
		self.__cache = {}
		self.__included = {}
		self.__mixin = {}
		self.__methods = {}
		self.__constants = {}
		self.__protect_levels = {}
		self.__current_protect_level = false
		if block then
			block(self)
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
	class_eval = function (self, block_or_expr, fname, lineno)
	end,
	const_get = function (self, symbol, inherit)
		local c = rawget(self.__cache, symbol)
		if c then return c end
		c = (inherit and self:constants() or self.__constants)[symbol]
		if c then 
			rawset(self.__cache, symbol, c)
			return c 
		end
		if self.const_missing then
			return self:const_missing(symbol)
		else
			error("NameError: uninitialized constant"..symbol)
		end
	end,
	const_set = function (self, symbol, body)
	--print(self, symbol, body)
		self.__constants[symbol] = body
		if body["is_a?"](body, luby.Module) then
			body.__name = symbol
		end
	end,
	name = function (self)
		return self.__name
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
		self.__methods[alias] = self.__methods[symbol]
		self.__protect_levels[alias] = self.__protect_level[symbol]
	end,
	define_method = function (self, symbol, block)
		self.__methods[symbol] = block
		self.__protect_levels[symbol] = self.__current_protect_level
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
