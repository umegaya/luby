local MetaModule = require ('bootstrap/meta/module')
local MetaClass = require ('bootstrap/meta/class')

local Module = MetaClass:allocate()
MetaModule.initialize(Module)
Module.__methods = MetaModule
Module.__name = "Module"

return Module
