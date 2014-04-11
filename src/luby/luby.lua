local luby = require ('runtime')
-- fundamental modules & classes
luby.Object = require ('bootstrap/init')
luby.Class = luby.Object:const_get("Class")
luby.Module = luby.Object:const_get("Module")

-- modules & classes for ruby literal
--[[
luby.class("Array", require ('class/array'))
luby.class("Hash", require ('class/hash'))
luby.class("String", require ('class/string'))
luby.class("Regexp", require ('class/regexp'))
luby.class("Range", require ('class/range'))
luby.class("Numeric", require ('class/numeric'))
luby.class("Float", require ('class/float'), "Numeric")
luby.class("Integer", require ('class/integer'), "Numeric")
luby.class("Bignum", require ('class/bignum'), "Numeric")
luby.class("Fixnum", require ('class/fixnum'), "Numeric")
luby.class("Rational", require ('class/rational'), "Numeric")
luby.class("Complex", require ('class/complex'), "Numeric")	
luby.module("Enumerable", require ('module/enumerable'))
luby.module("Comparable", require ('module/comparable'))

-- ruby bindings for luajit FFI
luby.class("FFI", require ('class/ffi'))
]]

-- top level scope is Object.
luby.self = luby.Object

-- export _R as global symbol for easy accessing ruby namespace from lua program
return luby