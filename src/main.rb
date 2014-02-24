require 'rubygems'
require 'ruby_parser'
load 'src/compiler.rb'

sexp = RubyParser.new.parse File.open(ARGV[0]).read
puts "------ S exp   ------"
p sexp
ast = Luby::Compiler.new.compile sexp
puts "------ lua AST ------"
# puts ast
system("luajit src/run.lua \"#{ast}\"")
