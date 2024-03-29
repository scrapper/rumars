#
# Copyright (c) Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# frozen_string_literal: true

require_relative 'terminal'
require_relative 'window'
require_relative 'splits'

module TextWM
  class WindowManager
    attr_reader :terminal, :active_window

    def initialize(out, inp)
      @terminal = Terminal.new(out, inp)
      @terminal.reset
      @terminal.clear

      @splits = nil
      @windows = []
      @active_window = nil
      @panels = []

      # Set to true to exit the event loop
      @exit_application = false
    end

    def resize
      raise 'Screen must be split first before calling resize' unless @splits

      columns, rows = @terminal.size

      return if columns < 40 || rows < 20

      @splits.resize(0, 0, columns, rows)
    end

    def split(direction, *ratios)
      @splits = Splits.new(direction, *ratios)
    end

    def register_window(window)
      @windows << window
      focus_window(window)
    end

    def register_panel(panel)
      @panels << panel
    end

    # The specified window to be the one that the user interacts with.
    # Other windows my continue to update their content, but the user can't
    # directly interact with them.
    def focus_window(window)
      raise 'Unknown window' unless @windows.include?(window)

      @active_window.active = false if @active_window
      @active_window = window
      window.active = true
    end

    def update_windows
      @windows.each do |window|
        next unless window.visible?

        window.update
      end
      @panels.each(&:update)

      @active_window.show_cursor
    end

    def exit_application
      @exit_application = true
    end

    def event_loop
      loop do
        update_windows

        Signal.trap('WINCH') { throw :signal_terminal_resized }
        c = nil
        catch(:signal_terminal_resized) do
          c = @terminal.getch
        end
        Signal.trap('WINCH', 'DEFAULT')

        process_keystroke(c)

        break if @exit_application
      end

      @terminal.clear
      @terminal.reset
    end

    def process_keystroke(char)
      if char.nil?
        resize
        return
      end

      @panels.each do |panel|
        return if panel.getch(char)
      end

      @active_window.getch(char)
    end

    def next_window
      i = 1
      loop do
        window = @windows[(@windows.index(@active_window) + i) % @windows.size]
        # Only return visible windows.
        return window if window.visible?

        i += 1
      end
    end

    def prev_window
      i = 1
      loop do
        window = @windows[(@windows.size + @windows.index(@active_window) - i) % @windows.size]
        # Only return visible windows.
        return window if window.visible?

        i += 1
      end
    end
  end
end
