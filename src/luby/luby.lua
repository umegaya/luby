local luby = require ('runtime')
-- fundamental modules & classes
luby.Object = require ('bootstrap/init')
luby.Class = luby.Object:const_get("Class")
luby.Module = luby.Object:const_get("Module")

-- top level scope is Object.
luby.self = luby.Class:new(luby.Object, function (klass)
	klass:private()
end)
luby["#selfk"] = luby.Object


-- modules & classes for ruby literal
luby.class("String", nil, require ('class/string'))
luby.class("Numeric", nil, require ('class/numeric'))
luby.class("TrueClass", nil, require ('class/true_class'))
luby.class("FalseClass", nil, require ('class/false_class'))
luby.class("NilClass", nil, require ('class/nil_class'))
luby.class("Proc", nil, require ('class/proc'))
--[[
luby.class("Array", require ('class/array'))
luby.class("Hash", require ('class/hash'))
luby.class("Regexp", require ('class/regexp'))
luby.class("Range", require ('class/range'))
luby.class("Float", "Numeric", require ('class/float'))
luby.class("Integer", "Numeric", require ('class/integer'))
luby.class("Bignum", "Numeric", require ('class/bignum'))
luby.class("Fixnum", "Numeric", require ('class/fixnum'))
luby.class("Rational", "Numeric", require ('class/rational'))
luby.class("Complex", "Numeric", require ('class/complex'))	
luby.module("Enumerable", require ('module/enumerable'))
luby.module("Comparable", require ('module/comparable'))

-- ruby bindings for luajit FFI
luby.class("FFI", require ('class/ffi'))
]]

-- set ruby class table to lua primitive types
luby.objectize_lua_primitives()

-- export _R as global symbol for easy accessing ruby namespace from lua program
return luby