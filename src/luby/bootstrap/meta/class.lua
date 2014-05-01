local luby = require ('runtime')
local Module = require ('bootstrap/meta/module')

-- class body
local Class = {
	-- new is from Module
	initialize = function (self, superclass, block)
		Module.initialize(self, false)
		if superclass ~= false then
			self.__superclass = (superclass or luby.Object)
			self:include(self.__superclass)
			self.__superclass.inherited(self)
		end
		if block then
			self:class_eval(block)
		end
	end,
	superclass = function (self) 
		return rawget(self, "__superclass")
	end,
	allocate = luby.allocator,
	inherited = function (successor)
	end,
}

return Class
