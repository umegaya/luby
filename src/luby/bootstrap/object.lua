local luby = require ('runtime')
local Class = require ('bootstrap/class')
local BasicObject = require ('bootstrap/basic_object')
local Kernel = require ('bootstrap/kernel')

local setflag = function (v, f, on)
	if on then
		return bit.bor(v, f)
	else
		return bit.band(v, bit.bnot(f))
	end
end
local getflag = function (v, f)
	return bit.band(v, f) ~= 0
end
local flag_tainted = bit.lshift(1, 0)
local flag_frozen = bit.lshift(1, 1)

local failed_new = function (self)
	luby.raise("TODO: TypeError: can't create instance of singleton class")
end

-- class body
local Object = Class:new(BasicObject, function (klass)
	klass.__name = "Object"
	klass:include(Kernel)
	klass.__methods = {
		initialize = function (...)
			BasicObject.initialize(self, ...)
			self.__flags = 0
		end,
		["!~"] = function (self, pattern)
			return not self["=~"](pattern)
		end,
		["<=>"] = function (self, other)
			return (self == other) and 0 or nil
		end,
		["==="] = function (self, other)
			return not (self == other)
		end,
		["=~"] = function (self, pattern)
			return nil
		end,
		class = function (self)
			local c = rawget(self, "__class")
			return (rawget(c, "__name") and c or rawget(c, "__superclass"))
		end,
		clone = function (self)
			local klass = getmetatable(self)
			for k,v in pairs(self) do
				if type(v) ~= "table" then
					copy[k] = v
				else
					copy[k] = v:clone()
				end
			end
			return setmetatable(copy, klass)
		end,
		define_singleton_method = function (self, symbol, proc)
			self:singleton_class():define_method(symbol, proc)
			self:singleton_method_added(symbol)
			return proc
		end,
		display = function (self, port)
			port = (port or _R["$>"])
			port:write(self)
		end,
		dup = function (self)
			-- TODO : differenciate from clone (check tainted and frozen state)
			return self:clone()
		end,
		enum_for = function (self)
			assert(false, "TODO: decide how to express enumerator in luby (pairs?)")
		end,
		extend = function (self, ...)
			local c = self:singleton_class()
			for i=1,select('#', ...),1 do
				local mod = select(i, ...)
				c:include(mod)
			end
		end,
		freeze = function (self)
			self.__flags = setflag(self.__flags, flag_frozen, on)
			return self
		end,
		["frozen?"] = function (self)
			return getflag(self.__flags, flag_frozen)
		end,
		["is_a?"] = function (self, klass)
			return luby.traverse_inheritance_ladder(self:class(), function (c)
				return klass == c
			end)
		end,
		singleton_class = function (self)
			local c = self:class() 
			if not c["singleton_class?"](c) then
				c = luby.Class:new(self.__class, function (klass)
					klass:define_method("new", failed_new)
				end)
				self.__class = c
			end
			return c
		end,
	}
end)

return Object
