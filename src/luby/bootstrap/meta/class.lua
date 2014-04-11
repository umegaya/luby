local luby = require ('runtime')
local Module = require ('bootstrap/meta/module')

-- class body
local Class = {
	-- new is from Module
	initialize = function (self, superclass, block)
		Module.initialize(self, false)
		if superclass ~= false then
			self.__superclass = (superclass or Module.const_get("Object"))
			self:include(self.__superclass)
			self.__superclass.inherited(self)
		else
			self.__superclass = false -- BasicObject
		end
		if block then
			block(self)
		end
	end,
	superclass = function (self) 
		return self.__superclass or nil
	end,
	allocate = luby.allocator,
	inherited = function (successor)
	end,
}

return Class
