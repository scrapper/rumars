# frozen_string_literal: true

require_relative 'trace_operand'
require_relative 'format'

module RuMARS
  class TraceInstruction
    attr_reader :a_operand, :b_operand

    include Format

    def initialize(address, instruction)
      @address = address
      @instruction = instruction
      @a_operand = nil
      @b_operand = nil
      @operation = ''
      @stores = []
      @pcs = nil
    end

    def new_a_operand
      @a_operand = TraceOperand.new
    end

    def new_b_operand
      @b_operand = TraceOperand.new
    end

    def operation(text)
      @operation = text
    end

    def program_counters(pcs)
      @pcs = pcs
    end

    def log_store(address, instruction)
      @stores << [address, instruction]
    end

    def to_s
      "IREG:    #{aformat(@address)}: #{@instruction}\n" \
        "A-OPERAND #{@a_operand}\n" \
        "B-OPERAND #{@b_operand}\n" \
        "OPERATION #{@operation}\n" \
        "STORES:  #{aiformat(@stores[0])}           #{aiformat(@stores[1])}\n" \
        "PCS: (#{@pcs&.length || 0}) [#{pcs_to_s}]"
    end

    def pcs_to_s
      return '' unless @pcs

      return "#{@pcs.join(' ')}" if @pcs.length < 8

      "#{@pcs[0..3].join(' ')}...#{@pcs[-3..].join(' ')}"
    end
  end
end