package.path = package.path .. ";./ext/luajit-lang-toolkit/?.lua;"
local ast = require('lua-ast').New()
local dump = require('syntax').dump
local generator = require('generator')

local function compile(src)
	local ast_builder,err = loadstring(([[
        local ast = select(1,...)
        return %s
    ]]):format(src))
	if not ast_builder then
		error(err)
	end
	local tree = ast_builder(ast)
    print(dump(tree))
    local luacode = generator(tree, "luby")

    -- dump the bytecode
    local jbc = require("jit.bc")
    local fn = assert(loadstring(luacode))
    jbc.dump(fn, nil, true)

    return luacode
end

local luacode = compile(arg[1])
local fn = assert(loadstring(luacode))
fn()
