local luby = require ('runtime')
local Module = require ('bootstrap/module')

-- class body
local Kernel = Module:new(function (klass)
	klass.__name = "Kernel"
	klass.__methods = {
		["print"] = function (self,...)
			local cnt = select('#',...)
			-- TODO : print prints same as ruby does.
			if cnt == 0 then
				print(luby["$_"])
			else
				print(...)
			end
		end,
	}
end)

return Kernel
