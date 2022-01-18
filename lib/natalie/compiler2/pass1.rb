require_relative './base_pass'

module Natalie
  class Compiler2
    class Pass1 < BasePass
      def initialize(ast)
        @ast = ast
      end

      # pass used: true to leave the final result on the stack
      def transform(used: true)
        raise 'unexpected AST input' unless @ast.sexp_type == :block
        transform_block(@ast, used: used).flatten
      end

      private

      def transform_array_of_expressions(array_of_expressions, used:)
        instructions = []
        array_of_expressions[0...-1].each { |exp| instructions << transform_expression(exp, used: false) }
        instructions << transform_expression(array_of_expressions.last, used: used) if array_of_expressions.last
        instructions.flatten
      end

      def transform_expression(exp, used:)
        case exp
        when Sexp
          method = "transform_#{exp.sexp_type}"
          send(method, exp, used: used)
        else
          raise "Unknown expression type: #{exp.inspect}"
        end
      end

      # INDIVIDUAL EXPRESSIONS = = = = =
      # (in alphabetical order)

      def transform_array(exp, used:)
        _, *items = exp
        instructions = items.map { |item| transform_expression(item, used: true) }
        instructions << CreateArrayInstruction.new(count: items.size)
      end

      def transform_block(exp, used:)
        _, *body = exp
        transform_array_of_expressions(body, used: used)
      end

      def transform_call(exp, used:, with_block: false)
        _, receiver, message, *args = exp
        instructions = args.map { |arg| transform_expression(arg, used: true) }
        instructions << PushArgcInstruction.new(args.size)
        if receiver.nil?
          instructions << PushSelfInstruction.new
        else
          instructions << transform_expression(receiver, used: true)
        end
        instructions << SendInstruction.new(message, with_block: with_block)
        instructions << PopInstruction.new unless used
        instructions
      end

      def transform_class(exp, used:)
        _, name, superclass, *body = exp
        instructions = []
        if superclass
          instructions << transform_expression(superclass, used: true)
        else
          instructions << ConstFindInstruction.new('Object')
        end
        instructions << DefineClassInstruction.new(name: name)
        instructions += transform_array_of_expressions(body, used: false)
        instructions << EndInstruction.new(:define_class)
        instructions << PushNilInstruction.new if used
        instructions
      end

      def transform_const(exp, used:)
        return [] unless used
        _, name = exp
        ConstFindInstruction.new(name)
      end

      def transform_defn(exp, used:)
        _, name, args, *body = exp
        arity = args.size - 1 # FIXME: way more complicated than this :-)
        instructions = []
        instructions << DefineMethodInstruction.new(name: name, arity: arity)
        instructions << transform_defn_args(args, used: true)
        instructions += transform_array_of_expressions(body, used: true)
        instructions << EndInstruction.new(:define_method)
        instructions << PopInstruction.new unless used
        instructions
      end

      def transform_defn_args(exp, used:)
        return [] unless used
        _, *args = exp
        if complicated_args?(args)
          [PushArgsInstruction.new, transform_complicated_defn_args(exp, used: used)]
        else
          args.each_with_index.flat_map do |name, index|
            [PushArgInstruction.new(index), VariableSetInstruction.new(name)]
          end
        end
      end

      # TODO: might need separate logic?
      alias transform_block_args transform_defn_args

      def complicated_args?(args)
        args.any? { |a| a.is_a?(Sexp) || a.start_with?('*') }
      end

      def transform_complicated_defn_args(exp, used:)
        return [] unless used
        _, *args = exp
        instructions = []
        splat_on_stack = false
        args.each do |name|
          if name.is_a?(Sexp)
            if name.sexp_type == :masgn
              instructions << ArrayShiftInstruction.new
              instructions << transform_complicated_defn_args(name, used: true)
            else
              raise "I don't yet know how to compile #{name.inspect}"
            end
          elsif name.start_with?('*')
            instructions << VariableSetInstruction.new(name[1..-1])
            instructions << VariableGetInstruction.new(name[1..-1]) # TODO: could eliminate this if the *splat is the last arg
            splat_on_stack = true
          else
            instructions << (splat_on_stack ? ArrayPopInstruction.new : ArrayShiftInstruction.new)
            instructions << VariableSetInstruction.new(name)
          end
        end
        instructions << PopInstruction.new
      end

      def transform_if(exp, used:)
        _, condition, true_expression, false_expression = exp
        true_instructions =
          if true_expression
            transform_expression(true_expression, used: true)
          else
            PushNilInstruction.new
          end
        false_instructions =
          if false_expression
            transform_expression(false_expression, used: true)
          else
            PushNilInstruction.new
          end
        instructions = [
          transform_expression(condition, used: true),
          IfInstruction.new,
          Array(true_instructions),
          ElseInstruction.new,
          Array(false_instructions),
          EndInstruction.new(:if),
        ]
        instructions << PopInstruction.new unless used
        instructions
      end

      def transform_iter(exp, used:)
        _, call, args, body = exp
        arity = args.size - 1 # FIXME: way more complicated than this :-)
        instructions = []
        instructions << DefineBlockInstruction.new(arity: arity)
        instructions << transform_defn_args(args, used: true)
        instructions << transform_expression(body, used: true)
        instructions << EndInstruction.new(:define_block)
        raise 'unexpected call' unless call.sexp_type == :call
        instructions << transform_call(call, used: used, with_block: true)
        instructions
      end

      def transform_lasgn(exp, used:)
        _, name, value = exp
        instructions = [transform_expression(value, used: true), VariableSetInstruction.new(name)]
        instructions << VariableGetInstruction.new(name) if used
        instructions
      end

      def transform_lit(exp, used:)
        return [] unless used
        _, lit = exp
        case lit
        when Integer
          PushIntInstruction.new(lit)
        when Float
          PushFloatInstruction.new(lit)
        when Symbol
          PushSymbolInstruction.new(lit)
        else
          raise "I don't yet know how to handle lit: #{lit.inspect}"
        end
      end

      def transform_lvar(exp, used:)
        return [] unless used
        _, name = exp
        VariableGetInstruction.new(name)
      end

      def transform_nil(_, used:)
        return [] unless used
        PushNilInstruction.new
      end

      def transform_self(_, used:)
        return [] unless used
        PushSelfInstruction.new
      end

      def transform_str(exp, used:)
        return [] unless used
        _, str = exp
        PushStringInstruction.new(str, str.size)
      end
    end
  end
end
