require 'rubygems'
require 'ruby_parser'
load 'src/compiler.rb'

sexp = RubyParser.new.parse File.open(ARGV[0]).read
p sexp
ast = Luby::Compiler.new.compile sexp
p ast
system("luajit src/run.lua \"#{ast}\"")
