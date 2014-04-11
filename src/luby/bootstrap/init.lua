local Module = require ('bootstrap/module')
local Class = require ('bootstrap/class')
local BasicObject = require ('bootstrap/basic_object')
local Kernel = require ('bootstrap/kernel')
local Object = require ('bootstrap/object')

-- hackable completion of ruby object hirarchy
-- (force set Object as ancestor of Module)
Module.__superclass = Object
Module:include(Object)
Module:private(
	"alias_method",
	"append_features",
	"attr",
	"attr_accessor",
	"attr_reader",
	"attr_writer",
	"class_exec",
	"class_variable_get",
	"class_variable_set",
	"define_method",
	"extend_object",
	"extended",
	"include",
	"included",
	"method_added",
	"method_removed",
	"method_undefined", 
	"module_exec",
	"module_function",
	"private",
	"private_constant",
	"protected",
	"public",
	"public_constant",
	"remove_const",
	"remove_method",
	"singleton_class?",
	"undef_method"
)

Class:private(
	"inherited"
)

-- add classes as constant of Object.
BasicObject:const_set("BasicObject", BasicObject)
Object:const_set("Module", Module)
Object:const_set("Class", Class)
Object:const_set("BasicObject", BasicObject)
Object:const_set("Kernel", Kernel)
Object:const_set("Object", Object)

return Object