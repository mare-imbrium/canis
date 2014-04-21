# ----------------------------------------------------------------------------- #
#         File: window.rb
#  Description: A wrapper over window
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: Around for a long time
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-04-21 14:19
#
#  == CHANGED
#     removed Pad and Subwin to lib/ver/rpad.rb - hopefully I've seen the last of both
#
# == TODO
#    strip and remove cruft. Now that I've stopped using pad, can we remove
#    the prv_printstring nonsense.
# ----------------------------------------------------------------------------- #
#
require 'canis/core/system/ncurses'
require 'canis/core/system/panel'
require 'canis/core/include/chunk'
# this is since often windows are declared with 0 height or width and this causes
# crashes in the most unlikely places. This prevceents me from having to write ternary
# e.g.
#     @layout[:width].ifzero(FFI::NCurses::LINES-2)
class Fixnum
  def ifzero v
    return self if self != 0
    return v
  end
end

module Canis
  class Window 
    attr_reader :width, :height, :top, :left
    attr_accessor :layout # hash containing hwtl
    attr_reader   :panel   # reader requires so he can del it in end
    attr_reader   :window_type   # window or pad to distinguish 2009-11-02 23:11 
    attr_accessor :name  # more for debugging log files. 2010-02-02 19:58 
    attr_accessor :modified # has it been modified and may need a refresh

    # @param [Array, Hash] window coordinates (ht, w, top, left)
    # or 
    # @param [int, int, int, int] window coordinates (ht, w, top, left)
    # 2011-09-21 allowing array, or 4 ints,  in addition to hash @since 1.3.1
    def initialize(*args)

      case args.size
      when 1
        case args[0]
        when Array, Hash
         layout = args[0]
        else
          raise ArgumentError, "Window expects 4 ints, array of 4 ints, or Hash in constructor"
        end
      when 4
        layout = { :height => args[0], :width => args[1], :top => args[2], :left => args[3] }
      end

      @visible = true
      reset_layout(layout)

      #$log.debug "XXX:WINDOW got h #{@height}, w #{@width}, t #{@top}, l #{@left} "

      @height = FFI::NCurses.LINES if @height == 0   # 2011-11-14 added since tired of checking for zero
      @width = FFI::NCurses.COLS   if @width == 0

      @window = FFI::NCurses.newwin(@height, @width, @top, @left) # added FFI 2011-09-6 
      @panel = Ncurses::Panel.new(@window) # added FFI 2011-09-6 
      #$error_message_row = $status_message_row = Ncurses.LINES-1
      $error_message_row ||= Ncurses.LINES-1
      $error_message_col ||= 1 # ask (bottomline) uses 0 as default so you can have mismatch. XXX
      $status_message ||= Canis::Variable.new # in case not an App

      $key_map ||= :vim
      $esc_esc = true; # gove me double esc as 2727 so i can map it.
      init_vars

      unless @key_reader
        create_default_key_reader
      end


    end
    def init_vars
      @window_type = :WINDOW
      Ncurses::keypad(@window, true)
      # Added this so we can get Esc, and also C-c pressed in succession does not crash system
      #  2011-12-20 half-delay crashes system as does cbreak
      #This causes us to be unable to process gg qq since getch won't wait.
      #Ncurses::nodelay(@window, bf = true)
      # wtimeout was causing RESIZE sigwinch to only happen after pressing a key
      #Ncurses::wtimeout(@window, $ncurses_timeout || 500) # will wait a second on wgetch so we can get gg and qq
      #@stack = [] # since we have moved to handler 2014-04-20 - 11:15 
      @name ||="#{self}"
      @modified = true
      $catch_alt_digits ||= false # is this where is should put globals ? 2010-03-14 14:00 XXX
    end
    ##
    # this is an alternative constructor
    def self.root_window(layout = { :height => 0, :width => 0, :top => 0, :left => 0 })
      #Canis::start_ncurses
      @layout = layout
      @window = Window.new(@layout)
      @window.name = "Window::ROOTW"
      @window.wrefresh
      Ncurses::Panel.update_panels
      return @window
    end
    # 2009-10-13 12:24 
    # not used as yet
    # this is an alternative constructor
    # created if you don't want to create a hash first
    #  2011-09-21 V1.3.1 You can now send an array to Window constructor
    def self.create_window(h=0, w=0, t=0, l=0)
      layout = { :height => h, :width => w, :top => t, :left => l }
      @window = Window.new(layout)
      return @window
    end

    def resize_with(layout)
      $log.debug " DARN ! This awready duz a resize!! if h or w or even top or left changed!!! XXX"
      reset_layout(layout)
      #@window.wresize(height, width)
      wresize(height, width)
      #FFI::NCurses.wresize(@window,height, width)
      # this is dicey since we often change top and left in pads only for panning !! XXX
      #@window.mvwin(top, left)
      mvwin(top, left)
      #FFI::NCurses.mvwin(@window, top, left)
    end

    %w[width height top left].each do |side|
      eval(
      "def #{side}=(n)
         return if n == #{side}
         @layout[:#{side}] = n
         resize_with @layout
       end"
      )
    end
    # ADDED DUE TO FFI 
    def wrefresh
      Ncurses.wrefresh(@window)
    end
    def delwin # 2011-09-7 
      Ncurses.delwin(@window)
    end
    def attron *args
      FFI::NCurses.wattron @window, *args
    end
    def attroff *args
      FFI::NCurses.wattroff @window, *args
    end
    #
    # ## END FFI

    def resize
      resize_with(@layout)
    end

    # Ncurses

    def pos
      return y, x
    end

    def y
      Ncurses.getcury(@window)
    end

    def x
      Ncurses.getcurx(@window)
    end

    def x=(n) move(y, n) end
    def y=(n) move(n, x) end

    #def move(y, x)
      #return unless @visible
##       Log.debug([y, x] => caller[0,4])
      ##@window.wmove(y, x) # bombing since ffi-ncurses 0.4.0 (maybe it was never called
      ##earlier. was crashing in appemail.rb testchoose.
      #wmove y,x # can alias it
    #end
    # since include FFI is taking over, i need to force it here. not going into
    # method_missing
    def wmove y,x
      #Ncurses.wmove @window, y, x
      FFI::NCurses.wmove @window, y, x
    end
    alias :move :wmove

    # while moving from ncurses-ruby to FFI need to pass window pointer
    # for w methods as well as mvw - NOT COMING HERE due to include FFI
    def OLDmethod_missing(meth, *args)
      $log.debug " WWWW method missing #{meth} "
      if meth[0,1]=="w" || meth[0,3] == "mvw"
        $log.debug " WWWW method missing #{meth} adding window in call "
        #return @window.send(meth, @window, *args)
        return FFI::NCurses.send(meth, @window, *args)
      else
      end
      if @window
        if @window.respond_to? meth
          @window.send(meth, *args)
        else
          FFI::NCurses.send( meth, *args)
        end
      else
        FFI::NCurses.send( meth, *args)
      end
    end

    def method_missing(name, *args)
      name = name.to_s
      if (name[0,2] == "mv")
        test_name = name.dup
        test_name[2,0] = "w" # insert "w" after"mv"
        if (FFI::NCurses.respond_to?(test_name))
          return FFI::NCurses.send(test_name, @window, *args)
        end
      end
      test_name = "w" + name
      if (FFI::NCurses.respond_to?(test_name))
        return FFI::NCurses.send(test_name, @window, *args)
      end
      FFI::NCurses.send(name, @window, *args)
    end
    def respond_to?(name)
      name = name.to_s
      if (name[0,2] == "mv" && FFI::NCurses.respond_to?("mvw" + name[2..-1]))
        return true
      end
      FFI::NCurses.respond_to?("w" + name) || FFI::NCurses.respond_to?(name)
    end

    # NOTE: many of these methods using width will not work since root windows width 
    #  is 0
    def print(string, width = width)
      return unless visible?
      w = width == 0? Ncurses.COLS : width
      waddnstr(string.to_s, w) # changed 2011 dts  
    end

    # NOTE: many of these methods using width will not work since root windows width 
    #  is 0
    def print_yx(string, y = 0, x = 0)
      w = width == 0? Ncurses.COLS : width
      mvwaddnstr(y, x, string, w) # changed 2011 dts  
    end

    # NOTE: many of these methods using width will not work since root windows width 
    #  is 0
    def print_empty_line
      return unless visible?
      w = getmaxx == 0? Ncurses.COLS : getmaxx
      printw(' ' * w)
    end

    # NOTE: many of these methods using width will not work since root windows width 
    #  is 0
    def print_line(string)
      w = getmaxx == 0? Ncurses.COLS : getmaxx
      print(string.ljust(w))
    end

    # returns the actual width in case you've used a root window
    # which returns a 0 for wid and ht
    # NOTE: this does not work when resize , use getmaxx instead
    #
    def actual_width
      width == 0? Ncurses.COLS : width
    end
    
    #
    # returns the actual ht in case you've used a root window
    # which returns a 0 for wid and ht
    #
    def actual_height
      height == 0? Ncurses.LINES : height
    end
    
    # NOTE: many of these methods using width will not work since root windows width 
    #  is 0
    #  Previously this printed a chunk as a full line, I've modified it to print on 
    #  one line. This can be used for running text. 
    #  NOTE 2013-03-08 - 17:02 added width so we don't overflow
    def show_colored_chunks(chunks, defcolor = nil, defattr = nil, wid = 999, pcol = 0)
      return unless visible?
      ww = 0
      chunks.each do |chunk| #|color, chunk, attrib|
        case chunk
        when Chunks::Chunk
          color = chunk.color
          attrib = chunk.attrib
          text = chunk.text

          ## 2013-03-08 - 19:11 take care of scrolling by means of pcol
          if pcol > 0
            if pcol > text.length 
              # ignore entire chunk and reduce pcol
              pcol -= text.length
              next
            else
              # print portion of chunk and zero pcol
              text = text[pcol..-1]
              pcol = 0
            end
          end
          oldw = ww
          ww += text.length
          if ww > wid
            # if we are exceeding the width then by howmuch
            rem = wid - oldw
            if rem > 0
              # take only as much as we are allowed
              text = text[0,rem]
            else
              break
            end
          end
        when Array
          # for earlier demos that used an array
          color = chunk[0]
          attrib = chunk[2]
          text = chunk[1]
        end

        color ||= defcolor
        attrib ||= defattr

        cc, bg = ColorMap.get_colors_for_pair color
        #$log.debug "XXX: CHUNK window #{text}, cp #{color} ,  attrib #{attrib}. #{cc}, #{bg} " 
        color_set(color,nil) if color
        wattron(attrib) if attrib
        print(text)
        wattroff(attrib) if attrib
      end
    end

    def puts(*strings)
      print(strings.join("\n") << "\n")
    end

    def _refresh
      return unless visible?
      @window.refresh
    end

    def wnoutrefresh
      return unless visible?
      @window.wnoutrefresh
    end

    def color=(color)
      @color = color
      @window.color_set(color, nil)
    end

    def highlight_line(color, y, x, max)
      @window.mvchgat(y, x, max, Ncurses::A_NORMAL, color, nil)
    end

    def ungetch(ch)
      Ncurses.ungetch(ch)
    end

    # reads a character from keyboard and returns
    # NOTE:
    #   if a function key is pressed, multiple such ints will be returned one after the other
    #   so the caller must decipher the same. See +getchar()+
    #
    # @return int 
    # @return -1 if no char read
    #
    def getch
      #c = @window.getch
      c = FFI::NCurses.wgetch(@window)
      # the only reason i am doing this is so ESC can be returned if no key is pressed
      # after that, not sure how this effects everything. most likely I should just
      # go back to using a wtimeout, and not worry about resize requiring a keystroke
      if c == 27
        Ncurses::wtimeout(@window, $ncurses_timeout || 500) # will wait a second on wgetch so we can get gg and qq
      else
        Ncurses::nowtimeout(@window, true)
      end
      c
      # 2011-12-20 - i am trying setting a timer on wgetch, see timeout
      #c = FFI::NCurses.getch # this will keep waiting, nodelay won't be used on it, since 
      # we've put nodelay on window
      #if c == Ncurses::KEY_RESIZE

    rescue SystemExit, Interrupt 
      #FFI::NCurses.flushinp
      3 # is C-c
    rescue StandardError
      -1 # is C-c
    end

    # Earlier this was handled by window itself. Now we delegate to a reader
    # @return int keycode, can be function key or meta or arrow key.
    #
    # NOTE:
    #  This is called by user programs in a loop. 
    #  We are now moving from returning an int to returning a string similar to what
    #  user would get on commandline using C-v
    #
    def getchar
      @key_reader.getchar
    end

    # This was getchar() earlier, now i am trying to put it in a class
    # so user can install his own and experiment.
    #
    # This is directly called by the users program in a loop.
    #
    # returns control, alt, alt+ctrl, alt+control+shift, F1 .. etc
    # ALT combinations also send a 27 before the actual key
    # Please test with above combinations before using on your terminal
    # added by jkepler 2008-12-12 23:07 
    #  2011-09-23 Redone Control-left, right, and Shift-F5..F10.
    #  Checking for quick press of Alt-Sh-O followed by Alt or printable char
    #  Checking for quick press of Alt-[ followed by Alt or printable char
    #  I attempted keeping a hash of combination arrays but it fails in the above
    #  2 cases, so abandoned.
    def _getchar 
      while 1 
        ch = self.getch
        #$log.debug "window getchar() GOT: #{ch}" if ch != -1
        sf = @stack.first
        if ch == -1
          # the returns escape 27 if no key followed it, so its SLOW if you want only esc
          if @stack.first == 27
            #$log.debug " -1 stack sizze #{@stack.size}: #{@stack.inspect}, ch #{ch}"
            case @stack.size
            when 1
              @stack.clear
              return 27
            when 2 # basically a ALT-O, or alt-[ (79 or 91) this will be really slow since it waits for -1
              ch = 128 + @stack.last
              $log.warn "XXX: WARN  #{ch} CLEARING stack #{@stack} "
              @stack.clear
              return ch
            else
              # check up a hash of special keys
              ret = SPECIAL_KEYS(@stack)
              return ret if ret
              $log.warn "INVALID UNKNOWN KEY: SHOULD NOT COME HERE getchar():#{@stack}" 
            end
          end
          # possibly a 49 left over from M3-1
          unless @stack.empty?
            if @stack.size == 1
              @stack.clear
              return sf
            end
            $log.warn "something on stack getchar(): #{@stack} "
          end
          # comemnt after testing keys since this will be called a lot, even stack.clear is called a lot
          $log.warn "ERROR CLEARING STACK WITH STUFF ON IT getchar():#{@stack}"  if ($log.debug? && !@stack.empty?)
          @stack.clear
          next
        end #  -1
        # this is the ALT combination
        if @stack.first == 27
          # experimental. 2 escapes in quick succession to make exit faster
          if @stack.size == 1 && ch == 27
            @stack.clear
            return 2727 if $esc_esc # this is double-esc if you wanna trap it, trying out
            return 27
          end
          # possible F1..F3 on xterm-color
          if ch == 79 || ch == 91
            #$log.debug " got 27, #{ch}, waiting for one more"
            @stack << ch
            next
          end
          #$log.debug "stack SIZE  #{@stack.size}, #{@stack.inspect}, ch: #{ch}"
          if @stack == [27,79]
            # xterm-color
            case ch
            when 80
              ch = FFI::NCurses::KEY_F1
            when 81
              ch = FFI::NCurses::KEY_F2
            when 82
              ch = FFI::NCurses::KEY_F3
            when 83
              ch = FFI::NCurses::KEY_F4
              #when 27 # another alt-char following Alt-Sh-O
            else
              ## iterm2 uses these for HOME END num keyboard keys
              @stack.clear
              #@stack << ch # earlier we pushed this but it could be of use
              #return 128 + 79
              return 128 + 79 + ch

            end
            @stack.clear
            return ch
          elsif @stack == [27, 91]
            # XXX 27, 91 also is Alt-[
            if ch == 90
              @stack.clear
              return KEY_BTAB # backtab
            elsif ch == 53 || ch == 50 || ch == 51
              # control left, right and shift function
              @stack << ch
              next
            elsif ch == 27 # another alt-char immediately after Alt-[
              $log.debug "getchar in 27, will return 128+91 " if $log.debug? 
              @stack.clear
              @stack << ch
              return 128 + 91
            else
              $log.debug "getchar in other, will return 128+91: #{ch} " if $log.debug? 
              # other cases Alt-[ followed by some char or key - merge with previous
              @stack.clear
              @stack << ch
              return 128 + 91
            end
          elsif @stack == [27, 91, 53]
            if ch == 68
              @stack.clear
              return C_LEFT  # control-left
            elsif ch == 67
              @stack.clear
              return C_RIGHT  # -control-rt
            end
          elsif @stack == [27, 91, 51]
            if ch == 49 && getch()== 126
              @stack.clear
              return 20009  # sh_f9
            end
          elsif @stack == [27, 91, 50]
            if ch == 50 && getch()== 126
              @stack.clear
              return 20010  # sh-F10
            end
            if ch == 57 && getch()== 126
              @stack.clear
              return 20008  # sh-F8
            elsif ch == 56 && getch()== 126
              @stack.clear
              return 20007  # sh-F7
            elsif ch == 54 && getch()== 126
              @stack.clear
              return 20006  # sh-F6
            elsif ch == 53 && getch()== 126
              @stack.clear
              return 20005  # sh-F5
            end
          end
          # the usual Meta combos. (alt) - this is screwing it up, just return it in some way
          ch = 128 + ch
          @stack.clear
          return ch
        end # stack.first == 27
        # append a 27 to stack, actually one can use a flag too
        if ch == 27
          @stack << 27
          next
        end
        return ch
      end # while
    end # def

    # doesn't seem to work, clears first line, not both
    def clear
      # return unless visible?
      move 0, 0
      puts *Array.new(height){ ' ' * (width - 1) }
    end

    # setup and reset

    ## allow user to send an array
    # I am tired of the hash layout (taken from Canis).
    def reset_layout(layout)
      case layout
      when Array
        $log.error  "NIL in window constructor" if layout.include? nil
        raise ArgumentError, "Nil in window constructor" if layout.include? nil
        @height, @width, @top, @left = *layout
        raise ArgumentError, "Nil in window constructor" if @top.nil? || @left.nil?

        @layout = { :height => @height, :width => @width, :top => @top, :left => @top }
      when Hash
        @layout = layout

        [:height, :width, :top, :left].each do |name|
          instance_variable_set("@#{name}", layout_value(name))
        end
      end
    end

    # removed ref to default_for since giving error in FFI 2011-09-8 
    def layout_value(name)
      value = @layout[name]
      default = default_for(name)

      value = value.call(default) if value.respond_to?(:call)
      return (value || default).to_i
    end

    # this gives error since stdscr is only a pointer at this time
    def default_for(name)
      case name
      when :height, :top
        #Ncurses.stdscr.getmaxy(stdscr)
        FFI::NCurses.LINES
      when :width, :left
        #Ncurses.stdscr.getmaxx(stdscr)
        FFI::NCurses.COLS
      else
        0
      end
    end

    # Ncurses panel

    def hide
      #return unless visible? # added 2011-10-14 these 2 are not behaving properly
      Ncurses::Panel.hide_panel @panel.pointer
      #Ncurses.refresh # wnoutrefresh
      Ncurses::Panel.update_panels # added so below window does not need to do this 2011-10-1 
      @visible = false
    end

    def show
      #return if visible? # added 2011-10-14 these 2 are not behaving properly
      Ncurses::Panel.show_panel @panel.pointer
      #Ncurses.refresh # wnoutrefresh
      Ncurses::Panel.update_panels # added so below window does not need to do this 2011-10-1 
      @visible = true
    end

    def on_top
      Ncurses::Panel.top_panel @panel.pointer
      wnoutrefresh
    end

    def visible?
      @visible
    end

    ##
    # destroy window, panel and any pads that were requested
    #
    def destroy
      # typically the ensure block should have this

      #$log.debug "win destroy start"

      Ncurses::Panel.del_panel(@panel.pointer) if @panel
      delwin() if @window 
      Ncurses::Panel.update_panels # added so below window does not need to do this 2011-10-1 

      # destroy any pads that were created by widgets using get_pad
      @pads.each { |pad|  
        FFI::NCurses.delwin(pad) if pad 
        pad = nil
      } if @pads
      #$log.debug "win destroy end"
    end

    # 
    # 2011-11-13 since 1.4.1
    # Widgets can get window to create a pad for them. This way when the window
    #  is destroyed, it will delete all the pads. A widget wold not be able to do this.
    # The destroy method of the widget will be called.
    def get_pad content_rows, content_cols
      pad = FFI::NCurses.newpad(content_rows, content_cols)
      @pads ||= []
      @pads << pad
      ## added 2013-03-05 - 19:21 without next line how was pad being returned
      return pad
    end

    #
    # Allows user to send data as normal string or chunks for printing
    # An array is assumed to be a chunk containing color and attrib info
    #
    def printstring_or_chunks(r,c,content, color, att = Ncurses::A_NORMAL)
      if content.is_a? String
        printstring(r,c,content, color, att)
      elsif content.is_a? Chunks::ChunkLine
        #$log.debug "XXX: using chunkline" # 2011-12-10 12:40:13
        wmove r, c
        a = get_attrib att
        # please add width to avoid overflow
        show_colored_chunks content, color, a
      elsif content.is_a? Array
        # several chunks in one row - NOTE Very experimental may change
        if content[0].is_a? Array
          $log.warn "XXX: WARNING outdated should send in a chunkline"
          wmove r, c
          a = get_attrib att
          # please add width to avoid overflow
          show_colored_chunks content, color, a
        else
          # a single row chunk - NOTE Very experimental may change
          text = content[1].dup
          printstring r, c, text, content[0] || color, content[2] || att
        end
      end
    end
    # 
    # prints a string formatted in our new experimental coloring format
    # taken from tmux. Currently, since i have chunks workings, i convert
    # to chunks and use the existing print function. This could change.
    # An example of a formatted string is:
    # s="#[fg=green]testing chunks #[fg=yellow, bg=red, bold]yellow #[reverse] reverseme \
    #  #[normal]normal#[bg = black]just yellow#[fg=blue],blue now #[underline] underlined text"
    # Ideally I should push and pop colors which the shell does not do with ansi terminal sequences. 
    # That way i can have a line in red,
    #  with some word in yellow, and then the line continues in red.
    #
    def printstring_formatted(r,c,content, color, att = Ncurses::A_NORMAL)
      att = get_attrib att unless att.is_a? Fixnum
      chunkline = convert_to_chunk(content, color, att)
      printstring_or_chunks r,c, chunkline, color, att
    end # print
    # 
    # print a formatted line right aligned
    # c (col) is ignored and calculated based on width and unformatted string length
    #
    def printstring_formatted_right(r,c,content, color, att = Ncurses::A_NORMAL)
      clean = content.gsub /#\[[^\]]*\]/,''  # clean out all markup
      #c = actual_width() - clean.length # actual width not working if resize
      c = getmaxx() - clean.length
      printstring_formatted(r,c,content, color, att )
    end

    private
    def get_default_color_parser
      require 'canis/core/util/colorparser'
      @color_parser || DefaultColorParser.new
    end
    # supply with a color parser, if you supplied formatted text
    public
    def color_parser f
      $log.debug "XXX:  color_parser setting in window to #{f} "
      if f == :tmux
        @color_parser = get_default_color_parser()
      else
        @color_parser = f
      end
    end
    #
    # Takes a formatted string and converts the parsed parts to chunks.
    #
    # @param [String] takes the entire line or string and breaks into an array of chunks
    # @yield chunk if block
    # @return [ChunkLine] # [Array] array of chunks
    # @since 1.4.1   2011-11-3 experimental, can change
    public
    def convert_to_chunk s, colorp=$datacolor, att=FFI::NCurses::A_NORMAL
      unless @color_parser
        @color_parser = get_default_color_parser()
        @converter = Chunks::ColorParser.new @color_parser
      end
      @converter.convert_to_chunk s, colorp, att
    end

    ## 
    # prints a string at row, col, with given color and attribute
    # added by rk 2008-11-29 19:01 
    # I usually use this, not the others ones here
    # @param  r - row
    # @param  c - col
    # @param string - text to print
    # @param color - color pair
    # @ param att - ncurses attribute: normal, bold, reverse, blink,
    # underline
    public
    def printstring(r,c,string, color, att = Ncurses::A_NORMAL)
      raise "Nil passed to peintstring row:#{r}, col:#{c}, #{color} " if r.nil? || c.nil? || color.nil?
      #raise "Zero or less passed to printstring row:#{r}, col:#{c} " if $log.debug? && (r <=0 || c <=0)
      prv_printstring(r,c,string, color, att )
    end

    ## name changed from printstring to prv_prinstring
    def prv_printstring(r,c,string, color, att = Ncurses::A_NORMAL)

      #$log.debug " #{@name} inside window printstring r #{r} c #{c} #{string} "
      if att.nil? 
        att = Ncurses::A_NORMAL
      else
        att = get_attrib att
      end

      wattron(Ncurses.COLOR_PAIR(color) | att)
      mvwprintw(r, c, "%s", :string, string);
      wattroff(Ncurses.COLOR_PAIR(color) | att)
    end
    ##
    # NOTE : FOR MESSAGEBOXES ONLY !!!! 
    def print_border_mb row, col, height, width, color, attr
      # the next is for xterm-256 
      att = get_attrib attr
      len = width
      len = Ncurses.COLS-0 if len == 0
      # print a bar across the screen 
      #attron(Ncurses.COLOR_PAIR(color) | att)
      # this works for newmessagebox but not for old one.
      # Even now in some cases some black shows through, if the widget is printing spaces
      # such as field or textview on a messagebox.
      (row-1).upto(row+height-1) do |r|
        mvwhline(r, col, 1, len)
      end
      #attroff(Ncurses.COLOR_PAIR(color) | att)

      mvwaddch row, col, Ncurses::ACS_ULCORNER
      mvwhline( row, col+1, Ncurses::ACS_HLINE, width-6)
      mvwaddch row, col+width-5, Ncurses::ACS_URCORNER
      mvwvline( row+1, col, Ncurses::ACS_VLINE, height-4)

      mvwaddch row+height-3, col, Ncurses::ACS_LLCORNER
      mvwhline(row+height-3, col+1, Ncurses::ACS_HLINE, width-6)
      mvwaddch row+height-3, col+width-5, Ncurses::ACS_LRCORNER
      mvwvline( row+1, col+width-5, Ncurses::ACS_VLINE, height-4)
    end
    ##
    # prints a border around a widget, CLEARING the area.
    #  If calling with a pad, you would typically use 0,0, h-1, w-1.
    def print_border row, col, height, width, color, att=Ncurses::A_NORMAL
      raise "height needs to be supplied." if height.nil?
      raise "width needs to be supplied." if width.nil?
      att ||= Ncurses::A_NORMAL

      #$log.debug " inside window print_border r #{row} c #{col} h #{height} w #{width} "

      # 2009-11-02 00:45 made att nil for blanking out
      # FIXME - in tabbedpanes this clears one previous line ??? XXX when using a textarea/view
      # when using a pad this calls pads printstring which again reduces top and left !!! 2010-01-26 23:53 
      ww=width-2
      (row+1).upto(row+height-1) do |r|
        prv_printstring( r, col+1," "*ww , color, att)
      end
      prv_print_border_only row, col, height, width, color, att
    end
    def print_border_only row, col, height, width, color, att=Ncurses::A_NORMAL
      prv_print_border_only row, col, height, width, color, att
    end


    ## print just the border, no cleanup
    #+ Earlier, we would clean up. Now in some cases, i'd like
    #+ to print border over what's been done. 
    # XXX this reduces 1 from width but not height !!! FIXME 
    def prv_print_border_only row, col, height, width, color, att=Ncurses::A_NORMAL
      if att.nil? 
        att = Ncurses::A_NORMAL
      else
        att = get_attrib att
      end
      wattron(Ncurses.COLOR_PAIR(color) | att)
      mvwaddch  row, col, Ncurses::ACS_ULCORNER
      mvwhline( row, col+1, Ncurses::ACS_HLINE, width-2)
      mvwaddch row, col+width-1, Ncurses::ACS_URCORNER
      mvwvline( row+1, col, Ncurses::ACS_VLINE, height-1)

      mvwaddch row+height-0, col, Ncurses::ACS_LLCORNER
      mvwhline(row+height-0, col+1, Ncurses::ACS_HLINE, width-2)
      mvwaddch row+height-0, col+width-1, Ncurses::ACS_LRCORNER
      mvwvline( row+1, col+width-1, Ncurses::ACS_VLINE, height-1)
      wattroff(Ncurses.COLOR_PAIR(color) | att)
    end
    # This used to return an Ncurses window object, and you could call methods on it
    # Now it returns a FFI::NCurses.window pointer which you cannot call methods on.
    # You have to pass it to FFI::NCurses.<method>
    def get_window; @window; end
    def to_s; @name || self; end
    # use in place of mvwhline if your widget could be using a pad or window
    def rb_mvwhline row, col, char, width
      mvwhline row, col, char, width
    end
    # use in place of mvwvline if your widget could be using a pad or window
    def rb_mvwvline row, col, char, width
      mvwvline row, col, char, width
    end
    # use in place of mvaddch if your widget could be using a pad or window
    def rb_mvaddch row, col, char
      mvaddch row, col, char
    end
    def close_command *args, &block
      @close_command ||= []
      @close_args ||= []
      @close_command << block
      @close_args << args
    end
    alias :command :close_command

    # set a single command to confirm whether window shoud close or not
    # Block should return true or false for closing or not
    def confirm_close_command *args, &block
      @confirm_close_command = block
      @confirm_close_args    = args
    end

    # need a way of lettign user decide whether he wishes to close 
    # in which case we return false. However, there could be several commands
    # mapped. how do we know which is the one that has this authority
    def fire_close_handler
      if @confirm_close_command
        comm = @confirm_close_command
        ret = comm.call(self, *@confirm_close_args) 
        return ret unless ret # only return if false returned
      end
      if @close_command
        @close_command.each_with_index do |comm, ix|
          comm.call(self, *@close_args[ix]) if comm
        end
      end
      @close_command = nil
      @close_args = nil
      return true
    end
    def create_default_key_reader
      @key_reader = DefaultKeyReader.new self
    end
  end # window

  # created on 2014-04-20 - 00:19 so that user can install own handler
  #
  #
  # A class that reads keys and handles function, shifted function, control, alt, and other
  # extended keys.
  # THis essentially consists of a method getchar which will be called by the application
  # to get keys in a loop. Application may also call getchar to get one key in some situations.
  #
  # Originally, rbcurse returned an int, but we are movign to a string, so that user can use the exact
  # control codes he gets on the terminal using C-v and map them here.
  #
  #
  class DefaultKeyReader # --- {{{
    def initialize win
      @window = win
      @stack = []
    end
    #  2011-09-23 @since 1.3.1
    # Added more combinations here. These 2 are just indicative
    SPECIAL_KEYS = {
      [27, 79, 50, 81]              => 20014, #  'F14',
      [27, 79, 50, 82]              => 20015 # 'F15',
    }

    # return an int for the key read. this is just a single int, and is not interpreted
    # for control or function keys. it also will return -1 when no action.
    # You may re-implenent it or call the original one.
    #
    def getch
      @window.getch
    end

    # This is directly called by the users program in a loop.
    #
    # returns control, alt, alt+ctrl, alt+control+shift, F1 .. etc
    # ALT combinations also send a 27 before the actual key
    # Please test with above combinations before using on your terminal
    # added by jkepler 2008-12-12 23:07 
    #  2011-09-23 Redone Control-left, right, and Shift-F5..F10.
    #  Checking for quick press of Alt-Sh-O followed by Alt or printable char
    #  Checking for quick press of Alt-[ followed by Alt or printable char
    #  I attempted keeping a hash of combination arrays but it fails in the above
    #  2 cases, so abandoned.
    def _getchar 
      while 1 
        ch = self.getch
        #$log.debug "window getchar() GOT: #{ch}" if ch != -1
        sf = @stack.first
        if ch == -1
          # the returns escape 27 if no key followed it, so its SLOW if you want only esc
          if @stack.first == 27
            #$log.debug " -1 stack sizze #{@stack.size}: #{@stack.inspect}, ch #{ch}"
            case @stack.size
            when 1
              @stack.clear
              return 27
            when 2 # basically a ALT-O, or alt-[ (79 or 91) this will be really slow since it waits for -1
              ch = 128 + @stack.last
              $log.warn "XXX: WARN  #{ch} CLEARING stack #{@stack} "
              @stack.clear
              return ch
            else
              # check up a hash of special keys
              ret = SPECIAL_KEYS(@stack)
              return ret if ret
              $log.warn "INVALID UNKNOWN KEY: SHOULD NOT COME HERE getchar():#{@stack}" 
            end
          end
          # possibly a 49 left over from M3-1
          unless @stack.empty?
            if @stack.size == 1
              @stack.clear
              return sf
            end
            $log.warn "something on stack getchar(): #{@stack} "
          end
          # comemnt after testing keys since this will be called a lot, even stack.clear is called a lot
          $log.warn "ERROR CLEARING STACK WITH STUFF ON IT getchar():#{@stack}"  if ($log.debug? && !@stack.empty?)
          @stack.clear
          next
        end #  -1
        # this is the ALT combination
        if @stack.first == 27
          # experimental. 2 escapes in quick succession to make exit faster
          if @stack.size == 1 && ch == 27
            @stack.clear
            return 2727 if $esc_esc # this is double-esc if you wanna trap it, trying out
            return 27
          end
          # possible F1..F3 on xterm-color
          if ch == 79 || ch == 91
            #$log.debug " got 27, #{ch}, waiting for one more"
            @stack << ch
            next
          end
          #$log.debug "stack SIZE  #{@stack.size}, #{@stack.inspect}, ch: #{ch}"
          if @stack == [27,79]
            # xterm-color
            case ch
            when 80
              ch = FFI::NCurses::KEY_F1
            when 81
              ch = FFI::NCurses::KEY_F2
            when 82
              ch = FFI::NCurses::KEY_F3
            when 83
              ch = FFI::NCurses::KEY_F4
              #when 27 # another alt-char following Alt-Sh-O
            else
              ## iterm2 uses these for HOME END num keyboard keys
              @stack.clear
              #@stack << ch # earlier we pushed this but it could be of use
              #return 128 + 79
              return 128 + 79 + ch

            end
            @stack.clear
            return ch
          elsif @stack == [27, 91]
            # XXX 27, 91 also is Alt-[
            if ch == 90
              @stack.clear
              return KEY_BTAB # backtab
            elsif ch == 53 || ch == 50 || ch == 51
              # control left, right and shift function
              @stack << ch
              next
            elsif ch == 27 # another alt-char immediately after Alt-[
              $log.debug "getchar in 27, will return 128+91 " if $log.debug? 
              @stack.clear
              @stack << ch
              return 128 + 91
            else
              $log.debug "getchar in other, will return 128+91: #{ch} " if $log.debug? 
              # other cases Alt-[ followed by some char or key - merge with previous
              @stack.clear
              @stack << ch
              return 128 + 91
            end
          elsif @stack == [27, 91, 53]
            if ch == 68
              @stack.clear
              return C_LEFT  # control-left
            elsif ch == 67
              @stack.clear
              return C_RIGHT  # -control-rt
            end
          elsif @stack == [27, 91, 51]
            if ch == 49 && getch()== 126
              @stack.clear
              return 20009  # sh_f9
            end
          elsif @stack == [27, 91, 50]
            if ch == 50 && getch()== 126
              @stack.clear
              return 20010  # sh-F10
            end
            if ch == 57 && getch()== 126
              @stack.clear
              return 20008  # sh-F8
            elsif ch == 56 && getch()== 126
              @stack.clear
              return 20007  # sh-F7
            elsif ch == 54 && getch()== 126
              @stack.clear
              return 20006  # sh-F6
            elsif ch == 53 && getch()== 126
              @stack.clear
              return 20005  # sh-F5
            end
          end
          # the usual Meta combos. (alt) - this is screwing it up, just return it in some way
          ch = 128 + ch
          @stack.clear
          return ch
        end # stack.first == 27
        # append a 27 to stack, actually one can use a flag too
        if ch == 27
          @stack << 27
          next
        end
        return ch
      end # while
    end # def

    # these should be read up from a file so program can update them for a user
    # These codes were required when we were using stdin outside of ncurses, but ncurses
    # gives us integer codes for these, and also deciphers function keys and arrow keys
    $kh=Hash.new
=begin
    $kh["OP"]="F1"
    $kh["[A"]="UP"
    $kh["[5~"]="PGUP"
    $kh['']="ESCAPE"
    KEY_PGDN="[6~"
    KEY_PGUP="[5~"
    ## I needed to replace the O with a [ for this to work
    #  in Vim Home comes as ^[OH whereas on the command line it is correct as ^[[H
    KEY_HOME='[H'
    KEY_END="[F"
    KEY_F1="OP"
    KEY_UP="[A"
    KEY_DOWN="[B"

    $kh[KEY_PGDN]="PgDn"
    $kh[KEY_PGUP]="PgUp"
    $kh[KEY_HOME]="Home"
    $kh[KEY_END]="End"
    $kh[KEY_F1]="F1"
    $kh[KEY_UP]="UP"
    $kh[KEY_DOWN]="DOWN"
    KEY_LEFT='[D' 
    KEY_RIGHT='[C' 
    $kh["OQ"]="F2"
    $kh["OR"]="F3"
    $kh["OS"]="F4"
    $kh[KEY_LEFT] = "LEFT"
    $kh[KEY_RIGHT]= "RIGHT"
    KEY_F5='[15~'
    KEY_F6='[17~'
    KEY_F7='[18~'
    KEY_F8='[19~'
    KEY_F9='[20~'
    KEY_F10='[21~'
    $kh[KEY_F5]="F5"
    $kh[KEY_F6]="F6"
    $kh[KEY_F7]="F7"
    $kh[KEY_F8]="F8"
    $kh[KEY_F9]="F9"
    $kh[KEY_F10]="F10"
=end
    # testing out shift+Function. these are the codes my kb generates
    KEY_S_F1='[1;2P'
    $kh[KEY_S_F1]="S-F1"
    $kh['[1;2Q']="S-F2"
    $kh['[1;2R']="S-F3"
    $kh['[1;2S']="S-F4"
    $kh['[15;2~']="S-F5"

    def getchar
      _getchar
    end
    # NOTE I cannot use this since we are not ready to take a string, that is a big decision that
    # requries a lot of work, and some decisions. We may bind using "<CR>" or "<C-d>" so 
    # maybe that's how we may need to send back
    ## get a character from user and return as a string
    # Adapted from:
    #http://stackoverflow.com/questions/174933/how-to-get-a-single-character-without-pressing-enter/8274275#8274275
    # Need to take complex keys and matc against a hash.
    # We cannot use the cetus example as is since here $stdin.ready? does not work and more importantly
    # we have keyboard set to true so function keys and arrow keys are not returned as multiple values but as 
    # one int in the 255 and above range. so that must be interpreted separately.
    #
    # If we wait for -1 then quick M-a can get concatenated. we need to take care
    # a ESC means the previous one should be evaluated and not contactenated
    def getchar_as_string
        c = nil
        while true
          c = self.getch
          break if c != -1
        end
    
        cn = c
        #return FFI::NCurses::keyname(c)  if [10,13,127,0,32,8].include? c
        return "ENTER" if cn == 10 || cn == 13
        return "BACKSPACE" if cn == 127
        return "C-SPACE" if cn == 0
        return "SPACE" if cn == 32
        # next does not seem to work, you need to bind C-i
        return "TAB" if cn == 8
        if cn >= 0 && cn < 27
          x= cn + 96
          return "C-#{x.chr}"
          #return FFI::NCurses::keyname(c)  # this gives result as "^C" 
        end
        
        # if escape then get into a loop and keep checking till -1 or another escape
        #
        if c == 27
          buff=c.chr
          # if there is another escape coming through then 2 keys were pressed so
          # evaluate upon hitting an escape
          # NOTE : i think only if ESc is followed by [ should be keep collectig
          # otherwise the next char should evaluate. cases like F1 are already being sent in as high integer codes
          while true
          
            k = self.getch

            if k == 27
              # seems like two Meta keys pressed in quick succession without chance for -1 to kick in
              # but this still does not catch meta char followed by single char. M-za 
              x = _evaluate_buff buff
              # return ESC so it can be interpreted again.
              @window.ungetch k
              return x if x
              $log.warn "getchar: window.rb 1200 Found no mapping for #{buff} "
              return buff # otherwise caught in loop ???
            elsif k > -1
              buff += k.chr
              # this is an alt/meta code. All other complex codes seem to have a [ after the escape
              # so we will keep accumulating them.
              # NOTE this still means that user can press Alt-[ and some letter in quick succession
              # and it will accumulate rather than be interpreted as M-[.
              #
              if buff.length == 2 and k.chr != '['
                x = _evaluate_buff buff
                return x if x
              end
              #$log.debug "XXX:  getchar adding #{k}, #{k.chr} to buff #{buff} "
            else
              # it is -1 so evaluate
              x = _evaluate_buff buff
              return x if x
              return buff
            end
          end
        end
        
        # what if keyname does not return anything
        if c > 127
          #$log.info "xxxgetchar: window.rb sending #{c} "
          ch =  FFI::NCurses::keyname(c) 
          # remove those ugly brackets around function keys
          if ch && ch[-1]==')'
            ch = ch.gsub(/[()]/,'')
          end
          return ch if ch
          $log.warn "getchar: window.rb 1234 Found no mapping for #{c} "
          return c
        end
        return c.chr if c
    end

    # check buffer if some key mapped in global kh for this
    # Otherwise if it is 2 keys then it is a Meta key
    # Can return nil if no mapping
    private
    def _evaluate_buff buff
      x=$kh[buff]
      return x if x
      #$log.debug "XXX:  getchar returning with  #{buff}"
      if buff.size == 2
        ## possibly a meta/alt char
        k = buff[-1]
        return "M-#{k.chr}"
      end
    end

  end # class DefaultKeyReader -- }}}

end
