require 'rubygems'
require 'sexp_processor'
require 'ruby_parser'
load 'src/last.rb'

# :stopdoc:
# REFACTOR: stolen from ruby_parser
class Regexp
	unless defined? ENC_NONE then
		ENC_NONE = /x/n.options
		ENC_EUC  = /x/e.options
		ENC_SJIS = /x/s.options
		ENC_UTF8 = /x/u.options

		CODES = {
			EXTENDED   => 'x',
			IGNORECASE => 'i',
			MULTILINE  => 'm',
			ENC_NONE   => 'n',
			ENC_EUC    => 'e',
			ENC_SJIS   => 's',
			ENC_UTF8   => 'u',
		}
	end
end
# :startdoc:

module Luby
	# based on shameless copy of ruby2ruby.rb
	class Compiler < SexpProcessor 
		LINE_LENGTH = 78

		# binary operation messages
		BINARY = [:<=>, :==, :<, :>, :<=, :>=, :-, :+, :*, :/, :%, :<<, :>>, :**, :'!=']
		LUA_BINARY = [:==, :<, :>, :<=, :>=, :-, :+, :*, :/, :%]

		# self class of current scope
		SELFK = "#selfk"


		##
		# Nodes that represent assignment and probably need () around them.
		#
		# TODO: this should be replaced with full precedence support :/

		ASSIGN_NODES = [
			:dasgn,
			:flip2,
			:flip3,
			:lasgn,
			:masgn,
			:attrasgn,
			:op_asgn1,
			:op_asgn2,
			:op_asgn_and,
			:op_asgn_or,
			:return,
			:if, # HACK
			:rescue,
		]

		def initialize # :nodoc:
			super
			self.auto_shift_type = true
			self.strict = true
			self.expected = LAST::Node

			@calls = []
			@tmpvar_serial = 0
			@last = LAST.new(defined? LUBY_VERSION)

			# self.debug[:defn] = /zsuper/
		end

		def ast
			@last
		end

		def compile(sexp)
			r = process(sexp).chunkize(ast)
			# p r
			r.evaluate
		end

		############################################################
		# Processors

		def process_alias(exp) # :nodoc:
			parenthesize "alias #{process(exp.shift)} #{process(exp.shift)}"
		end

		def process_and(exp) # :nodoc:
			ast.expr_binop("and", process(exp.shift), process(exp.shift)).lineno exp.line
		end

		def process_arglist(exp) # custom made node # :nodoc:
			code = []
			until exp.empty? do
			  arg = exp.shift
			  to_wrap = arg.first == :rescue
			  arg_code = process arg
			  code << (to_wrap ? "(#{arg_code})" : arg_code)
			end
			code.join ', '
		end

		def process_args(exp) # :nodoc:
			args = []
			vararg = false

			until exp.empty? do
				arg = exp.shift
				case arg
				when String then
					if arg[0] == '*' then
						vararg = true
						args << ast.identifier(arg.sub(1))
					else
						args << ast.identifier(arg)
					end
				when Symbol then
					args << ast.identifier(arg)
				when Sexp then
					case arg.first
					when :lasgn then
						arg.shift # remove lasgn
						args << ast.identifier(arg.shift) # store symbol name only
					when :masgn then # TODO : think when it appears
						args << process(arg)
					else
						raise "unknown arg type #{arg.first.inspect}"
					end
				else
					raise "unknown arg type #{arg.inspect}"
				end
			end

			# "(#{args.join ', '})"
			args.insert(0, vararg)
			ast.tuple_stmt(args)
		end

		def process_array(exp) # :nodoc:
			"[#{process_arglist(exp)}]"
		end

		def process_attrasgn(exp) # :nodoc:
			receiver = process exp.shift
			name = exp.shift
			rhs  = exp.pop
			args = s(:array, *exp)
			exp.clear

			case name
			when :[]= then
				args = process args
				"#{receiver}#{args} = #{process rhs}"
			else
				raise "dunno what to do: #{args.inspect}" unless args.size == 1 # s(:array)
				name = name.to_s.sub(/=$/, '')
				if rhs && rhs != s(:arglist) then
					"#{receiver}.#{name} = #{process(rhs)}"
				else
					raise "dunno what to do: #{rhs.inspect}"
				end
			end
		end

		def process_back_ref(exp) # :nodoc:
			"$#{exp.shift}"
		end

		# TODO: figure out how to do rescue and ensure ENTIRELY w/o begin
		def process_begin(exp) # :nodoc:
			code = []
			code << "begin"
			until exp.empty?
				src = process(exp.shift)
				src = indent(src) unless src =~ /(^|\n)(rescue|ensure)/ # ensure no level 0 rescues
				code << src
			end
			code << "end"
			return code.join("\n")
		end

		def process_block(exp) # :nodoc:
			result = []

			line = exp.line
			exp << nil if exp.empty?
			until exp.empty? do
				code = exp.shift
				if code.nil? or code.first == :nil then
					result << ast.literal("# do nothing\n")
				else
					result << to_statement(process(code), code)
				end
			end
			if code then
				lastline = code.line
			else
				lastline = line
			end

			return ast.chunk(result, "luby", line, lastline).lineno(line)
		end

		def process_block_pass exp # :nodoc:
			raise "huh?: #{exp.inspect}" if exp.size > 1

			"&#{process exp.shift}"
		end

		def process_break(exp) # :nodoc:
			val = exp.empty? ? nil : process(exp.shift)
			# HACK "break" + (val ? " #{val}" : "")
			if val then
				"break #{val}"
			else
				"break"
			end
		end

		def to_statement(body, exp)
			return body if body.is(:stmt)
			return ast.new_statement_expr(body).lineno exp.line
		end

		def process_call(exp) # :nodoc:
			receiver_node_type = exp.first.nil? ? nil : exp.first.first
			receiver = process exp.shift

			name = exp.shift
			args = []

			# this allows us to do both old and new sexp forms:
			exp.push(*exp.pop[1..-1]) if exp.size == 1 && exp.first.first == :arglist

			@calls.push name

			in_context :arglist do
				until exp.empty? do
					#arg_type = exp.first.sexp_type
					#is_empty_hash = (exp.first == s(:hash))
					# p exp
					arg = process exp.shift
					args << arg
				end
			end

			# TODO : some special method should be turned into lua metatable calls
			# eg)
			# 	send => __index && __call
			#   method_missing => __index
			case name
			when *BINARY then
				if LUA_BINARY.include?(name) and args.length == 1 then # normal lua operator
					ast.expr_binop(name, receiver, args[0]).lineno exp.line
				else # operator which lua does not have. regarded as function call.
					ast.expr_method_call(receiver, name, args).lineno exp.line
				end
				# "(#{receiver} #{name} #{args.join(', ')})"
			when :[] then
				if args.length > 1 then 
					# multiple args for [] is not supported in lua. so translate to normal function call which name is "[]".
					ast.expr_method_call(receiver, "[]", args).lineno exp.line
				else # normal index operation for lua
					ast.expr_index(receiver, args[0]).lineno exp.line
				end
				# "#{receiver}[#{args.join(', ')}]"
			when :[]= then
				if args.length > 1 then 
					rhs = args.pop
					# multiple args for [] is not supported in lua. so translate to normal function call which name is "[]=".
					ast.expr_method_call(receiver, "[]=", rhs).lineno exp.line
				else
					rhs = args.pop
					# index + assignment
					ast.assignment_expr([ast.expr_index(receiver, args[0]).lineno(exp.line)], [rhs]).lineno exp.line
				end
			when :"!" then
				ast.expr_unop('not', receiver).lineno exp.line
			when :"-@" then
				ast.expr_unop('-', receiver).lineno exp.line
			when :"+@" then
				ast.expr_method_call(receiver, "+@", []).lineno exp.line
			else
				if receiver then
					ast.expr_method_call(receiver, name, args).lineno exp.line
				else
					call_no_receiver(ast.identifier("self"), name, *args).lineno exp.line
					# ast.expr_function_call(ast.identifier(name), args).lineno exp.line
				end
			end
			ensure
			@calls.pop
		end

		def process_case(exp) # :nodoc:
			result = []
			expr = process exp.shift
			if expr then
				result << "case #{expr}"
			else
				result << "case"
			end
			until exp.empty?
				pt = exp.shift
				if pt and pt.first == :when
					result << "#{process(pt)}"
				else
					code = indent(process(pt))
					code = indent("# do nothing") if code =~ /^\s*$/
					result << "else\n#{code}"
				end
			end
			result << "end"
			result.join("\n")
		end

		def add_constant(symbol_ast, value_ast)
			# "#{lhs} = #{rhs}"
			call_no_receiver(ast.identifier(SELFK), "const_set", symbol_ast, value_ast)
		end
		def process_cdecl(exp) # :nodoc:
			lhs = exp.shift
			lhs = process lhs if Sexp === lhs
			unless exp.empty? then
				rhs = process(exp.shift)
			end
			add_constant(ast.literal(lhs), rhs).lineno exp.line
		end

		def process_class(exp) # :nodoc:
			# "#{exp.comments}class #{util_module_or_class(exp, true)}"
			util_module_or_class(exp, true).lineno exp.line
		end

		def process_colon2(exp) # :nodoc:
			"#{process(exp.shift)}::#{exp.shift}"
		end

		def process_colon3(exp) # :nodoc:
			"::#{exp.shift}"
		end

		def process_const(exp) # :nodoc:
			# exp.shift.to_s
			# check subtree also
			call_no_receiver(ast.identifier(SELFK), "const_get", ast.literal(exp.shift), ast.literal(true))
		end

		def process_cvar(exp) # :nodoc:
			# "#{exp.shift}"
			ast.expr_property(ast.identifier("self"), exp.shift)
		end

		def process_cvasgn(exp) # :nodoc:
			"#{exp.shift} = #{process(exp.shift)}"
		end

		def process_cvdecl(exp) # :nodoc:
			# "#{exp.shift} = #{process(exp.shift)}"
			ast.assignment_expr([ast.expr_property(ast.identifier("self"), exp.shift)], [process(exp.shift)]).lineno exp.line
		end

		def process_defined(exp) # :nodoc:
			"defined? #{process(exp.shift)}"
		end

		def create_function(exp)
			firstline = exp.line
			#p "create_fnction:" + exp.to_s
			type1 = exp[1].first
			type2 = exp[2].first rescue nil
			expect = [:ivar, :iasgn, :attrset]

			# s(name, args, ivar|iasgn|attrset) TODO : think when it appears 
			if exp.size == 3 and type1 == :args and expect.include? type2 then
				name = exp.first # don't shift in case we pass through
				case type2
				when :ivar then
					ivar_name = exp.ivar.last

					meth_name = ivar_name.to_s[1..-1].to_sym
					expected = s(meth_name, s(:args), s(:ivar, ivar_name))

					if exp == expected then
						exp.clear
						return "attr_reader #{name.inspect}"
					end
				when :attrset then
					# TODO: deprecate? this is a PT relic
					exp.clear
					return "attr_writer :#{name.to_s[0..-2]}"
					when :iasgn then
					ivar_name = exp.iasgn[1]
					meth_name = "#{ivar_name.to_s[1..-1]}=".to_sym
					arg_name = exp.args.last
					expected = s(meth_name, s(:args, arg_name),
						s(:iasgn, ivar_name, s(:lvar, arg_name)))

					if exp == expected then
						exp.clear
						return "attr_writer :#{name.to_s[0..-2]}"
					end
				else
					raise "Unknown defn type: #{exp.inspect}"
				end
			end

			comm = exp.comments
			name = exp.shift
			tpl = process exp.shift ## invokes process_args

			exp.shift if exp == s(s(:nil)) # empty it out of a default nil expression

			# REFACTOR: use process_block but get it happier wrt parenthesize
			body = []
			until exp.empty? do
				code = exp.shift
				tmp = process(code).lineno code.line
				#p code

				body << (tmp.expr? ? ast.new_statement_expr(tmp) : tmp)
			end

			if code then
				lastline = code.line
			else
				lastline = firstline
			end

			args = tpl.args.first
			vararg = args.shift

			tmp = ast.block_stmt(body).range(firstline, lastline)
			# p tmp.evaluate
			body_block,changed = tmp.each_last_expr_with(:assignment_expr) do |e|
				#p "last_expr:" + e.to_s
				e.as_return_value(ast, lastline)
			end
			# p "expr_function:" + firstline.to_s + "|" + lastline.to_s

			return ast.literal(name), ast.expr_function(args, ast.newscope(body_block), 
				{ :vararg => vararg, :firstline => firstline, :lastline => lastline }).lineno(exp.line)
		end

		def call_no_receiver(this, method, *args)
			ast.expr_function_call(ast.expr_function_call(ast.identifier("self_indexer"), [this, ast.literal(method)]), args.insert(0, this))
		end

		def process_defn(exp) # :nodoc:


			#body << indent("# do nothing") if body.empty?
			name, body = create_function(exp)
			call_no_receiver(ast.identifier("self"), "define_method", name, body)

			#return "#{comm}def #{name}#{args}\n#{body}\nend".gsub(/\n\s*\n+/, "\n")
		end

		def process_defs(exp) # :nodoc:
			lhs  = exp.shift
			#var = [:self, :cvar, :dvar, :ivar, :gvar, :lvar].include? lhs.first
			lhs = process(lhs) #if lhs === Sexp
			tmp = exp.shift
			tmp = process(tmp) if tmp === Sexp
			# lhs = "(#{lhs})" unless var

			exp.unshift tmp
			name, body = create_function(exp)
			call_no_receiver(ast.expr_index(lhs, ast.literal(tmp)), "define_method", name, body)
		end

		def process_dot2(exp) # :nodoc:
			"(#{process exp.shift}..#{process exp.shift})"
		end

		def process_dot3(exp) # :nodoc:
			"(#{process exp.shift}...#{process exp.shift})"
		end

		def process_dregx(exp) # :nodoc:
			options = re_opt exp.pop if Fixnum === exp.last
			"/" << util_dthing(:dregx, exp) << "/#{options}"
		end

		def process_dregx_once(exp) # :nodoc:
			process_dregx(exp) + "o"
		end

		def process_dstr(exp) # :nodoc:
			"\"#{util_dthing(:dstr, exp)}\""
		end

		def process_dsym(exp) # :nodoc:
			":\"#{util_dthing(:dsym, exp)}\""
		end

		def process_dxstr(exp) # :nodoc:
			"`#{util_dthing(:dxstr, exp)}`"
		end

		def process_ensure(exp) # :nodoc:
			body = process exp.shift
			ens  = exp.shift
			ens  = nil if ens == s(:nil)
			ens  = process(ens) || "# do nothing"
			ens = "begin\n#{ens}\nend\n" if ens =~ /(^|\n)rescue/

			body.sub!(/\n\s*end\z/, '')
			body = indent(body) unless body =~ /(^|\n)rescue/

			return "#{body}\nensure\n#{indent ens}"
		end

		def process_evstr(exp) # :nodoc:
			exp.empty? ? '' : process(exp.shift)
		end

		def process_false(exp) # :nodoc:
			ast.literal(false)
		end

		def process_flip2(exp) # :nodoc:
			"#{process(exp.shift)}..#{process(exp.shift)}"
		end

		def process_flip3(exp) # :nodoc:
			"#{process(exp.shift)}...#{process(exp.shift)}"
		end

		def process_for(exp) # :nodoc:
			recv = process exp.shift
			iter = process exp.shift
			body = exp.empty? ? nil : process(exp.shift)

			result = ["for #{iter} in #{recv} do"]
			result << indent(body ? body : "# do nothing")
			result << "end"

			result.join("\n")
		end

		def process_gasgn(exp) # :nodoc:
			process_iasgn(exp)
		end

		def process_gvar(exp) # :nodoc:
			return exp.shift.to_s
		end

		def process_hash(exp) # :nodoc:
			result = []

			until exp.empty?
				lhs = process(exp.shift)
				rhs = exp.shift
				t = rhs.first
				rhs = process rhs
				rhs = "(#{rhs})" unless [:lit, :str].include? t # TODO: verify better!

				result << "#{lhs} => #{rhs}"
			end

			return result.empty? ? "{}" : "{ #{result.join(', ')} }"
		end

		def process_iasgn(exp) # :nodoc:
			lhs = exp.shift
			if exp.empty? then # part of an masgn
				lhs.to_s
			else
				# "#{lhs} = #{process exp.shift}"
				result, change = do_assign(exp, ast.expr_property(ast.identifier("self"), lhs, exp.line), (process exp.shift))
				return result
			end
		end

		def tmpvar_name(exp)
			@tmpvar_serial = (@tmpvar_serial + 1)
			"tmp_#{exp.line}_#{@tmpvar_serial}"
		end
		def process_if(exp) # :nodoc:
			# p exp
			expand = ASSIGN_NODES.include? exp.first.first
			c = process exp.shift
			t = process exp.shift
			f = process exp.shift

			# p "c/t/f", c.to_s, t.to_s, f.to_s
			# p c.evaluate

			# if c then => tmp = c; if tmp then
			name = tmpvar_name exp
			tmpvar = ast.local_decl([name], []).lineno exp.line
			sym = ast.identifier(name)
			asgn = do_assign(exp, sym, c)

			#p "asgn c to tmp:" + asgn.evaluate
			#p f ? f.evaluate : "Nil"

			#c = "(#{c.chomp})" if c =~ /\n/

			if t then
				unless expand then
					if f then
						ast.tuple_stmt([
							tmpvar,
							asgn,
							ast.if_stmt([sym], [t.blockize(ast)], f.blockize(ast)).lineno(exp.line)
						])
						# "#{c} ? (#{t}) : (#{f})"
					else
						ast.tuple_stmt([
							tmpvar,
							asgn,
							ast.if_stmt([sym], [t.blockize(ast)], nil).lineno(exp.line)
						])
						# "#{t} if #{c}"
					end
				else
					# r = "if #{c} then\n#{indent(t)}\n"
					# r << "else\n#{indent(f)}\n" if f
					# r << "end"
					ast.tuple_stmt([
						tmpvar,
						asgn,
						ast.if_stmt([sym], [t.blockize(ast)], f.blockize(ast)).lineno(exp.line)
					])
				end

			elsif f
				tests = [ast.expr_unop('not', sym)]
				unless expand then
					ast.tuple_stmt([
						tmpvar,
						asgn,
						ast.if_stmt(tests, [f.blockize(ast)], nil).lineno(exp.line)
					])
				else
					ast.tuple_stmt([
						tmpvar,
						asgn,
						ast.if_stmt(tests, [f.blockize(ast)], nil).lineno(exp.line)
					])
				end
			else
				# empty if statement, just do it in case of side effects from condition
				ast.tuple_stmt([
					tmpvar,
					asgn
				])
			end
		end

		def process_iter(exp) # :nodoc:
			iter = process exp.shift
			args = exp.shift
			body = exp.empty? ? nil : process(exp.shift)

			args = case args
				when 0 then
					" ||"
				else
					a = process(args)[1..-2]
					a = " |#{a}|" unless a.empty?
					a
				end

			b, e = if iter == "END" then
					[ "{", "}" ]
				else
					[ "do", "end" ]
				end

			iter.sub!(/\(\)$/, '')

			# REFACTOR: ugh
			result = []
			result << "#{iter} {"
			result << args
			if body then
				result << " #{body.strip} "
			else
				result << ' '
			end
			result << "}"
			result = result.join
			return result if result !~ /\n/ and result.size < LINE_LENGTH

			result = []
			result << "#{iter} #{b}"
			result << args
			result << "\n"
			if body then
				result << indent(body.strip)
				result << "\n"
			end
			result << e
			result.join
		end

		def process_ivar(exp) # :nodoc:
			ast.expr_property(ast.identifier("self"), exp.shift).lineno exp.line
			#exp.shift.to_s
		end

		def do_assign(exp, left, right)
			result,changed = right.each_last_expr do |e|
				e.assign_to(ast, left, exp.line)
			end
			return result
		end

		def process_lasgn(exp) # :nodoc:
			sym = exp.shift
			var = ast.identifier(sym)
			decl = ast.local_decl([sym], []).lineno exp.line
			expr = process exp.shift
			#p "left:" + var.evaluate
			#p "right:" + expr.evaluate
			expr, changed = do_assign exp, var, expr
			r = ast.tuple_stmt([decl, expr])
			#p r.evaluate
			return r
			#s = "#{exp.shift}"
			#s += " = #{process exp.shift}" unless exp.empty?
			#s
		end

		def process_lit(exp) # :nodoc:
			obj = exp.shift
			case obj
			when Range then
				raise "unsupported literal: (#{obj.inspect})"
			# TODO : more literal support
			else
				ast.literal(obj)
			end
		end

		def process_lvar(exp) # :nodoc:
			ast.identifier(exp.shift)
		end

		def process_masgn(exp) # :nodoc:
			# s(:masgn, s(:array, s(:lasgn, :var), ...), s(:to_ary, <val>, ...))
			# => ast:local_decl({'var1', 'var2', ...}, {<val1>, <val2>, ...})
			# s(:iter, <call>, s(:args, s(:masgn, :a, :b)), <body>)
			# => TODO: maybe after iter support is done.

			case exp.first
			when Sexp then
				lhs = exp.shift
				rhs = exp.empty? ? nil : exp.shift

				case lhs.first
				when :array then
					lhs.shift # node type
					lhs = lhs.map do |l|
						case l.first
						when :masgn then
							# eg) a, (b, c), d = 1, 2, 3, 4π
							"(#{process(l)})"
						else
							process(l)
						end
					end
				else
					raise "no clue: #{lhs.inspect}"
				end

				unless rhs.nil? then
					t = rhs.first
					rhs = process rhs
					rhs = rhs[1..-2] if t == :array # FIX: bad? I dunno
					return "#{lhs.join(", ")} = #{rhs}"
				else
					return lhs.join(", ")
				end
			when Symbol then # block arg list w/ masgn
				result = exp.join ", "
				exp.clear
				"(#{result})"
			else
				raise "unknown masgn: #{exp.inspect}"
			end
		end

		def process_match(exp) # :nodoc:
			"#{process(exp.shift)}"
		end

		def process_match2(exp) # :nodoc:
			lhs = process(exp.shift)
			rhs = process(exp.shift)
			"#{lhs} =~ #{rhs}"
		end

		def process_match3(exp) # :nodoc:
			rhs = process(exp.shift)
			left_type = exp.first.sexp_type
			lhs = process(exp.shift)

			if ASSIGN_NODES.include? left_type then
				"(#{lhs}) =~ #{rhs}"
			else
				"#{lhs} =~ #{rhs}"
			end
		end

		def process_module(exp) # :nodoc:
			util_module_or_class(exp)
			# "#{exp.comments}module #{util_module_or_class(exp)}"
		end

		def process_next(exp) # :nodoc:
			val = exp.empty? ? nil : process(exp.shift)
			if val then
				"next #{val}"
			else
				"next"
			end
		end

		def process_nil(exp) # :nodoc:
			"nil"
		end

		def process_not(exp) # :nodoc:
			"(not #{process exp.shift})"
		end

		def process_nth_ref(exp) # :nodoc:
			"$#{exp.shift}"
		end

		def process_op_asgn1(exp) # :nodoc:
			# [[:lvar, :b], [:arglist, [:lit, 1]], :"||", [:lit, 10]]
			lhs = process(exp.shift)
			index = process(exp.shift)
			msg = exp.shift
			rhs = process(exp.shift)

			"#{lhs}[#{index}] #{msg}= #{rhs}"
		end

		def process_op_asgn2(exp) # :nodoc:
			# [[:lvar, :c], :var=, :"||", [:lit, 20]]
			lhs = process(exp.shift)
			index = exp.shift.to_s[0..-2]
			msg = exp.shift

			rhs = process(exp.shift)

			"#{lhs}.#{index} #{msg}= #{rhs}"
		end

		def process_op_asgn_and(exp) # :nodoc:
			# a &&= 1
			# [[:lvar, :a], [:lasgn, :a, [:lit, 1]]]
			exp.shift
			process(exp.shift).sub(/\=/, '&&=')
		end

		def process_op_asgn_or(exp) # :nodoc:
			# a ||= 1
			# [[:lvar, :a], [:lasgn, :a, [:lit, 1]]]
			exp.shift
			process(exp.shift).sub(/\=/, '||=')
		end

		def process_or(exp) # :nodoc:
			"(#{process exp.shift} or #{process exp.shift})"
		end

		def process_postexe(exp) # :nodoc:
			"END"
		end

		def process_redo(exp) # :nodoc:
			"redo"
		end

		def process_resbody exp # :nodoc:
			args = exp.shift
			body = finish(exp)
			body << "# do nothing" if body.empty?

			name =   args.lasgn true
			name ||= args.iasgn true
			args = process(args)[1..-2]
			args = " #{args}" unless args.empty?
			args += " => #{name[1]}" if name

			"rescue#{args}\n#{indent body.join("\n")}"
		end

		def process_rescue exp # :nodoc:
			body = process(exp.shift) unless exp.first.first == :resbody
			els  = process(exp.pop)   unless exp.last.first  == :resbody

			body ||= "# do nothing"
			simple = exp.size == 1 && !exp.resbody.block && exp.resbody.size <= 3

			resbodies = []
			until exp.empty? do
				resbody = exp.shift
				simple &&= resbody[1] == s(:array)
				simple &&= resbody[2] != nil && resbody[2].node_type != :block
				resbodies << process(resbody)
			end

			if els then
				"#{indent body}\n#{resbodies.join("\n")}\nelse\n#{indent els}"
			elsif simple then
				resbody = resbodies.first.sub(/\n\s*/, ' ')
				"#{body} #{resbody}"
			else
				"#{indent body}\n#{resbodies.join("\n")}"
			end
		end

		def process_retry(exp) # :nodoc:
			"retry"
		end

		def process_return(exp) # :nodoc:
			# HACK return "return" + (exp.empty? ? "" : " #{process exp.shift}")

			if exp.empty? then
				return "return"
			else
				return "return #{process exp.shift}"
			end
		end

		def process_sclass(exp) # :nodoc:
			"class << #{process(exp.shift)}\n#{indent(process_block(exp))}\nend"
		end

		def process_self(exp) # :nodoc:
			ast.identifier("self")
		end

		def process_splat(exp) # :nodoc:
		if exp.empty? then
			"*"
		else
			"*#{process(exp.shift)}"
		end
		end

		def process_str(exp) # :nodoc:
			return ast.literal(exp.shift)
		end

		def process_super(exp) # :nodoc:
			args = finish exp

			"super(#{args.join(', ')})"
		end

		def process_svalue(exp) # :nodoc:
			code = []
			until exp.empty? do
				code << process(exp.shift)
			end
			code.join(", ")
		end

		def process_to_ary(exp) # :nodoc:
			process(exp.shift)
		end

		def process_true(exp) # :nodoc:
			ast.literal(true)
		end

		def process_undef(exp) # :nodoc:
			"undef #{process(exp.shift)}"
		end

		def process_until(exp) # :nodoc:
			cond_loop(exp, 'until')
		end

		def process_valias(exp) # :nodoc:
			"alias #{exp.shift} #{exp.shift}"
		end

		def process_when(exp) # :nodoc:
			src = []

			if self.context[1] == :array then # ugh. matz! why not an argscat?!?
				val = process(exp.shift)
				exp.shift # empty body
				return "*#{val}"
			end

			until exp.empty?
				cond = process(exp.shift).to_s[1..-2]
				code = indent(finish(exp).join("\n"))
				code = indent "# do nothing" if code =~ /\A\s*\Z/
				src << "when #{cond} then\n#{code.chomp}"
			end

			src.join("\n")
		end

		def process_while(exp) # :nodoc:
			cond_loop(exp, 'while')
		end

		def process_xstr(exp) # :nodoc:
			"`#{process_str(exp)[1..-2]}`"
		end

		def process_yield(exp) # :nodoc:
			args = []
			until exp.empty? do
				args << process(exp.shift)
			end

			unless args.empty? then
				"yield(#{args.join(', ')})"
			else
				"yield"
			end
		end

		def process_zsuper(exp) # :nodoc:
			"super"
		end

		############################################################
		# Rewriters:

		def rewrite_attrasgn exp # :nodoc:
			if context.first(2) == [:array, :masgn] then
				exp[0] = :call
				exp[2] = exp[2].to_s.sub(/=$/, '').to_sym
			end

			exp
		end

		def rewrite_ensure exp # :nodoc:
			exp = s(:begin, exp) unless context.first == :begin
			exp
		end

		def rewrite_resbody exp # :nodoc:
			raise "no exception list in #{exp.inspect}" unless exp.size > 2 && exp[1]
			raise exp[1].inspect if exp[1][0] != :array
			# for now, do nothing, just check and freak if we see an errant structure
			exp
		end

		def rewrite_rescue exp # :nodoc:
			complex = false
			complex ||= exp.size > 3
			complex ||= exp.resbody.block
			complex ||= exp.resbody.size > 3
			complex ||= exp.find_nodes(:resbody).any? { |n| n[1] != s(:array) }
			complex ||= exp.find_nodes(:resbody).any? { |n| n.last.nil? }
			complex ||= exp.find_nodes(:resbody).any? { |n| n[2] and n[2].node_type == :block }

			handled = context.first == :ensure

			exp = s(:begin, exp) if complex unless handled

			exp
		end

		def rewrite_svalue(exp) # :nodoc:
			case exp.last.first
			when :array
				s(:svalue, *exp[1][1..-1])
			when :splat
				exp
			else
				raise "huh: #{exp.inspect}"
			end
		end

		############################################################
		# Utility Methods:

		##
		# Generate a post-or-pre conditional loop.

		def cond_loop(exp, name)
			cond = process(exp.shift)
			body = process(exp.shift)
			head_controlled = exp.shift

			body = indent(body).chomp if body

			code = []
			if head_controlled then
				code << "#{name} #{cond} do"
				code << body if body
				code << "end"
			else
				code << "begin"
				code << body if body
				code << "end #{name} #{cond}"
			end
			code.join("\n")
		end

		##
		# Utility method to escape something interpolated.

		def dthing_escape type, lit
			lit = lit.gsub(/\n/, '\n')
			case type
			when :dregx then
				lit.gsub(/(\A|[^\\])\//, '\1\/')
			when :dstr, :dsym then
				lit.gsub(/"/, '\"')
			when :dxstr then
				lit.gsub(/`/, '\`')
			else
				raise "unsupported type #{type.inspect}"
			end
		end

		##
		# Process all the remaining stuff in +exp+ and return the results
		# sans-nils.

		def finish exp # REFACTOR: work this out of the rest of the processors
			body = []
			until exp.empty? do
				body << process(exp.shift)
			end
			body.compact
		end

		##
		# Indent all lines of +s+ to the current indent level.

		def indent(s)
			s.to_s.split(/\n/).map{|line| @indent + line}.join("\n")
		end

		##
		# Wrap appropriate expressions in matching parens.

		def parenthesize exp
			case self.context[1]
			when nil, :defn, :defs, :class, :sclass, :if, :iter, :resbody, :when, :while then
				exp
			else
				"(#{exp})"
			end
		end

		##
		# Return the appropriate regexp flags for a given numeric code.

		def re_opt options
			bits = (0..8).map { |n| options[n] * 2**n }
			bits.delete 0
			bits.map { |n| Regexp::CODES[n] }.join
		end

		##
		# Return a splatted symbol for +sym+.

		def splat(sym)
			:"*#{sym}"
		end

		##
		# Utility method to generate something interpolated.

		def util_dthing(type, exp)
			s = []

			# first item in sexp is a string literal
			s << dthing_escape(type, exp.shift)

			until exp.empty?
				pt = exp.shift
				case pt
				when Sexp then
					case pt.first
					when :str then
						s << dthing_escape(type, pt.last)
					when :evstr then
						s << '#{' << process(pt) << '}' # do not use interpolation here
					else
						raise "unknown type: #{pt.inspect}"
					end
				else
					raise "unhandled value in d-thing: #{pt.inspect}"
				end
			end

			s.join
		end

		##
		# Utility method to generate ether a module or class.

		def util_module_or_class(exp, is_class=false)
			result = []

			firstline = exp.line
			name = exp.shift
			name = process name if Sexp === name
			superk = process(exp.shift) if is_class

			body = []
			body << (ast.local_decl([SELFK], [ast.identifier("self")]).lineno firstline)
			begin
				body << ast.new_statement_expr(process(tmp = exp.shift)) unless exp.empty?
			end until exp.empty?

			if tmp then
				lastline = tmp.line
			else
				lastline = firstline
			end

			# p "util_module_or_class:" + firstline.to_s + "|" + lastline.to_s

			body = ast.newscope(ast.block_stmt(body).range(firstline, lastline))
			if is_class then
				ast.expr_function_call(ast.identifier("class"), [ast.literal(name), ast.literal(superk),
					ast.expr_function([ast.identifier("self")], body, {:firstline => firstline, :lastline => lastline})
				])
			else
				ast.expr_function_call(ast.identifier("module"), [ast.literal(name),
					ast.expr_function([ast.identifier("self")], body, {:firstline => firstline, :lastline => lastline})
				])
			end
		end
	end
end
