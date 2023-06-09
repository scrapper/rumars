#
# Copyright (c) Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# frozen_string_literal: true

require_relative 'trace_operand'
require_relative 'format'

module RuMARS
  class TraceInstruction
    attr_reader :a_operand, :b_operand

    include Format

    def initialize(address, instruction, pid)
      @address = address
      @instruction = instruction
      @cycle_counter = 0
      @a_operand = nil
      @b_operand = nil
      @operation = ''
      @stores = []
      @pcs = nil
      @pid = pid
    end

    def cycle(cycle_counter)
      @cycle_counter = cycle_counter
    end

    def new_a_operand
      @a_operand = TraceOperand.new
    end

    def new_b_operand
      @b_operand = TraceOperand.new
    end

    def operation(text)
      @operation += '; ' unless @operation.empty?
      @operation += text
    end

    def program_counters(pcs)
      @pcs = pcs.clone
    end

    def log_store(address, instruction)
      @stores << [address, instruction]
    end

    def to_s
      s = "IREG:    #{aformat(@address)}: #{iformat(@instruction)}  " \
          "CYCLE: #{format('%4d', @cycle_counter)}  " \
          "PID: #{@pid}\n" \
          "A-OPERAND             A.a, A.b        B-OPERAND          B.a, B.b\n"
      a = a_operand.to_s.split("\n")
      b = b_operand.to_s.split("\n")
      a.length.times do |i|
        s += format("  %-34s  %-34s\n", a[i], b[i])
      end
      s += "OPERATION #{@operation}\n" \
           "STORES:  #{aiformat(@stores[0])}           #{aiformat(@stores[1])}\n" \
           "PCS: (#{@pcs&.length || 0}) [#{pcs_to_s}]"

      s
    end

    def self.csv_header
      'Cycle;PID;Address;Instruction;' \
        "#{TraceOperand.csv_header('A')};" \
        "#{TraceOperand.csv_header('B')};" \
        "Store1;Store2;PCS\n"
    end

    def to_csv
      "#{@cycle_counter};#{@pid};#{@address};#{@instruction};" \
        "#{a_operand.to_csv};#{b_operand.to_csv};" \
        "#{aiformat(@stores[0])};#{aiformat(@stores[1])};" \
        "#{@pcs&.join(',')}"
    end

    def pcs_to_s
      return '' unless @pcs

      return @pcs.join(' ') if @pcs.length < 8

      "#{@pcs[0..3].join(' ')}...#{@pcs[-3..].join(' ')}"
    end
  end
end
