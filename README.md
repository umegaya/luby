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


