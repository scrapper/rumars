#
# Copyright (c) Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# frozen_string_literal: true

require_relative 'format'
require_relative 'operand'
require_relative 'memory_core'

module RuMARS
  OPCODES = %w[DAT MOV ADD SUB MUL DIV MOD JMP JMZ JMN DJN CMP SLT SPL].freeze
  MODIFIERS = %w[A B AB BA F X I].freeze

  # A REDCODE instruction that is stored in the core memory.
  # https://corewar-docs.readthedocs.io/en/latest/redcode/
  class Instruction
    class DivBy0Error < RuntimeError
    end

    class InstructionBus
      attr_reader :memory_core, :base_address, :program_counter, :modifier, :pid
      attr_accessor :a_operand, :b_operand

      def initialize(memory_core, base_address, program_counter, modifier, pid)
        @memory_core = memory_core
        @base_address = base_address
        @program_counter = program_counter
        @modifier = modifier
        @pid = pid

        @a_operand = nil
        @b_operand = nil
      end
    end

    include Format

    attr_accessor :pid, :opcode, :modifier, :a_operand, :b_operand, :address

    @tracer = nil

    # Accessor for @tracer
    class << self
      attr_accessor :tracer
    end

    # @param pid [Integer] PID of the Warrior this instruction belongs to. 0 means no owner.
    # @param opcode [String] Determines the type of instruction
    # @param modifier [String] Determines how the operands are used
    # @param a_operand [Operand] 'A' value of the instruction
    # @param b_operand [Operand] 'B' value of the instruction
    def initialize(pid, opcode, modifier, a_operand, b_operand, address = nil)
      raise ArgumentError unless OPCODES.include?(opcode) || MODIFIERS.include?(modifier)

      # ID of the Warrior that either loaded or modified this instruction.
      @pid = pid
      # Address in the memory that the instruction is loaded to.
      @address = address
      @opcode = opcode
      @modifier = modifier
      @a_operand = a_operand
      @b_operand = b_operand
    end

    def a_number
      @a_operand&.number
    end

    def set_a_number(number, bus)
      return 0 unless bus.memory_core.check_limit(:write_limit, bus.program_counter, @address)

      @pid = bus.pid
      @a_operand.number = number
      self.class.tracer&.log_store(@address, to_s)

      number
    end

    def increment_a_number(bus)
      n = @a_operand.number = MemoryCore.fold(a_number + 1)
      set_a_number(n, bus)
    end

    def decrement_a_number(bus)
      n = @a_operand.number = MemoryCore.fold(a_number - 1)
      set_a_number(n, bus)
    end

    def b_number
      @b_operand&.number
    end

    def set_b_number(number, bus)
      return 0 unless bus.memory_core.check_limit(:write_limit, bus.program_counter, @address)

      @pid = bus.pid
      @b_operand.number = number
      self.class.tracer&.log_store(@address, to_s)

      number
    end

    def increment_b_number(bus)
      n = @b_operand.number = MemoryCore.fold(b_number + 1)
      set_b_number(n, bus)
    end

    def decrement_b_number(bus)
      n = @b_operand.number = MemoryCore.fold(b_number - 1)
      set_b_number(n, bus)
    end

    def evaluate_expressions(symbol_table, instruction_address)
      @a_operand.evaluate_expressions(symbol_table, instruction_address)
      @b_operand.evaluate_expressions(symbol_table, instruction_address)
    end

    def execute(memory_core, program_counter, pid, base_address)
      bus = InstructionBus.new(memory_core, base_address, program_counter, @modifier, pid)

      # Prepare the A-Operand
      self.class.tracer&.processing_a_operand
      bus.a_operand = @a_operand.evaluate(bus)
      bus.a_operand.instruction = bus.a_operand.instruction.deep_copy
      @a_operand.post_increment(bus, bus.a_operand)
      self.class.tracer&.log_operand(bus.a_operand)

      # Prepare the B-Operand
      self.class.tracer&.processing_b_operand
      bus.b_operand = @b_operand.evaluate(bus)
      @b_operand.post_increment(bus, bus.b_operand)
      self.class.tracer&.log_operand(bus.b_operand)

      self.class.tracer&.processing_instruction
      next_pc = [program_counter + 1]

      case @opcode
      when 'ADD'
        arith('+', bus)
      when 'DAT'
        self.class.tracer&.operation('Terminating current thread')
        next_pc = nil
      when 'DIV'
        begin
          arith('/', bus)
        rescue DivBy0Error
          next_pc = nil
        end
      when 'DJN'
        next_pc = djn(bus)
      when 'JMN'
        next_pc = jmn(bus)
      when 'JMP'
        next_pc = jmp(bus)
      when 'JMZ'
        next_pc = jmz(bus)
      when 'MOD'
        begin
          arith('%', bus)
        rescue DivBy0Error
          next_pc = nil
        end
      when 'MOV'
        mov(bus)
      when 'MUL'
        arith('*', bus)
      when 'NOP'
        # Do nothing
      when 'SEQ', 'CMP'
        next_pc = seq(bus)
      when 'SNE'
        next_pc = sne(bus)
      when 'SLT'
        next_pc = slt(bus)
      when 'SPL'
        next_pc = spl(bus)
      when 'SUB'
        arith('-', bus)
      else
        raise "Unknown opcode #{@opcode} at address #{program_counter}"
      end

      next_pc&.delete_if do |pc|
        if memory_core.check_limit(:read_limit, 0, pc)
          false
        else
          self.class.tracer&.operation('Jump beyond read limit')
          true
        end
      end
      next_pc = nil if next_pc&.empty?

      next_pc
    end

    # Create an identical deep copy.
    def deep_copy
      Instruction.new(@pid, @opcode.clone, @modifier.clone, @a_operand.deep_copy, @b_operand&.deep_copy, @address)
    end

    def to_s
      "#{@opcode}.#{@modifier} #{@a_operand}, #{@b_operand}"
    end

    def ==(other)
      @opcode == other.opcode && @modifier == other.modifier &&
        @a_operand == other.a_operand && @b_operand == other.b_operand
    end

    private

    def arith(op, bus)
      ira = bus.a_operand.instruction
      irb = bus.b_operand.instruction

      unless bus.memory_core.check_limit(:write_limit, bus.program_counter, irb.address)
        self.class.tracer&.operation('Write limit exceeded')
        return
      end

      case @modifier
      when 'A'
        irb.set_a_number(arith_op('B.a', irb.a_number, op, 'A.a', ira.a_number), bus)
      when 'B'
        irb.set_b_number(arith_op('B.b', irb.b_number, op, 'A.b', ira.b_number), bus)
      when 'AB'
        irb.set_b_number(arith_op('B.b', irb.b_number, op, 'A.a', ira.a_number), bus)
      when 'BA'
        irb.set_a_number(arith_op('B.a', irb.a_number, op, 'A.b', ira.b_number), bus)
      when 'F', 'I'
        begin
          irb.set_a_number(arith_op('B.a', irb.a_number, op, 'A.a', ira.a_number), bus)
        rescue DivBy0Error => e
        end
        # The b operation must be computed even if the a operation had a division by 0
        irb.set_b_number(arith_op('B.b', irb.b_number, op, 'A.b', ira.b_number), bus)
        raise e if e
      when 'X'
        begin
          irb.set_a_number(arith_op('B.a', irb.a_number, op, 'A.b', ira.b_number), bus)
        rescue DivBy0Error => e
        end
        # The b operation must be computed even if the a operation had a division by 0
        irb.set_b_number(arith_op('B.b', irb.b_number, op, 'A.a', ira.a_number), bus)
        raise e if e
      else
        raise ArgumentError, "Unknown instruction modifier #{@modifier}"
      end
    end

    def arith_op(tag1, op1, operator, tag2, op2)
      case operator
      when '+'
        # The add instruction adds the number(s) from the address referenced by
        # the A operand to the number(s) at the address referenced by the B
        # operand.
        result = MemoryCore.fold(op1 + op2)
      when '-'
        # The sub instruction subtracts the number(s) from the address
        # referenced by the A operand from the number(s) at the address
        # referenced by the B operand.
        result = MemoryCore.fold(op1 - op2)
      when '*'
        # The mul instruction multiplies the number(s) from the address
        # referenced by the A operand by the number(s) at the address
        # referenced by the B operand.
        result = MemoryCore.fold(op1 * op2)
      when '/'
        # The div instruction divides the number(s) from the address referenced
        # by the B operand by the number(s) at the address referenced by the A
        # operand. The quotient of this division is always rounded down.
        # Dividing by zero is considered an illegal instruction in Corewar. The
        # executing warrior's process is removed from the process queue
        # (terminated).
        raise DivBy0Error if op2.zero?

        result = op1 / op2
      when '%'
        # The mod instruction divides the number(s) from the address referenced
        # by the B operand by the number(s) at the address referenced by the A
        # operand. The remainder from this division is stored at the
        # destination.
        # Dividing by zero is considered an illegal instruction in Corewar. The
        # executing warrior's process is removed from the process queue
        # (terminated).
        raise DivBy0Error if op2.zero?

        result = op1 % op2
      else
        raise ArgumentError, "Unknown operator #{operator}"
      end
      self.class.tracer&.operation("Computing #{tag1}:#{nformat(op1)} #{operator} #{tag2}:#{nformat(op2)} = " \
                                   "#{tag1}:#{nformat(result)}")

      result
    end

    # The djn instruction works in a similar way to the jmn instruction
    # detailed above with one addition. Before comparing the destination
    # instruction against zero, the number(s) at the destination instruction
    # are decremented. One common use of this opcode is to create the
    # equivalent of a simple for loop in higher level languages.
    # Unlike the jmn instruction, the djn instruction will perform the jump if
    # either operand is zero when using the .f, .x and .i modifiers.
    def djn(bus)
      rpa = bus.a_operand.pointer
      irb = bus.b_operand.instruction

      next_pc = [MemoryCore.fold(bus.program_counter + rpa)]

      case @modifier
      when 'A', 'BA'
        self.class.tracer&.operation("Decr. B.a:#{nformat(irb.a_number)}")
        irb.decrement_a_number(bus)
        self.class.tracer&.operation("Jumping to #{next_pc.first} if B.a:#{nformat(irb.a_number)} != 0")
        return next_pc unless irb.a_number.zero?
      when 'B', 'AB'
        self.class.tracer&.operation("Decr. B.b:#{nformat(irb.b_number)}")
        irb.decrement_b_number(bus)
        self.class.tracer&.operation("Jumping to #{next_pc.first} if B.b:#{nformat(irb.b_number)} != 0")
        return next_pc unless irb.b_number.zero?
      when 'F', 'X', 'I'
        self.class.tracer&.operation("Decr. B.a:#{nformat(irb.a_number)}")
        irb.decrement_a_number(bus)
        self.class.tracer&.operation("Decr. B.b:#{nformat(irb.b_number)}")
        irb.decrement_b_number(bus)
        self.class.tracer&.operation("Jumping to #{next_pc.first} if not (B.a:#{nformat(irb.a_number)} == 0 && " \
                                     "B.b:#{nformat(irb.b_number)} == 0)")
        return next_pc unless irb.a_number.zero? && irb.b_number.zero?
      else
        raise ArgumentError, "Unknown instruction modifier #{@modifier}"
      end

      [bus.program_counter + 1]
    end

    # The jmp instruction changes the address of the next instruction which
    # will be executed by the currently executing process. The most common
    # usages of this opcode are to create a loop or to skip over a section of
    # code.
    # Modifiers have no effect on the jmp instruction, the A operand is always
    # used as the jump address.
    def jmp(bus)
      rpa = bus.a_operand.pointer

      # Return a PC-relative jump destination address
      next_pc = MemoryCore.fold(bus.program_counter + rpa)
      self.class.tracer&.operation("Jumping to #{next_pc}")
      [next_pc]
    end

    # The jmz instruction works in the same way as the jmp instruction detailed
    # above with the exception that the jump is only performed if the number(s)
    # at the address referenced by the B operand is zero. This allows the jmz
    # instruction to function like an if statement in a higher level language.
    def jmz(bus)
      rpa = bus.a_operand.pointer
      irb = bus.b_operand.instruction

      # PC-relative jump destination address
      jump_pc = [MemoryCore.fold(bus.program_counter + rpa)]

      case @modifier
      when 'A', 'BA'
        self.class.tracer&.operation("Jumping to #{jump_pc.first} " \
                                     "if B.a:#{nformat(irb.a_number)} == 0")
        return jump_pc if irb.a_number.zero?
      when 'B', 'AB'
        self.class.tracer&.operation("Jumping to #{jump_pc.first} " \
                                     "if B.b:#{nformat(irb.b_number)} == 0")
        return jump_pc if irb.b_number.zero?
      when 'F', 'X', 'I'
        # Jump of both of the fields are zero
        self.class.tracer&.operation("Jumping to #{jump_pc.first} " \
                                     "if B.a:#{nformat(irb.a_number)} == 0 &&" \
                                     "B.b:#{nformat(irb.b_number)} == 0")
        return jump_pc if irb.a_number.zero? && irb.b_number.zero?
      else
        raise ArgumentError, "Unknown instruction modifier #{@modifier}"
      end

      [bus.program_counter + 1]
    end

    # The jmn instruction works in the same way as the jmz instruction detailed
    # above with the exception that the jump is performed if the referenced
    # number(s) are not zero.
    # Note that when comparing both A and B operands with zero, the jump will
    # not be taken if either operand is zero.
    def jmn(bus)
      rpa = bus.a_operand.pointer
      irb = bus.b_operand.instruction

      jump_pc = [MemoryCore.fold(bus.program_counter + rpa)]

      case @modifier
      when 'A', 'BA'
        self.class.tracer&.operation("Jumping to #{jump_pc.first} " \
                                     "if B.a:#{nformat(irb.a_number)} != 0")
        return jump_pc unless irb.a_number.zero?
      when 'B', 'AB'
        self.class.tracer&.operation("Jumping to #{jump_pc.first} " \
                                     "if B.b:#{nformat(irb.b_number)} != 0")
        return jump_pc unless irb.b_number.zero?
      when 'F', 'X', 'I'
        # Jump if either of the fields are zero
        self.class.tracer&.operation("Jumping to #{jump_pc.first} " \
                                     "unless B.a:#{nformat(irb.a_number)} == 0 || " \
                                     "B.b:#{nformat(irb.b_number)} == 0")
        return jump_pc unless irb.a_number.zero? || irb.b_number.zero?
      else
        raise ArgumentError, "Unknown instruction modifier #{@modifier}"
      end

      [bus.program_counter + 1]
    end

    # The mov instruction copies data from the address referenced by the A
    # operand to the address referenced by the B operand.
    def mov(bus)
      ira = bus.a_operand.instruction
      wpb = bus.b_operand.pointer
      irb = bus.b_operand.instruction

      return unless bus.memory_core.check_limit(:write_limit, bus.program_counter, irb.address)

      case @modifier
      when 'A'
        self.class.tracer&.operation("Replacing B.a:#{nformat(irb.a_number)} " \
                                     "with A.a:#{nformat(ira.a_number)}")
        irb.set_a_number(ira.a_number, bus)
      when 'B'
        self.class.tracer&.operation("Replacing B.b:#{nformat(irb.b_number)} " \
                                     "with A.b:#{nformat(ira.b_number)}")
        irb.set_b_number(ira.b_number, bus)
      when 'AB'
        self.class.tracer&.operation("Replacing B.b:#{nformat(irb.b_number)} " \
                                     "with A.a:#{nformat(ira.a_number)}")
        irb.set_b_number(ira.a_number, bus)
      when 'BA'
        self.class.tracer&.operation("Replacing B.a:#{nformat(irb.a_number)} " \
                                     "with A.b:#{nformat(ira.b_number)}")
        irb.set_a_number(ira.b_number, bus)
      when 'F'
        self.class.tracer&.operation("Replacing B.a:#{nformat(irb.a_number)} " \
                                     "with A.a:#{nformat(ira.a_number)} and " \
                                     "B.b:#{nformat(irb.b_number)} " \
                                     "with A.b:#{nformat(ira.b_number)}")
        irb.set_a_number(ira.a_number, bus)
        irb.set_b_number(ira.b_number, bus)
      when 'X'
        self.class.tracer&.operation("Replacing B.a:#{nformat(irb.a_number)} " \
                                     "with A.b:#{nformat(ira.b_number)} and " \
                                     "B.b:#{nformat(irb.b_number)} " \
                                     "with A.a:#{nformat(ira.a_number)}")
        irb.set_a_number(ira.b_number, bus)
        irb.set_b_number(ira.a_number, bus)
      when 'I'
        # Copies entire instruction
        self.class.tracer&.operation('Copy A instruction into B instruction')
        # Ensure ownership of modified instruction
        bus.memory_core.store_relative(bus.base_address, bus.program_counter, wpb, ira, bus.pid)
      else
        raise ArgumentError, "Unknown instruction modifier #{@modifier}"
      end
    end

    # The seq or cmp instruction compares the number(s) at the addresses
    # specified by its source and destination operands and if they are equal,
    # increments the next address to be executed by the current process by one
    # - in effect skipping the next instruction. Skip instructions are commonly
    # used to develop scanners which scan the core looking for other warriors.
    def seq(bus)
      jump_conditional(bus, :==, '==')
    end

    # The sne instruction works in the same way as the seq instruction detailed
    # above with the exception that the next instruction is skipped if the
    # source and destination instructions are not equal.
    def sne(bus)
      jump_conditional(bus, :!=, '!=')
    end

    # The slt instruction compares the number(s) at the addresses specified by
    # its source and destination operands. If the source number(s) are less
    # than the destination number(s), the next address to be executed by
    # the current process is incremented by one - in effect skipping the next
    # instruction.
    def slt(bus)
      jump_conditional(bus, :<, '<')
    end

    # The spl instruction spawns a new process for the current warrior at the
    # address specified by the A operand.
    # The newly created process is added to the process queue after the
    # currently executing process.
    def spl(bus)
      rpa = bus.a_operand.pointer

      next_pc = MemoryCore.fold(bus.program_counter + rpa)
      self.class.tracer&.operation("Forking to #{next_pc}")
      # Fork off another thread. One thread continues at the next instruction, the other at
      # the A-Pointer.
      [bus.program_counter + 1, next_pc]
    end

    def jump_conditional(bus, op, op_text)
      ira = bus.a_operand.instruction
      irb = bus.b_operand.instruction

      next2_pc = [bus.program_counter + 2]

      case @modifier
      when 'A'
        self.class.tracer&.operation("Jumping to #{next2_pc.first} " \
                                     "if A.a:#{nformat(ira.a_number)} " \
                                     "#{op_text} B.a:#{nformat(irb.a_number)}")
        return next2_pc if ira.a_number.send(op, irb.a_number)
      when 'B'
        self.class.tracer&.operation("Jumping to #{next2_pc.first} " \
                                     "if A.b:#{nformat(ira.b_number)} " \
                                     "#{op_text} B.b:#{nformat(irb.b_number)}")
        return next2_pc if ira.b_number.send(op, irb.b_number)
      when 'AB'
        self.class.tracer&.operation("Jumping to #{next2_pc.first} " \
                                     "if A.a:#{nformat(ira.a_number)} " \
                                     "#{op_text} B.b:#{nformat(irb.b_number)}")
        return next2_pc if ira.a_number.send(op, irb.b_number)
      when 'BA'
        self.class.tracer&.operation("Jumping to #{next2_pc.first} " \
                                     "if A.b:#{nformat(ira.b_number)} " \
                                     "#{op_text} B.a:#{nformat(irb.a_number)}")
        return next2_pc if ira.b_number.send(op, irb.a_number)
      when 'F'
        self.class.tracer&.operation("Jumping to #{next2_pc.first} " \
                                     "if A.a:#{nformat(ira.a_number)} " \
                                     "#{op_text} B.a:#{nformat(irb.a_number)} &&" \
                                     "A.b:#{nformat(ira.b_number)} " \
                                     "#{op_text} B.b:#{nformat(irb.b_number)}")
        return next2_pc if ira.a_number.send(op, irb.a_number) && ira.b_number.send(op, irb.b_number)
      when 'X'
        self.class.tracer&.operation("Jumping to #{next2_pc.first} " \
                                     "if A.a:#{nformat(ira.b_number)} " \
                                     "#{op_text} B.b:#{nformat(irb.b_number)} &&" \
                                     "A.b:#{nformat(ira.b_number)} " \
                                     "#{op_text} B.a:#{nformat(irb.a_number)}")
        return next2_pc if ira.a_number.send(op, irb.b_number) && ira.b_number.send(op, irb.a_number)
      when 'I'
        if op_text == '<'
          # For the < operation, .I is identical to .F
          self.class.tracer&.operation("Jumping to #{next2_pc.first} " \
                                       "if A.a:#{nformat(ira.a_number)} " \
                                       "#{op_text} B.a:#{nformat(irb.a_number)} &&" \
                                       "A.b:#{nformat(ira.b_number)} " \
                                       "#{op_text} B.b:#{nformat(irb.b_number)}")
          return next2_pc if ira.a_number.send(op, irb.a_number) && ira.b_number.send(op, irb.b_number)
        else
          self.class.tracer&.operation("Jumping to #{next2_pc.first} if A:#{ira} #{op_text} B:#{irb}")
          return next2_pc if ira.send(op, irb)
        end
      else
        raise ArgumentError, "Unknown instruction modifier #{@modifier}"
      end

      [bus.program_counter + 1]
    end
  end
end
