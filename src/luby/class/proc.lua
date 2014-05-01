local luby = require ('runtime')
return function (klass)
	luby.define_method(klass, "class", function (self)
		return klass
	end)
end
