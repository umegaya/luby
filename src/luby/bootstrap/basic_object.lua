local luby = require ('runtime')
local Class = require ('bootstrap/class')

-- class body
local BasicObject = Class:new(false, function (klass)
	klass.__name = "BasicObject"
	klass.__methods = {
		initialize = function (self, ...)
		end,
		["!"] = function (self)
			return (not self)
		end,
		["equal?"] = function (self, other)
			return self.__uuid__ == other.__uuid__
		end,
		["!="] = function (self, other)
			return not (self == other)
		end,
		__id__ = function (self)
			return self.__uuid__
		end,
		__send__ = function (self, symbol, ...)
			return self[symbol](...)
		end,
		method_missing = function (self, name, ...)
			luby.raise("todo:throw NoMethodError:"..self.__class.__name.."."..name)
		end,
		singleton_method_added = function (self, symbol)
		end,
		singleton_method_removed = function (self, symbol)
		end,
		singleton_method_undefined = function (self, symbol)
		end,
	}
end)

return BasicObject
