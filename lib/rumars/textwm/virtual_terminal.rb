#
# Copyright (c) Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# frozen_string_literal: true

require_relative 'string'

module TextWM
  class VirtualTerminal
    attr_accessor :right_clip, :bottom_clip, :view_top_line

    def initialize(columns, rows)
      # The size of the visible part of the buffer
      @view_columns = columns
      @view_rows = rows
      @max_lines = 500

      @right_clip = @bottom_clip = false

      clear
    end

    def clear
      # The buffer can be larger than the window view but we
      # start with a buffer that has as many lines as the view.
      @buffer_lines = []
      @buffer_lines << String.new
      # The cursor marks where in the buffer the next character
      # will be written.
      @cursor_row = 0
      @cursor_column = 0
      # The index of the first line visible in the view.
      @view_top_line = 0
    end

    def backspace
      return unless @cursor_column.positive?

      @cursor_column -= 1
      line = @buffer_lines[@cursor_row]
      @buffer_lines[@cursor_row] = line[0..@cursor_column - 1] + line[@cursor_column + 1..]
    end

    def clear_row
      @buffer_lines[@cursor_row] = +''
      @cursor_column = 0
    end

    def resize(columns, rows)
      @view_columns = columns
      @view_rows = rows

      return unless @cursor_row - @view_top_line > @view_rows - 1

      # The cursor is no longer inside the visible area. Update the @view_top_line
      # to ensure that the cursor is at least on the last visible line.
      @view_top_line = @cursor_row - @view_rows + 1
    end

    def scroll(lines)
      # Adjust first visible line by 'lines'. To scroll up,
      # lines must be negative. This increases the @view_top_line.
      # To scroll down, lines must be positive.
      @view_top_line -= lines

      # Ensure that the @view_top_line does not get negative.
      @view_top_line = 0 if @view_top_line.negative?

      # When scrolling up we ensure that the last @view_rows lines
      # of the buffer stay visible.
      lowest_view_top_line = @buffer_lines.length - @view_rows
      # We might not have @view_rows lines in the buffer.
      lowest_view_top_line = 0 if lowest_view_top_line.negative?
      @view_top_line = lowest_view_top_line if @view_top_line > lowest_view_top_line
    end

    def puts(str)
      print "#{str}\n"
    end

    def print(str)
      str.each_char do |c|
        if c == "\n"
          # If we have bottom clip mode enabled, we ignore all lines
          # that don't fit the view.
          next if @bottom_clip && @cursor_row >= @view_rows - 1

          @cursor_row += 1
          @cursor_column = 0
          @buffer_lines << String.new
          scroll(-1)

          if @buffer_lines.length >= @max_lines
            # The first line is discarded.
            @buffer_lines.shift
            @cursor_row -= 1
            @view_top_line -= 1
          end
        else
          @buffer_lines.last[@cursor_column] = c
          @cursor_column += 1
        end
      end
    end

    # Return the row of the cursor in window coordinates
    def cursor_row
      @cursor_row - @view_top_line
    end

    # @return the column of the cursor in window coordinates
    def cursor_column
      @buffer_lines[@cursor_row[0..@cursor_column]].visible_length
    end

    def line_count
      @buffer_lines.length
    end

    def line(index)
      if (line = @buffer_lines[@view_top_line + index])
        length = line.visible_length

        if length < @view_columns
          line + (' ' * (@view_columns - length))
        else
          line.first_visible_characters(@view_columns)
        end
      else
        # The line is empty. Blank out the screen line.
        @view_columns.negative? ? '' : ' ' * @view_columns
      end
    end
  end
end
