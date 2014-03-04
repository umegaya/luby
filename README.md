[![Build Status](https://travis-ci.org/umegaya/luby.png?branch=master)](https://travis-ci.org/umegaya/luby)

luby
====

- ruby implementation by luajit VM
- powered by [luajit-lang-toolkit](https://github.com/franko/luajit-lang-toolkit), [ruby-parser](https://github.com/seattlerb/ruby_parser), [sexp-processor](https://github.com/seattlerb/sexp_processor)
- ruby syntax + luajit performance & ffi



how it works
============

- luby == (luajit + luajit bytecode files)
- luajit bytecode files == (luajit_lang_toolkit + lua-compiled ruby files)
- lua-compiled ruby files == (ruby_parser + sexp_processor)



how ruby-specified code converts
================================
- basic idea is last evaluate expression is value of if statement or block statement.
- so move return or assignment to last evaluated expression.

```
a = b = c
=>
b = c
a = b
```

```
a = def f(x) p x end
=>
function f(x) print(x) end
a = nil # in ruby it actually be nil
```

```
a = if true then 1 else 2 end
=>
if true then a = 1 else a = 2 end
```

```
return if true then 1 else 2 end
=>
if true then return 1 else return 2 end
```

```
def fn
  "string"
end
=>
function fn()
  return "string"
end
```



how ruby state express in lua _G
================================

```
_G 
 +- _R 
     +- class
         +- Object
         +- Array
         ...
     +- scope 
         +- 0
         +- 1
         +- 2
         ...
         +- N (global)
```


