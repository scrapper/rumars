#
# Copyright (c) Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# frozen_string_literal: true

module RuMARS
  class Expression
    class ExpressionError < RuntimeError
      attr_reader :expression, :line_no

      def initialize(expression, message, line_no)
        super(message)

        @expression = expression
        @line_no = line_no
      end
    end

    attr_reader :operator, :line_no
    attr_accessor :operand1, :parenthesis

    PRECEDENCE = {
      '*' => 4,
      '/' => 4,
      '%' => 4,
      '+' => 3,
      '-' => 3,
      '!' => 3,
      '==' => 2,
      '!=' => 2,
      '<' => 2,
      '>' => 2,
      '>=' => 2,
      '<=' => 2,
      '&&' => 1,
      '||' => 0
    }.freeze

    def initialize(operand1, operator, operand2, line_no = -1)
      raise ArgumentError, 'Operand 1 of an expression must not be nil' unless operand1
      raise ArgumentError, 'Binary expression must have an operator' if operand2 && operator.nil?

      @operand1 = operand1
      @operator = operator
      @operand2 = operand2
      @line_no = line_no

      @parenthesis = false
    end

    def eval(symbol_table, instruction_address = 0)
      eval_recursive(symbol_table, instruction_address)
    rescue ExpressionError => e
      raise ExpressionError.new(self, "#{self}: #{e.message}", @line_no)
    end

    def eval_recursive(symbol_table, instruction_address)
      @operand2 ? eval_binary(symbol_table, instruction_address) : eval_unary(symbol_table, instruction_address)
    end

    # Find the leftmost operation of this expression that has a lower or equal
    # precedence than the provided operator.
    def find_lhs_node(operator)
      return nil unless lower_or_equal_precedence?(operator)

      expr = self
      expr = expr.operand1 while expr.operand1.is_a?(Expression) && expr.operand1.lower_or_equal_precedence?(operator)

      expr
    end

    # @return true if the passed operator has a lower or equal precedence than
    #         the operator of the Expression
    def lower_or_equal_precedence?(other_operator)
      return false if @operator.nil? || @parenthesis

      PRECEDENCE[@operator] <= PRECEDENCE[other_operator]
    end

    def to_s
      if @operand2
        "(#{@operand1} #{@operator} #{@operand2})"
      elsif @operator
        "#{@operator}#{@operand1}"
      else
        @operand1.to_s
      end
    end

    private

    def eval_unary(symbol_table, instruction_address)
      result = eval_operand(@operand1, symbol_table, instruction_address)

      case @operator
      when '-'
        -result
      when '!'
        result.zero? ? 1 : 0
      else
        result
      end
    end

    def eval_binary(symbol_table, instruction_address)
      op1 = eval_operand(@operand1, symbol_table, instruction_address)
      op2 = eval_operand(@operand2, symbol_table, instruction_address)

      case @operator
      when '+'
        op1 + op2
      when '-'
        op1 - op2
      when '*'
        op1 * op2
      when '/'
        raise ExpressionError.new(self, 'Division by zero', @line_no) if op2.zero?

        op1 / op2
      when '%'
        raise ExpressionError.new(self, 'Modulo by zero', @line_no) if op2.zero?

        op1 % op2
      when '=='
        eval_boolean(op1 == op2)
      when '!='
        eval_boolean(op1 != op2)
      when '<'
        eval_boolean(op1 < op2)
      when '>'
        eval_boolean(op1 > op2)
      when '<='
        eval_boolean(op1 <= op2)
      when '>='
        eval_boolean(op1 >= op2)
      when '&&'
        eval_boolean(op1 && op2)
      when '||'
        eval_boolean(op1 || op2)
      else
        raise ArgumentError, "Unknown operator #{@operator}"
      end
    end

    def eval_operand(operand, symbol_table, instruction_address)
      case operand
      when Integer
        operand
      when String
        raise ExpressionError.new(self, "Unknown symbol #{operand}", @line_no) unless symbol_table.include?(operand)

        symbol_table[operand].to_i - instruction_address
      when Expression
        operand.eval_recursive(symbol_table, instruction_address)
      else
        raise "Unknown operand class #{operand.class}"
      end
    end

    def eval_boolean(value)
      value ? 1 : 0
    end
  end
end
