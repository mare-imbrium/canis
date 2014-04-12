require 'canis'

module Canis

  #
  # A vim-like application status bar that can display time and various other statuses
  #  at the bottom, typically above the dock (3rd line from last).
  #
  class ListFooter
    attr_accessor :config
    attr_accessor :color_pair
    attr_accessor :attrib

    def initialize config={}, &block
      @config = config
      @color_pair = get_color($datacolor, config[:color], config[:bgcolor]) 
      @attrib = config[:attrib]
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
      @command_text.call(comp, @command_args) 
    end
    def right_text(comp)
      @right_text.call(comp, @right_args) 
    end

    # supply a default print function. The user program need not call this. It may be overridden
    def print comp
      config = @config
      row = comp.row + comp.height - 1
      col = comp.col + 2
      len = comp.width - col 
      g = comp.form.window
      # we check just in case user nullifies it deliberately, since he may have changed config values
      @color_pair ||= get_color($datacolor, config[:color], config[:bgcolor]) 
      @attrib ||= config[:attrib] || Ncurses::A_REVERSE
      

      # first print dashes through
      #g.printstring row, col, "%s" % "-" * len, @color_pair, Ncurses::A_REVERSE

      # now call the block to get current values for footer text on left
      ftext = nil
      if @command_text
        ftext = text(comp) 
      else
        if !@right_text
          # user has not specified right or left, so we use a default on left
          ftext = "#{comp.current_index} of #{comp.size}   "
        end
      end
      g.printstring(row, col, ftext, @color_pair, @attrib) if ftext

      # user has specified text for right, print it
      if @right_text
        len = comp.width
        ftext = right_text(comp)
        c = len - ftext.length - 2
        g.printstring row, c, ftext, @color_pair, @attrib
      end
    end

    
  end # class
end # module
