class Klass
	V = "v"
	@@w = "w"
	def initialize(x)
		@x = x
	end
	def self.y
		"y"
	end
	def z
		"z"
	end
	def func(a, b, c)
		V + @@w + x + Klass.y + z + a + b + c
	end
end

p Klass.new("x").func 1, 2, 3

