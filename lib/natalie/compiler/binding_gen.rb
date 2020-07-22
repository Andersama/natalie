class BindingGen
  def initialize
    @bindings = {}
    @undefine_singleton_methods = []
  end

  def binding(*args, **kwargs)
    b = Binding.new(*args, **kwargs)
    b.increment_name while @bindings[b.name]
    @bindings[b.name] = b
    b.write
  end

  def singleton_binding(*args, **kwargs)
    b = Binding.new(*args, singleton: true, **kwargs)
    b.increment_name while @bindings[b.name]
    @bindings[b.name] = b
    b.write
  end

  def undefine_singleton_method(rb_class, method)
    @undefine_singleton_methods << [rb_class, method]
  end

  def init
    puts 'void init_bindings(Env *env) {'
    @consts = {}
    @bindings.values.each do |binding|
      unless @consts[binding.rb_class]
        puts "    Value *#{binding.rb_class} = NAT_OBJECT->const_get(env, #{binding.rb_class.inspect}, true);"
        @consts[binding.rb_class] = true
      end
      puts "    #{binding.rb_class}->#{binding.define_method_name}(env, #{binding.rb_method.inspect}, #{binding.name});"
    end
    @undefine_singleton_methods.each do |rb_class, method|
      puts "    #{rb_class}->undefine_singleton_method(env, #{method.inspect});"
    end
    puts '}'
  end

  class Binding
    def initialize(rb_class, rb_method, cpp_class, cpp_method, argc:, pass_env:, pass_block:, return_type:, singleton: false)
      @rb_class = rb_class
      @rb_method = rb_method
      @cpp_class = cpp_class
      @cpp_method = cpp_method
      @argc = argc
      @pass_env = pass_env
      @pass_block = pass_block
      @return_type = return_type
      @singleton = singleton
      generate_name
    end

    attr_reader :rb_class, :rb_method, :cpp_class, :cpp_method, :argc, :pass_env, :pass_block, :return_type, :name

    def write
      if @singleton
        write_singleton_function
      else
        write_function
      end
    end

    def write_function
      puts <<-FUNC
Value *#{name}(Env *env, Value *self_value, ssize_t argc, Value **args, Block *block) {
    #{argc_assertion}
    #{cpp_class} *self = #{as_type 'self_value'};
    auto return_value = self->#{cpp_method}(#{args_to_pass});
    #{return_code}
}\n
      FUNC
    end

    def write_singleton_function
      puts <<-FUNC
Value *#{name}(Env *env, Value *, ssize_t argc, Value **args, Block *block) {
    #{argc_assertion}
    auto return_value = #{cpp_class}::#{cpp_method}(#{args_to_pass});
    #{return_code}
}\n
      FUNC
    end

    def args_to_pass
      case argc
      when :any
        [env_arg, 'argc', 'args', block_arg].compact.join(', ')
      when Range
        if argc.end
          ([env_arg] + args + [block_arg]).compact.join(', ')
        else
          [env_arg, 'argc', 'args', block_arg].compact.join(', ')
        end
      when Integer
        ([env_arg] + args + [block_arg]).compact.join(', ')
      end
    end

    def define_method_name
      "define#{@singleton ? '_singleton' : ''}_method"
    end

    def increment_name
      @name = @name.sub(/_binding(\d*)$/) { "_binding#{$1.to_i + 1}" }
    end

    private

    def argc_assertion
      case argc
      when :any
        ''
      when Range
        if argc.end
          "NAT_ASSERT_ARGC(#{argc.begin}, #{argc.end});"
        else
          "NAT_ASSERT_ARGC_AT_LEAST(#{argc.begin});"
        end
      when Integer
        "NAT_ASSERT_ARGC(#{argc});"
      else
        raise "Unknown argc: #{argc.inspect}"
      end
    end

    def env_arg
      if pass_env
        'env'
      end
    end

    def args
      (0...max_argc).map do |i|
        "argc > #{i} ? args[#{i}] : nullptr"
      end
    end

    def block_arg
      if pass_block
        'block'
      end
    end

    def as_type(value)
      if cpp_class == 'Value'
        value
      else
        underscored = cpp_class.sub(/Value/, '').gsub(/([a-z])([A-Z])/,'\1_\2').downcase
        "#{value}->as_#{underscored}()"
      end
    end

    def return_code
      case return_type
      when :bool
        'if (return_value) { return NAT_TRUE; } else { return NAT_FALSE; }'
      when :ssize_t, :int
        'return new IntegerValue { env, return_value };'
      when :Value
        'return return_value;'
      when :NullableValue
        'if (return_value) { return return_value; } else { return NAT_NIL; }'
      when :StringValue
        'return return_value;'
      else
        raise "Unknown return type: #{return_type.inspect}"
      end
    end

    def max_argc
      if Range === argc
        argc.end
      else
        argc
      end
    end

    def generate_name
      @name = "#{cpp_class}_#{cpp_method}#{@singleton ? '_singleton' : ''}_binding"
    end
  end
end

puts '// DO NOT EDIT THIS FILE BY HAND!'
puts '// This file is generated by the lib/natalie/compiler/binding_gen.rb script.'
puts '// Run `make src/bindings.cpp` to regenerate this file.'
puts
puts '#include "natalie.hpp"'
puts
puts 'namespace Natalie {'
puts

gen = BindingGen.new

gen.singleton_binding('Array', '[]', 'ArrayValue', 'square_new', argc: :any, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', '+', 'ArrayValue', 'add', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', '-', 'ArrayValue', 'sub', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', '<<', 'ArrayValue', 'ltlt', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', '<=>', 'ArrayValue', 'cmp', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', '==', 'ArrayValue', 'eq', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', '===', 'ArrayValue', 'eq', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', '[]', 'ArrayValue', 'ref', argc: 1..2, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', '[]=', 'ArrayValue', 'refeq', argc: 2..3, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', 'any?', 'ArrayValue', 'any', argc: 0, pass_env: true, pass_block: true, return_type: :Value)
gen.binding('Array', 'each', 'ArrayValue', 'each', argc: 0, pass_env: true, pass_block: true, return_type: :Value)
gen.binding('Array', 'each_with_index', 'ArrayValue', 'each_with_index', argc: 0, pass_env: true, pass_block: true, return_type: :Value)
gen.binding('Array', 'first', 'ArrayValue', 'first', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', 'include?', 'ArrayValue', 'include', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', 'initialize', 'ArrayValue', 'initialize', argc: 0..2, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', 'inspect', 'ArrayValue', 'inspect', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', 'join', 'ArrayValue', 'join', argc: 0..1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', 'last', 'ArrayValue', 'last', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', 'length', 'ArrayValue', 'size', argc: 0, pass_env: false, pass_block: false, return_type: :ssize_t)
gen.binding('Array', 'map', 'ArrayValue', 'map', argc: 0, pass_env: true, pass_block: true, return_type: :Value)
gen.binding('Array', 'pop', 'ArrayValue', 'pop', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', 'size', 'ArrayValue', 'size', argc: 0, pass_env: false, pass_block: false, return_type: :ssize_t)
gen.binding('Array', 'sort', 'ArrayValue', 'sort', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Array', 'to_a', 'ArrayValue', 'to_ary', argc: 0, pass_env: false, pass_block: false, return_type: :Value)
gen.binding('Array', 'to_ary', 'ArrayValue', 'to_ary', argc: 0, pass_env: false, pass_block: false, return_type: :Value)
gen.binding('Array', 'to_s', 'ArrayValue', 'inspect', argc: 0, pass_env: true, pass_block: false, return_type: :Value)

gen.singleton_binding('Class', 'new', 'ClassValue', 'new_method', argc: 0..1, pass_env: true, pass_block: true, return_type: :Value)
gen.binding('Class', 'superclass', 'ClassValue', 'superclass', argc: 0, pass_env: false, pass_block: false, return_type: :NullableValue)

gen.singleton_binding('Encoding', 'list', 'EncodingValue', 'list', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Encoding', 'inspect', 'EncodingValue', 'inspect', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Encoding', 'name', 'EncodingValue', 'name', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Encoding', 'names', 'EncodingValue', 'names', argc: 0, pass_env: true, pass_block: false, return_type: :Value)

gen.binding('Exception', 'backtrace', 'ExceptionValue', 'backtrace', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Exception', 'initialize', 'ExceptionValue', 'initialize', argc: 0..1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Exception', 'inspect', 'ExceptionValue', 'inspect', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Exception', 'message', 'ExceptionValue', 'message', argc: 0, pass_env: true, pass_block: false, return_type: :Value)

gen.undefine_singleton_method('FalseClass', 'new')
gen.binding('FalseClass', 'inspect', 'FalseValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('FalseClass', 'to_s', 'FalseValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)

gen.binding('Float', '%', 'FloatValue', 'mod', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', '*', 'FloatValue', 'mul', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', '**', 'FloatValue', 'pow', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', '+', 'FloatValue', 'add', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', '+@', 'FloatValue', 'uplus', argc: 0, pass_env: false, pass_block: false, return_type: :Value)
gen.binding('Float', '-', 'FloatValue', 'sub', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', '-@', 'FloatValue', 'uminus', argc: 0, pass_env: false, pass_block: false, return_type: :Value)
gen.binding('Float', '/', 'FloatValue', 'div', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', '<', 'FloatValue', 'lt', argc: 1, pass_env: true, pass_block: false, return_type: :bool)
gen.binding('Float', '<=', 'FloatValue', 'lte', argc: 1, pass_env: true, pass_block: false, return_type: :bool)
gen.binding('Float', '<=>', 'FloatValue', 'cmp', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', '==', 'FloatValue', 'eq', argc: 1, pass_env: true, pass_block: false, return_type: :bool)
gen.binding('Float', '===', 'FloatValue', 'eq', argc: 1, pass_env: true, pass_block: false, return_type: :bool)
gen.binding('Float', '>', 'FloatValue', 'gt', argc: 1, pass_env: true, pass_block: false, return_type: :bool)
gen.binding('Float', '>=', 'FloatValue', 'gte', argc: 1, pass_env: true, pass_block: false, return_type: :bool)
gen.binding('Float', 'abs', 'FloatValue', 'abs', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'ceil', 'FloatValue', 'ceil', argc: 0..1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'coerce', 'FloatValue', 'coerce', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'divmod', 'FloatValue', 'divmod', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'eql?', 'FloatValue', 'eql', argc: 1, pass_env: false, pass_block: false, return_type: :bool)
gen.binding('Float', 'fdiv', 'FloatValue', 'div', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'finite?', 'FloatValue', 'is_finite', argc: 0, pass_env: false, pass_block: false, return_type: :bool)
gen.binding('Float', 'floor', 'FloatValue', 'floor', argc: 0..1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'infinite?', 'FloatValue', 'is_infinite', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'inspect', 'FloatValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'nan?', 'FloatValue', 'is_nan', argc: 0, pass_env: false, pass_block: false, return_type: :bool)
gen.binding('Float', 'quo', 'FloatValue', 'div', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'to_i', 'FloatValue', 'to_i', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'to_s', 'FloatValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Float', 'zero?', 'FloatValue', 'is_zero', argc: 0, pass_env: false, pass_block: false, return_type: :bool)

gen.singleton_binding('Hash', '[]', 'HashValue', 'square_new', argc: :any, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', '==', 'HashValue', 'eq', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', '===', 'HashValue', 'eq', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', '[]', 'HashValue', 'ref', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', '[]=', 'HashValue', 'refeq', argc: 2, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', 'delete', 'HashValue', 'delete_key', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', 'each', 'HashValue', 'each', argc: 0, pass_env: true, pass_block: true, return_type: :Value)
gen.binding('Hash', 'initialize', 'HashValue', 'initialize', argc: 0..1, pass_env: true, pass_block: true, return_type: :Value)
gen.binding('Hash', 'inspect', 'HashValue', 'inspect', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', 'key?', 'HashValue', 'has_key', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', 'keys', 'HashValue', 'keys', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', 'size', 'HashValue', 'size', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', 'sort', 'HashValue', 'sort', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', 'to_s', 'HashValue', 'inspect', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Hash', 'values', 'HashValue', 'values', argc: 0, pass_env: true, pass_block: false, return_type: :Value)

gen.binding('Integer', '%', 'IntegerValue', 'mod', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', '&', 'IntegerValue', 'bitwise_and', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', '*', 'IntegerValue', 'mul', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', '**', 'IntegerValue', 'pow', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', '+', 'IntegerValue', 'add', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', '-', 'IntegerValue', 'sub', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', '/', 'IntegerValue', 'div', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', '<=>', 'IntegerValue', 'cmp', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', '===', 'IntegerValue', 'eqeqeq', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', 'abs', 'IntegerValue', 'abs', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', 'chr', 'IntegerValue', 'chr', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', 'coerce', 'IntegerValue', 'coerce', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', 'eql?', 'IntegerValue', 'eql', argc: 1, pass_env: true, pass_block: false, return_type: :bool)
gen.binding('Integer', 'inspect', 'IntegerValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', 'succ', 'IntegerValue', 'succ', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', 'times', 'IntegerValue', 'times', argc: 0, pass_env: true, pass_block: true, return_type: :Value)
gen.binding('Integer', 'to_i', 'IntegerValue', 'to_i', argc: 0, pass_env: false, pass_block: false, return_type: :Value)
gen.binding('Integer', 'to_s', 'IntegerValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Integer', '|', 'IntegerValue', 'bitwise_or', argc: 1, pass_env: true, pass_block: false, return_type: :Value)

gen.binding('IO', 'close', 'IoValue', 'close', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('IO', 'fileno', 'IoValue', 'fileno', argc: 0, pass_env: false, pass_block: false, return_type: :int)
gen.binding('IO', 'initialize', 'IoValue', 'initialize', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('IO', 'print', 'IoValue', 'print', argc: :any, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('IO', 'puts', 'IoValue', 'puts', argc: :any, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('IO', 'read', 'IoValue', 'read', argc: 0..1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('IO', 'seek', 'IoValue', 'seek', argc: 1..2, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('IO', 'write', 'IoValue', 'write', argc: 1.., pass_env: true, pass_block: false, return_type: :Value)

gen.binding('MatchData', 'size', 'MatchDataValue', 'size', argc: 0, pass_env: false, pass_block: false, return_type: :ssize_t)
gen.binding('MatchData', 'length', 'MatchDataValue', 'size', argc: 0, pass_env: false, pass_block: false, return_type: :ssize_t)
gen.binding('MatchData', 'to_s', 'MatchDataValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('MatchData', '[]', 'MatchDataValue', 'ref', argc: 1, pass_env: true, pass_block: false, return_type: :Value)

gen.undefine_singleton_method('NilClass', 'new')
gen.binding('NilClass', 'inspect', 'NilValue', 'inspect', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('NilClass', 'to_a', 'NilValue', 'to_a', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('NilClass', 'to_i', 'NilValue', 'to_i', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('NilClass', 'to_s', 'NilValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)

gen.binding('Object', 'nil?', 'Value', 'is_nil', argc: 0, pass_env: false, pass_block: false, return_type: :bool)

gen.binding('Proc', 'initialize', 'ProcValue', 'initialize', argc: 0, pass_env: true, pass_block: true, return_type: :Value)
gen.binding('Proc', 'call', 'ProcValue', 'call', argc: :any, pass_env: true, pass_block: true, return_type: :Value)
gen.binding('Proc', 'lambda?', 'ProcValue', 'is_lambda', argc: 0, pass_env: false, pass_block: false, return_type: :bool)

gen.binding('Regexp', '==', 'RegexpValue', 'eq', argc: 1, pass_env: true, pass_block: false, return_type: :bool)
gen.binding('Regexp', '===', 'RegexpValue', 'match', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Regexp', '=~', 'RegexpValue', 'eqtilde', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Regexp', 'initialize', 'RegexpValue', 'initialize', argc: 0..1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Regexp', 'inspect', 'RegexpValue', 'inspect', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Regexp', 'match', 'RegexpValue', 'match', argc: 1, pass_env: true, pass_block: false, return_type: :Value)

gen.binding('String', '*', 'StringValue', 'mul', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', '+', 'StringValue', 'add', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', '<<', 'StringValue', 'ltlt', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', '<=>', 'StringValue', 'cmp', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', '==', 'StringValue', 'eq', argc: 1, pass_env: false, pass_block: false, return_type: :bool)
gen.binding('String', '===', 'StringValue', 'eq', argc: 1, pass_env: false, pass_block: false, return_type: :bool)
gen.binding('String', '=~', 'StringValue', 'eqtilde', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', '[]', 'StringValue', 'ref', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'bytes', 'StringValue', 'bytes', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'chars', 'StringValue', 'chars', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'encode', 'StringValue', 'encode', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'encoding', 'StringValue', 'encoding', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'force_encoding', 'StringValue', 'force_encoding', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'index', 'StringValue', 'index', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'initialize', 'StringValue', 'initialize', argc: 0..1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'inspect', 'StringValue', 'inspect', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'length', 'StringValue', 'length', argc: 0, pass_env: false, pass_block: false, return_type: :ssize_t)
gen.binding('String', 'ljust', 'StringValue', 'ljust', argc: 1..2, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'match', 'StringValue', 'match', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'ord', 'StringValue', 'ord', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'size', 'StringValue', 'size', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'split', 'StringValue', 'split', argc: 0..1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'sub', 'StringValue', 'sub', argc: 2, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'succ', 'StringValue', 'successive', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'to_i', 'StringValue', 'to_i', argc: 0..1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('String', 'to_s', 'StringValue', 'to_s', argc: 0, pass_env: false, pass_block: false, return_type: :Value)
gen.binding('String', 'to_str', 'StringValue', 'to_str', argc: 0, pass_env: false, pass_block: false, return_type: :Value)

gen.binding('Symbol', '<=>', 'SymbolValue', 'cmp', argc: 1, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Symbol', 'inspect', 'SymbolValue', 'inspect', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Symbol', 'to_proc', 'SymbolValue', 'to_proc', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('Symbol', 'to_s', 'SymbolValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)

gen.undefine_singleton_method('TrueClass', 'new')
gen.binding('TrueClass', 'inspect', 'TrueValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)
gen.binding('TrueClass', 'to_s', 'TrueValue', 'to_s', argc: 0, pass_env: true, pass_block: false, return_type: :Value)

gen.init

puts
puts '}'
