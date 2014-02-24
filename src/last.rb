module Luby
	class LAST
		attr :luby
		def initialize(is_luby)
			@luby = is_luby
			if @luby then
				@ast_builder = nil ## TODO: load lua-ast.New when luby can run by itself
			end
		end
		def method_missing(m, *args)
			if luby then
				# if @luby, lua-ast will be exist in same memory.
				return @ast_builder.send m.to_sym, *args
			else
				# otherwise lua-ast will be passed to luajit as string arugument.
				return Node.new.setup(m, args)
			end
		end
		class Node 
			def initialize
			end
			def setup(m, args)
				@m = m
				@args = args # include lineno info
				return self
			end
			def line 
				if @args.length > 0 then
					@args[@args.length - 1] 
				else
					nil
				end
			end
			def chunkize(last)
				unless @m == :chunk then
					return last.chunk([last.new_statement_expr(self, line)])
				end
				return self
			end
			def self.to_str(a)
				if a.is_a? String or a.is_a? Symbol then
					return "'#{a}'"
				elsif a.is_a? Array and a.length > 0 then
					r = "{" + Node.to_str(a[0])
					a[1..-1].each do |arg|
						r = (r + "," + Node.to_str(arg))
					end
					return r + "}"
				elsif a.is_a? Node
					return a.evaluate
				else
					return a.to_s
				end
			end
			def evaluate
				r = "ast:#{@m}("
				if @args.length > 0 then
					r = (r + Node.to_str(@args[0]))
					@args[1..-1].each do |a|
						r = (r + "," + Node.to_str(a))
					end
				end
				return (r + ")")
			end
		end
	end
end