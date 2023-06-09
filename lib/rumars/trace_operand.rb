#
# Copyright (c) Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# frozen_string_literal: true

require_relative 'operand'
require_relative 'format'

module RuMARS
  class TraceOperand
    attr_reader :pointer, :instruction, :post_incr_instr, :loads, :stores

    include Format

    def initialize
      @pointer = nil
      @instruction = nil
      @post_incr_instr = nil
      @loads = []
      @stores = []
    end

    def log(operand)
      @pointer = operand.pointer
      @instruction = operand.instruction&.to_s
      @post_incr_instr = operand.post_incr_instr&.to_s
    end

    def log_load(address, instruction)
      @loads << [address, instruction]
    end

    def log_store(address, instruction)
      @stores << [address, instruction]
    end

    def to_s
      "PTR:   #{aformat(@pointer)}\n" \
        "LOAD1: #{aiformat(@loads[0])}\n" \
        "LOAD2: #{aiformat(@loads[1])}\n" \
        "STORE: #{aiformat(@stores[0])}\n" \
        "INS:         #{iformat(@instruction)}\n" \
    end

    def self.csv_header(prefix)
      "#{prefix}-Pointer;#{prefix}-Load1;#{prefix}-Load2;#{prefix}-Store"
    end

    def to_csv
      "#{@pointer};#{aiformat(@loads[0])};#{aiformat(@loads[1])};" \
        "#{aiformat(stores[0])}"
    end
  end
end
