require 'canis'

module Canis

  #
  # A vim-like application status bar that can display time and various other statuses
  #  at the bottom, typically above the dock (3rd line from last).
  #
  class ListFooter
    attr_accessor :config

    def initialize config={}, &block
      @config = config
      instance_eval &block if block_given?
    end
    #
    # command that returns a string that populates the status line (left aligned)
    # @see :right
    # e.g. 
    #   @l.command { "%-20s [DB: %-s | %-s ]" % [ Time.now, $current_db || "None", $current_table || "----"] }  
    #
    def command *args, &blk
      @command_text = blk
      @command_args = args
    end
    alias :left :command

    # 
    # Procudure for text to be right aligned in statusline
    def command_right *args, &blk
      @right_text = blk
      @right_args = args
    end
    def text(comp)
      @command_text.call(comp, @args) 
    end

    # NOTE: I have not put a check of repaint_required, so this will print on each key-stroke OR
    #   rather whenever form.repaint is called.
    def print comp
      row = comp.row + comp.height - 1
      col = comp.col + 2
      @color_pair ||= get_color($datacolor, @color, @bgcolor) 
      len = comp.width - col
      g = comp.window

      # first print dashes through
      g.printstring row, col, "%s" % "-" * len, @color_pair, Ncurses::A_REVERSE

      # now call the block to get current values
      if @text
        ftext = @text.call(comp, @args) 
      else
        #ftext = " %-20s | %s" % [Time.now, status] # should we print a default value just in case user doesn't
        ftext = "Dummy"
      end

      if @right_text
        len = comp.width
        ftext = @right_text.call(self, @right_args) 
        c = len - ftext.length
        g.printstring @row, c, ftext, @color_pair, Ncurses::A_REVERSE
      end
    end

    
  end # class
end # module
