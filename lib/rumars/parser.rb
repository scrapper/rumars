# frozen_string_literal: true

require 'strscan'

require_relative 'program'
require_relative 'instruction'
require_relative 'expression'

# REDCODE 94 Syntax definition
#
# Taken from http://www.koth.org/info/icws94.html
#
# assembly_file:
#         list
# list:
#         line | line list
# line:
#         comment | instruction
# comment:
#         ; v* EOL | EOL
# instruction:
#         label_list operation mode field comment |
#         label_list operation mode expr , mode expr comment
# label_list:
#         label | label label_list | label newline label_list | e
# label:
#         alpha alphanumeral*
# operation:
#         opcode | opcode.modifier
# opcode:
#         DAT | MOV | ADD | SUB | MUL | DIV | MOD |
#         JMP | JMZ | JMN | DJN | CMP | SLT | SPL |
#         ORG | EQU | END
# modifier:
#         A | B | AB | BA | F | X | I
# mode:
#         # | $ | @ | < | > | e
# expr:
#         term |
#         term + expr | term - expr |
#         term * expr | term / expr |
#         term % expr
# term:
#         label | number | (expression)
# number:
#         whole_number | signed_integer
# signed_integer:
#         +whole_number | -whole_number
# whole_number:
#         numeral+
# alpha:
#         A-Z | a-z | _
# numeral:
#         0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
# alphanumeral:
#         alpha | numeral
# v:
#         ^EOL
# EOL:
#         newline | EOF
# newline:
#         LF | CR | LF CR | CR LF
# e:

module RuMARS
  # REDCODE parser
  class Parser
    # This class handles all parsing errors.
    class ParseError < RuntimeError
      def initialize(parser, message)
        super()
        @parser = parser
        @message = message
      end

      def to_s
        "#{@parser.file_name ? "#{@parser.file_name}: " : ''}#{@parser.line_no}: #{@message}'\n" \
          "  #{@parser.scanner.string}\n" \
          "  #{' ' * @parser.scanner.pos}^"
      end
    end

    attr_reader :file_name, :line_no, :scanner

    def initialize
      @line_no = 0
      @file_name = nil
      @scanner = nil
      # Hash to store the EQU definitions
      @constants = {}
    end

    def parse(source_code)
      @program = Program.new

      @line_no = 1
      @ignore_lines = true
      source_code.lines.each do |line|
        # Remove trailing line break
        line.chop!

        # Redcode files require a line that reads
        # ;redcode-94
        # All lines before this line will be ignored.
        @ignore_lines = false if /^;redcode(-94|)\s*$/ =~ line

        @line_no += 1

        # Ignore empty lines
        next if @ignore_lines || /\A\s*\z/ =~ line

        @constants.each do |name, text|
          line.gsub!(/(?!=\w)#{name}(?!<=\w)/, text)
        end

        @scanner = StringScanner.new(line)
        comment_or_instruction
      end

      begin
        @program.evaluate_expressions
      rescue Expression::ExpressionError => e
        raise ParseError.new(self, "Error in expression: #{e.message}")
      end

      @program
    end

    private

    def scan(regexp)
      # puts "Scanning '#{@scanner.string[@scanner.pos..]}' with #{regexp}"
      @scanner.scan(regexp)
    end

    #
    # Terminal Tokens
    #
    def space
      scan(/\s*/) || ''
    end

    def semicolon
      scan(/;/)
    end

    def comma
      scan(/,/)
    end

    def operator
      scan(/[-+*\\%]/)
    end

    def open_parenthesis
      scan(/\(/)
    end

    def close_parenthesis
      scan(/\)/)
    end

    def sign_prefix
      scan(/[+-]/)
    end

    def anything
      scan(/.*$/)
    end

    def label
      scan(/[A-Za-z_][A-Za-z0-9]*/)
    end

    def equ
      scan(/EQU/i)
    end

    def end_token
      scan(/END/i)
    end

    def org
      scan(/ORG/i)
    end

    def not_comment
      scan(/[^;\n]+/)
    end

    def opcode
      scan(/(ADD|CMP|DAT|DIV|DJN|JMN|JMP|JMZ|MOD|MOV|MUL|NOP|SEQ|SNE|SLT|SPL|SUB)/i)
    end

    def mode
      scan(/[#@*<>{}$]/) || '$'
    end

    def modifier
      scan(/\.(AB|BA|A|B|F|X|I)/i)
    end

    def whole_number
      scan(/[0-9]+/)
    end

    #
    # Grammar
    #
    def comment_or_instruction
      (comment || instruction_line)
    end

    def comment
      (s = semicolon) && (text = anything)

      return nil unless s

      if text.start_with?('name ')
        @program.name = text[5..].strip
      elsif text.start_with?('author ')
        @program.author = text[7..].strip
      elsif text.start_with?('strategy ')
        @program.add_strategy(text[9..])
      end

      ''
    end

    def instruction_line
      (label = optional_label) && space && pseudo_or_instruction(label) && space && optional_comment
    end

    def pseudo_or_instruction(label)
      equ_instruction(label) || end_instruction || org_instruction || instruction(label)
    end

    def equ_instruction(label)
      (e = equ) && space && (definition = not_comment)

      return nil unless e

      raise ParseError.new(self, 'EQU lines must have a label') if label.empty?

      raise ParseError.new(self, "Constant #{label} has already been defined") if @constants.include?(label)

      @constants[label] = definition
    end

    def org_instruction
      (o = org) && space && (exp = expr)

      return nil unless o

      raise ParseError.new(self, 'Expression expected') unless exp

      @program.start_address = exp
    end

    def end_instruction
      (e = end_token) && space && (exp = expr)

      return nil unless e

      # Older Redcode standards used the END instruction to set the program start address
      @program.start_address = exp if exp

      @ignore_lines = true
    end

    def instruction(label)
      (opc = opcode) && (mod = optional_modifier[1..]) &&
        space && (e1 = expression) && space && (e2 = optional_expression) && space && optional_comment

      raise ParseError.new(self, 'Uknown instruction') unless opc
      # Redcode instructions are case-insensitive. We use upper case internally,
      # but allow for lower-case notation in source files.
      opc.upcase!
      mod.upcase!

      raise ParseError.new(self, "Instruction #{opc} must have an A-operand") unless e1

      @program.add_label(label) unless label.empty?

      # The default B-operand is an immediate value of 0
      e2 ||= Operand.new('#', Expression.new(0, nil, nil))
      mod = default_modifier(opc, e1, e2) if mod == ''

      instruction = Instruction.new(0, opc, mod, e1, e2)
      @program.append_instruction(instruction)
    end

    def optional_label
      label || ''
    end

    def optional_modifier
      modifier || '.'
    end

    def optional_expression
      comma && space && expression
    end

    def expression
      (m = mode) && (e = expr)
      raise ParseError.new(self, 'Expression expected') unless e

      Operand.new(m, e)
    end

    def expr
      (t1 = term) && space && (optr = operator) && space && (t2 = expr)

      if optr
        raise ParseError.new(self, 'Right hand side of expression is missing') unless t2

        Expression.new(t1, optr, t2)
      else
        t1
      end
    end

    def term
      t = (label || number || parenthesized_expression)

      return nil unless t

      Expression.new(t, nil, nil)
    end

    def parenthesized_expression
      (op = open_parenthesis) && space && (e = expr) && space && (cp = close_parenthesis)

      return nil unless op

      raise ParseError.new(self, 'Expression expected') unless e

      raise ParseError.new(self, "')' expected") unless cp

      e
    end

    def number
      (s = signed_number) || (n = whole_number)

      return s if s

      n ? n.to_i : nil
    end

    def signed_number
      (sign = sign_prefix) && (n = whole_number)
      return nil unless sign

      sign == '-' ? -(n.to_i) : n.to_i
    end

    def optional_comment
      comment || ''
    end

    #
    # Utility methods
    #
    def default_modifier(opc, e1, e2)
      case opc
      when 'ORG', 'END'
        return ''
      when 'DAT', 'NOP'
        return 'F'
      when 'MOV', 'CMP'
        return 'AB' if e1.address_mode == '#' && '#$@*<>{}'.include?(e2.address_mode)
        return 'B' if '$@*<>{}'.include?(e1.address_mode) && e2.address_mode == '#'
        return 'I'
      when 'ADD', 'SUB', 'MUL', 'DIV', 'MOD'
        return 'AB' if e1.address_mode == '#' && '#$@*<>{}'.include?(e2.address_mode)
        return 'B' if '$@*<>{}'.include?(e1.address_mode) && e2.address_mode == '#'
        return 'F'
      when 'SLT'
        return 'AB' if e1.address_mode == '#' && '#$@*<>{}'.include?(e2.address_mode)
        return 'B'
      when 'JMP', 'JMZ', 'JMN', 'DJN', 'SPL'
        return 'B'
      when 'SEQ', 'SNE'
        return 'I'
      else
        raise ParseError.new(self, "Unknown instruction #{opc}")
      end

      raise ParseError.new(self, "Cannot determine default modifier for #{opc} #{e1}, #{e2}")
    end
  end
end
