local MetaModule = require ('bootstrap/meta/module')
local MetaClass = require ('bootstrap/meta/class')
local Module = require ('bootstrap/module')

local Class = MetaClass:allocate()
MetaModule.initialize(Class)
Class.__class = Class
Class.__superclass = Module
Class.__methods = MetaClass
table.insert(Class.__mixin, Module)
Module.__class = Class
Class.__name = "Class"

return Class