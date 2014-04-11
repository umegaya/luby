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

-- class body
local Object = Class:new(BasicObject, function (klass)
	klass.__name = "Object"
	klass:include(Kernel)
	klass.__methods = {
		initialize = function (...)
			BasicObject.initialize(self, ...)
			self.__flags__ = 0
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
			return self.__class__
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
			local mt = getmetatable(self)
			mt[symbol] = proc
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
			for i=1,select('#', ...),1 do
				local mod = select(i, ...)
				self.__class__:include(mod)
			end
		end,
		freeze = function (self)
			self.__flags.__ = setflag(self.__flags__, flag_frozen, on)
			return self
		end,
		["frozen?"] = function (self)
			return getflag(self.__flags__, flag_frozen)
		end,
		["is_a?"] = function (self, klass)
			return luby.traverse_inheritance_ladder(self.__class, function (c)
				return klass == c
			end)
		end,
	}
end)

return Object
