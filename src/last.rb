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
			TO_STR_PRETTY_PRINT = true
			def initialize
			end
			def setup(m, args)
				@m = m
				@line = nil
				@args = resolve_tuple(args, (is(:tuple_stmt) or is(:chunk) or is(:block_stmt)))
				return self
			end
			def self.ln
				TO_STR_PRETTY_PRINT ? "\n" : ""
			end
			def is(m)
				return @m[m.to_s]
			end
			def stmt?
				is(:stmt) or 
					is(:chunk) or 
					is(:assignment_expr) or 
					is(:function_decl) or 
					is(:local_function_decl) or 
					is(:new_statement_expr)
			end
			def expr?
				(is(:expr) and (not is(:new_statement_expr))) or 
					is(:identifier) or 
					is(:concat_append) or 
					is(:literal)
			end
			def set_type(t)
				@m = t
				self
			end
			def args
				@args
			end
			def resolve_tuple(args, flatten)
				# convert tuple node to valid last node(s)
				# tuple node in tuple or chunk or block_stmt is flattened. (each element merged into parent node array.)
				# otherwise it converted to block_stmt.
				#p "start resolve_tuple", Node.to_str(args)
				result = []
				args.each do |a|
					if a.is_a? Node and a.is(:tuple_stmt) then
						if flatten then
							result = (result + a.args[0])
						else
							result.push(a.set_type(:block_stmt))
						end
					elsif a.is_a? Array then
						result.push(resolve_tuple(a, flatten))
					else
						result.push(a)
					end
				end
				return result
			end
			def lineno(no)
				@line = no
				self
			end
			def range(first, last)
				@first = first
				@last = last
				self
			end
			def args 
				@args
			end
			def get_lineno
				@line
			end
			def kind
				@m.to_s
			end
			def self.linerange(node)
				if not node.is_a? Node then
					return nil,nil
				end
				#p "nodekind:" + node.kind
				min, max = node.get_lineno, node.get_lineno
				node.args.each do |a|
					if a.is_a? Node then
						tmin,tmax = Node.linerange(a)
						if tmin and ((not min) or (tmin < min)) then
							min = tmin
						end
						if tmax and ((not max) or (tmax > max)) then
							max = tmax
						end	
					elsif a.is_a? Array then
						a.each do |aa|
							tmin,tmax = Node.linerange(aa)
							if tmin and ((not min) or (tmin < min)) then
								min = tmin
							end
							if tmax and ((not max) or (tmax > max)) then
								max = tmax
							end	
						end
					end
				end
				#p "nodekind:" + node.kind + " result=" + min.to_s + "|" + max.to_s
				return min,max
			end
			# ruby requires evaluate chunk or statement which luajit VM not supports.
			# instead of evaluating chunk, statement, find last expression and block do something 
			def each_last_expr(&block)
				#p "each_last_expr:" + self.evaluate
				if expr? then
					return block.call(self), true
				end
				if is(:if_stmt) then
					#p "ifstmt:" + Node.to_str(self)
					#p "then:" + Node.to_str(@args[1])
					#p "else:" + Node.to_str(@args[2])
					# search expression to both path.
					@args[1].each do |a| 
						a.each_last_expr(&block)
					end
					@args[2].each_last_expr(&block)
					return self, false
				end
				parent = nil
				node = @args
				while node.is_a? Array 
					parent = node
					node = node.last
				end
				#p "each_last_expr2:" + Node.to_str(node)
				if node.is_a? Node then
					#p "node:" + node.evaluate
					v, changed = node.each_last_expr(&block)
					#if changed then
					#	p "changed:to: " + v.evaluate
					#end
					if changed then
						if v.is_a? Node and v.is(:tuple_stmt) then
							parent.pop # last element will be replaced by *v.args[0]
							parent.push(*(v.args[0]))
						else
							parent[parent.length - 1] = v
						end
					end
					return self, changed
				end
				return self, false
			end
			# e.g) a = b = c => b = c; a = b
			def assign_to(ast, exp, line)
				#p "assign_to----:" + evaluate + "|" + exp.evaluate
				if is(:assignment_expr) then
					ast.tuple_stmt([
						self,
						ast.assignment_expr([exp], @args[0]).lineno(line)
					])
				elsif expr? then
					ast.assignment_expr([exp], [self]).lineno(line)
				else 
					raise "invalid node to assign:" + @m
				end
			end
			def chunkize(last, name = nil)
				unless is(:chunk) then
					if stmt? then
						body = self
						firstline, lastline = Node.linerange(self)
					else
						body = last.new_statement_expr(self).lineno(@line)
						firstline, lastline = Node.linerange(self)
					end
					# p "first/last:" + firstline.to_s + "|" + lastline.to_s
					return last.newscope(last.chunk([body], (name or "luby"), firstline, lastline))
				end
				return last.newscope(self)
			end
			def blockize(last)
				unless is(:block_stmt) then
					if is(:tuple_stmt) then
						return set_type(:block_stmt)
					elsif stmt?
						return last.block_stmt([self]).lineno(@line)
					else
						return last.block_stmt([last.new_statement_expr(self)]).lineno(@line)
					end
				end
				self
			end
			def self.to_str(a)
				if not a then
					return a.nil? ? "nil" : "false"
				elsif a.is_a? String or a.is_a? Symbol then
					return "'#{a}'"
				elsif a.is_a? Array then
					r = "{"
					if a.length > 0 then
						r = (r + Node.to_str(a[0]))
						a[1..-1].each do |arg|
							r = (r + "," + Node.to_str(arg))
						end
					end
					return r + "}"
				elsif a.is_a? Hash then
					r = "{"
					a.each do |k,v| 
						r = (r + k.to_s + "=" + Node.to_str(v) + ",")
					end
					return r + "}"					
				elsif a.is_a? Node
					return a.evaluate
				else
					return a.to_s
				end
			end
			def evaluate
				if is(:newscope) then
					return "ast:scope(function (ast) return #{@args[0].evaluate} end)"
				end
				if is(:break_stmt) then
					return "ast:break_stmt(#{@line})"
				end
				r = "ast:#{@m}("
				if @args.length > 0 then
					r = (r + Node.to_str(@args[0]))
					@args[1..-1].each do |a|
						r = (r + "," + Node.to_str(a))
					end
				end
				if @first and @last then
					return (r + ",#{@first},#{@last})")
				elsif @line then
					return (r + ",#{@line})")
				else
					return (r + ")")
				end
			end
			alias :to_s :evaluate
		end
	end
end