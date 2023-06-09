#
# Copyright (c) Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# frozen_string_literal: true

require_relative 'trace_instruction'

module RuMARS
  class Tracer
    def initialize(max_traces = 100)
      @traces = []
      @traces_by_pid = {}
      @current_instruction = nil
      @current_operand = nil
      @max_traces = max_traces
    end

    def next_instruction(address, instruction, pid)
      @traces.shift if @max_traces.positive? && @traces.length >= @max_traces
      @traces << (@current_instruction = TraceInstruction.new(address, instruction, pid))
      @traces_by_pid[pid] ||= []
      @traces_by_pid[pid].shift if @max_traces.positive? && @traces_by_pid[pid].length >= @max_traces
      @traces_by_pid[pid].append(@current_instruction)
    end

    def processing_instruction
      @current_operand = nil
    end

    def cycle(cycle_counter)
      @current_instruction.cycle(cycle_counter)
    end

    def processing_a_operand
      @current_operand = @current_instruction.a_operand || @current_instruction.new_a_operand
    end

    def processing_b_operand
      @current_operand = @current_instruction.b_operand || @current_instruction.new_b_operand
    end

    def operation(text)
      @current_instruction.operation(text)
    end

    def program_counters(pcs)
      @current_instruction.program_counters(pcs)
    end

    def log_operand(operand)
      @current_operand.log(operand)
    end

    def log_load(address, instruction)
      @current_operand.log_load(address, instruction)
    end

    def log_store(address, instruction)
      (@current_operand || @current_instruction).log_store(address, instruction)
    end

    def trace_count(pid = nil)
      @traces_by_pid[pid] ||= [] if pid
      pid ? @traces_by_pid[pid].length : @traces.length
    end

    def instruction(index = -1, pid = nil)
      @traces_by_pid[pid] ||= [] if pid
      pid ? @traces_by_pid[pid][index] : @traces[index]
    end

    def to_s
      @traces.each(&:to_s).join("\n#{'-' * 70}\n")
    end

    def save(file_name)
      begin
        File.write(file_name, TraceInstruction.csv_header + @traces.map(&:to_csv).join("\n"))
      rescue IOError => e
        puts "Error writing file '#{file_name}': #{e.message}"
        return false
      end

      true
    end
  end
end
