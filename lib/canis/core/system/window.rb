# ----------------------------------------------------------------------------- #
#         File: window.rb
#  Description: A wrapper over window
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: Around for a long time
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-05-20 20:53
#
#  == CHANGED
#     removed dead or redudant code - 2014-04-22 - 12:53 
#     - replaced getchar with new simpler one - 2014-05-04
#     - introduced key_tos to replace keycode_tos, moved to Util in rwidget.rb
#     - reintroduced nedelay and reduced escdelay
#
# == TODO
#    strip and remove cruft. Several methods marked as deprecated.
# ----------------------------------------------------------------------------- #
#
require 'canis/core/system/ncurses'
require 'canis/core/system/panel'
#require 'canis/core/include/chunk'
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
# This class is to be extended so that it can be called by anyone wanting to implement
# chunks ot text with color and attributes. Chunkline consists of multiple chunks of colored text
# and should implement a +each_with_color+.
# The purpose of adding this is so that +chunk.rb+ does not need to be required if colored text
# is not being used by an application.
class AbstractChunkLine; end

module Canis
  class Window 
    attr_reader :width, :height, :top, :left
    attr_accessor :layout # hash containing hwtl
    attr_reader   :panel   # reader requires so he can del it in end
    attr_reader   :window_type   # window or pad to distinguish 2009-11-02 23:11 
    attr_accessor :name  # more for debugging log files. 2010-02-02 19:58 
    #attr_accessor :modified # has it been modified and may need a refresh 2014-04-22 - 10:23 CLEANUP
    # for root windows we need to know the form so we can ask it to update when
    #   there are overlapping windows.
    attr_accessor :form

    # creation and layout related {{{
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
      set_layout(layout)

      #$log.debug "XXX:WINDOW got h #{@height}, w #{@width}, t #{@top}, l #{@left} "

      @height = FFI::NCurses.LINES if @height == 0   # 2011-11-14 added since tired of checking for zero
      @width = FFI::NCurses.COLS   if @width == 0

      @window = FFI::NCurses.newwin(@height, @width, @top, @left) # added FFI 2011-09-6 
      # trying out refreshing underlying window.
      $global_windows ||= []
      # this causes issues padrefresh failing when display_list does a resize.
      #$global_windows << self
      @panel = Ncurses::Panel.new(@window) # added FFI 2011-09-6 
      #$error_message_row = $status_message_row = Ncurses.LINES-1
      $error_message_row ||= Ncurses.LINES-1
      $error_message_col ||= 1 # ask (bottomline) uses 0 as default so you can have mismatch. XXX
      $status_message ||= Canis::Variable.new # in case not an App

      # 2014-05-07 - 12:29 CANIS earlier this was called $key_map but that suggests a map.
      $key_map_type ||= :vim
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
      #FFI::NCurses::nodelay(@window, bf = true)
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
      @window.name = "Window::ROOTW:#{$global_windows.count}"
      @window.wrefresh
      Ncurses::Panel.update_panels
      # earlier we only put root window, now we may need to do all (bline - numbered menu - alert)
      $global_windows << @window unless $global_windows.include? @window
      return @window
    end

    # This refreshes the root window whenever overlapping windows are 
    # destroyed or moved.
    # This works by asking the root window's form to repaint all its objects.
    # This is now being called whenever a window is destroyed (and also resized). 
    # However, it must
    # manually be called if you move a window.
    # NOTE : if there are too many root windows, this could get expensive since we are updating all.
    # We may need to have a way to specify which window to repaint.
    #  If there are non-root windows above, we may have manually refresh only the previous one.
    #
    def self.refresh_all
      #Ncurses.touchwin(FFI::NCurses.stdscr)
      # above blanks out entire screen
      # in case of multiple root windows lets just do last otherwise too much refreshing.
      return unless $global_windows.last
      wins = [ $global_windows.last ]
      wins.each_with_index do |w,i|
        $log.debug " REFRESH_ALL on #{w.name} (#{i}) sending 1000"
        # NOTE 2014-05-01 - 20:25 although we have reached the root window from any level
        #  however, this is sending the hack to whoever is trapping the key, which in our current
        #  case happends to be Viewer, *not* the root form. We need to send to root form.
        f = w.form
        if f
          # send hack to root windows form if passed. 
          f.handle_key 1000
        end
        #w.ungetch(1000)
      # below blanks out entire screen too
        #FFI::NCurses.touchwin(w.get_window)
        #$log.debug "XXX:  refreshall diong window "
        #w.hide
        #w.show
        #Ncurses.refresh
        #w.wrefresh 
      end
      #Ncurses::Panel.update_panels
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
      set_layout(layout)
      wresize(height, width)
      mvwin(top, left)
      Window.refresh_all
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
    
    ## 
    # Creating variables case of array, we still create the hash
    # @param array or hash containing h w t and l
    def set_layout(layout)
      case layout
      when Array
        $log.error  "NIL in window constructor" if layout.include? nil
        raise ArgumentError, "Nil in window constructor" if layout.include? nil
        # NOTE this is just setting, and not replacing zero with max values
        @height, @width, @top, @left = *layout
        raise ArgumentError, "Nil in window constructor" if @top.nil? || @left.nil?

        @layout = { :height => @height, :width => @width, :top => @top, :left => @left }
      when Hash
        @layout = layout

        [:height, :width, :top, :left].each do |name|
          instance_variable_set("@#{name}", @layout[name])
        end
      end
    end
    # --- layout and creation related }}}

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
      raise "dead code ??"
      return y, x
    end

    def y
      raise "dead code ??"
      Ncurses.getcury(@window)
    end

    def x
      raise "dead code ??"
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

    #--
    # removing some methods that not used or used once
    # leaving here so we not what to do to print in these cases 
    def print(string, width = width)
      w = width == 0? Ncurses.COLS : width
      waddnstr(string.to_s, w) # changed 2011 dts  
    end

    #def print_yx(string, y = 0, x = 0)
      #w = width == 0? Ncurses.COLS : width
      #mvwaddnstr(y, x, string, w) # changed 2011 dts  
    #end
    #++

    # dead code ??? --- {{{
    # NOTE: many of these methods using width will not work since root windows width 
    #  is 0
    def print_empty_line
      raise "print empty is working"
      return unless visible?
      w = getmaxx == 0? Ncurses.COLS : getmaxx
      printw(' ' * w)
    end

    def print_line(string)
      raise "print line is working"
      w = getmaxx == 0? Ncurses.COLS : getmaxx
      print(string.ljust(w))
    end

    

    def puts(*strings)
      raise "puts is working, remove this"
      print(strings.join("\n") << "\n")
    end

    def _refresh
      raise "dead code remove"
      return unless visible?
      @window.refresh
    end

    def wnoutrefresh
      #raise "dead code ???"
      return unless visible?
      # next line gives error XXX DEAD
      @window.wnoutrefresh
    end

    def color=(color)
      raise "dead code ???"
      @color = color
      @window.color_set(color, nil)
    end

    def highlight_line(color, y, x, max)
      raise "dead code"
      @window.mvchgat(y, x, max, Ncurses::A_NORMAL, color, nil)
    end
    # doesn't seem to work, clears first line, not both
    def clear
      # return unless visible?
      raise "dead code ??"
      move 0, 0
      puts *Array.new(height){ ' ' * (width - 1) }
    end

    def on_top
      raise "on_top used, remove this line dead code"
      Ncurses::Panel.top_panel @panel.pointer
      wnoutrefresh
    end
    # --- dead code ??? }}}

    # return the character to the keyboard buffer to be read again.
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
    # ORIGINALLY After esc there was a timeout, but after others there was notimeout, so it would wait
    # indefinitely for a key
    # NOTE : caller may set a timeout prior to calling, but not change setting after since this method
    # maintains the default state in +ensure+. e.g. +widget.rb+ does a blocking get in +_process_key+
    # Curses sets a timeout when ESCAPE is pressed, it is called ESCDELAY and is 1000 milliseconds.
    # You may reduce it if you are not on some old slow telnet session. This returns faster from an esc
    # although there are still some issues. ESC-ESC becomes an issue, but if i press ESC-ESC-1 then esc-esc comes
    # together. otherwise there is a -1 between each esc.
    #
    def getch
      #c = @window.getch
      #FFI::NCurses::nodelay(@window, true)
      #FFI::NCurses::wtimeout(@window, 0)
      #$log.debug " #{Time.now.to_f} inside MAIN before getch " 
      c = FFI::NCurses.wgetch(@window)
      # the only reason i am doing this is so ESC can be returned if no key is pressed
      # after that, not sure how this effects everything. most likely I should just
      # go back to using a wtimeout, and not worry about resize requiring a keystroke
      if c == 27
        $escstart = Time.now.to_f
        # if ESC pressed don't wait too long for next key
        Ncurses::wtimeout(@window, $ncurses_timeout || 500) # will wait n millisecond on wgetch so that we can return if no
      else
        FFI::NCurses.set_escdelay(100)
        # this means keep waiting for a key.
        Ncurses::nowtimeout(@window, true)
      end
      c

    rescue SystemExit, Interrupt 
      #FFI::NCurses.flushinp
      3 # is C-c
    rescue StandardError
      -1 # is C-c
    ensure
      # whatever the default is, is to be set here in case caller changed it.
      #FFI::NCurses::nodelay(@window, true)
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


    # setup and reset



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


    def visible?
      @visible
    end

    ##
    # destroy window, panel and any pads that were requested
    #
    def destroy
      # typically the ensure block should have this

      #$log.debug "win destroy start"

      $global_windows.delete self
      Ncurses::Panel.del_panel(@panel.pointer) if @panel
      delwin() if @window 
      Ncurses::Panel.update_panels # added so below window does not need to do this 2011-10-1 

      # destroy any pads that were created by widgets using get_pad
      @pads.each { |pad|  
        FFI::NCurses.delwin(pad) if pad 
        pad = nil
      } if @pads
      # added here to hopefully take care of this issue once and for all. 
      # Whenever any window is destroyed, the root window is repainted.
      #
      Window.refresh_all
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

    # print and chunk related --- {{{
    #
    # Allows user to send data as normal string or chunks for printing
    # An array is assumed to be a chunk containing color and attrib info
    #
    def printstring_or_chunks(r,c,content, color, att = Ncurses::A_NORMAL)
      if content.is_a? String
        printstring(r,c,content, color, att)
      elsif content.is_a? AbstractChunkLine
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
      require 'canis/core/include/chunk'
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
    public
    def convert_to_chunk s, colorp=$datacolor, att=FFI::NCurses::A_NORMAL
      unless @color_parser
        require 'canis/core/include/chunk'
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
    # prints the border for message boxes
    #
    # NOTE : FOR MESSAGEBOXES ONLY !!!!  Then why not move to messagebox FIXME
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
    #  FIXME can this be moved to module Bordertitle ?
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
        printstring( r, col+1," "*ww , color, att)
      end
      print_border_only row, col, height, width, color, att
    end


    ## print just the border, no cleanup
    #+ Earlier, we would clean up. Now in some cases, i'd like
    #+ to print border over what's been done. 
    # XXX this reduces 1 from width but not height !!! FIXME 
    #  FIXME can this be moved to module Bordertitle ?
    def print_border_only row, col, height, width, color, att=Ncurses::A_NORMAL
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

    #  Previously this printed a chunk as a full line, I've modified it to print on 
    #  one line. This can be used for running text. 
    #  NOTE 2013-03-08 - 17:02 added width so we don't overflow
    #  NOTE 2014-05-11 - textpad has its own version, so does not call this.
    def show_colored_chunks(chunks, defcolor = nil, defattr = nil, wid = 999, pcol = 0)
      return unless visible?
      ww = 0
      chunks.each_with_color do |text, color, attrib|

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

        color ||= defcolor
        attrib ||= defattr

        cc, bg = ColorMap.get_colors_for_pair color
        #$log.debug "XXX: CHUNK window #{text}, cp #{color} ,  attrib #{attrib}. #{cc}, #{bg} " 
        color_set(color,nil) if color
        wattron(attrib) if attrib
        #print(text)
        waddnstr(text.to_s, @width) # changed 2014-04-22 - 11:59  to reduce a function
        wattroff(attrib) if attrib
      end
    end
    # ----- }}}

    # This used to return an Ncurses window object, and you could call methods on it
    # Now it returns a FFI::NCurses.window pointer which you cannot call methods on.
    # You have to pass it to FFI::NCurses.<method>
    def get_window; @window; end

    # returns name of window or self (mostly for debugging)
    def to_s; @name || self; end

    # actions to perform when window closed.
    # == Example
    #    @window.close_command do
    #       if confirm("Save tasks?", :default_button => 0)
    #           take some actions
    #        end
    #    end
    def close_command *args, &block
      @close_command ||= []
      @close_args ||= []
      @close_command << block
      @close_args << args
    end
    alias :command :close_command

    # set a single command to confirm whether window shoud close or not
    # Block should return true or false for closing or not
    # == Examples
    #
    #    @window.confirm_close_command do
    #       confirm "Sure you wanna quit?", :default_button => 1
    #    end
    #
    def confirm_close_command *args, &block
      @confirm_close_command = block
      @confirm_close_args    = args
    end

    # Called when window close is requested by user. 
    # Executes confirm_close block and if it succeeds then executes close commands
    # called by util/app.rb
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

    # creates a key reader unless overridden by application which should be rare.
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

    # return an int for the key read. this is just a single int, and is not interpreted
    # for control or function keys. it also will return -1 when no action.
    # You may re-implenent it or call the original one.
    #
    def getch
      @window.getch
    end


    # A map of int keycodes associated with a string name which is defined in $kh
    $kh_int ||= Hash.new {|hash, key| hash[key] = key.hash }
    # these 4 for xterm-color which does not send 265 on F1
    $kh_int["F1"] = 265
    $kh_int["F2"] = 266
    $kh_int["F3"] = 267
    $kh_int["F4"] = 268
    # testing out shift+Function. these are the codes my kb generates
    if File.exists? File.expand_path("~/ncurses-keys.yml")
      # a sample of this file should be available with this 
      # the file is a hash or mapping, but should not contrain control characters.
      # Usually delete the control character and insert a "\e" in its place.
      # "\e[1;3C": C-RIGHT
      require 'yaml'
      $kh = YAML::load( File.open( File.expand_path("~/ncurses-keys.yml" ) ))
    else
      # if we could not find any mappings then use some dummy ones that work on my laptop.
      $kh=Hash.new
      KEY_S_F1='[1;2P'
      $kh[KEY_S_F1]="S-F1"
      $kh['[1;2Q']="S-F2"
      $kh['[1;2R']="S-F3"
      $kh['[1;2S']="S-F4"
      $kh['[15;2~']="S-F5"

    end
    # this is for xterm-color which does not send 265 on F1
      $kh['OP']="F1"
      $kh['OQ']="F2"
      $kh['OR']="F3"
      $kh['OS']="F4"
    
    # NOTE: This is a reworked and much simpler version of the original getchar which was taken from manveru's 
    # codebase. This also currently returns the keycode as int while placing the char version in a 
    # global $key_chr. Until we are ready to return a char, we use this.
    #
    # FIXME : I have tried very hard to revert to nodelay but it does not seem to have an effect when ESC is pressed.
    # Somewhere, there is a delay when ESC is pressed. I not longer wish to provide the feature of pressing ESC
    # and then a key to be evaluated as Meta-key. This slows down when a user just presses ESC.
    #
    # Read a char from the window (from user) and returns int code.
    # In some cases, such as codes entered in the $kh hash, we do not yet have a keycode defined
    # so we return 9999 and the user can access $key_chr.
    #
    # NOTE: Do not convert to string, that is doing two things. Allow user to convert if required using 
    # `key_tos`
    def getchar
      $key_chr = nil
        c = nil
        while true
          c = self.getch
          break if c != -1
        end
    
        cn = c
        $key_int = c
        # handle control codes 0 to 127 but not escape
        if cn >= 0 && cn < 128 && cn != 27
          #$key_chr = key_tos(c)
          return c
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
            #$log.debug " #{Time.now.to_f} inside LOOP before getch "
            # This getch seems to take enough time not to return a -1 for almost a second
            # even if nodelay is true ??? XXX
            FFI::NCurses.set_escdelay(5)
            k = self.getch
            #$log.debug "elapsed #{elapsed} millis  inside LOOP AFTER getch #{k} (#{elapsed1})"
            $log.debug "inside LOOP AFTER getch #{k} "

            if k == 27
              # seems like two Meta keys pressed in quick succession without chance for -1 to kick in
              # but this still does not catch meta char followed by single char. M-za , it does.
              if $esc_esc
                if buff == 27.chr
                  $key_chr = "<ESC-ESC>"
                  return 2727
                else
                  alert "buff is #{buff}"
                end
              end
              $log.debug "  1251 before evaluate "
              x = _evaluate_buff buff
              # return ESC so it can be interpreted again.
              @window.ungetch k
              $key_chr = x if x
              return $key_int if x
              $log.warn "getchar: window.rb 1200 Found no mapping for #{buff} "
              $key_chr = buff
              return $key_int
              #return buff # otherwise caught in loop ???
            elsif k > -1
              # FIXME next lne crashes if M-C-h pressed which gives 263
              if k > 255
                $log.warn "getchar: window.rb 1247 Found no mapping for #{buff} #{k} "
                $key_int = k + 128
                return $key_int
                # this contains ESc followed by a high number
=begin
                ka = key_tos(k)
                if ka
                  $key_chr = "<M-" + ka[1..-1]
                  $key_int = k + 128
                  return $key_int
                else
                  $key_chr = "UNKNOWN: Meta + #{k}"
                  return 9999
                end
=end
              end

              buff += k.chr
              # this is an alt/meta code. All other complex codes seem to have a [ after the escape
              # so we will keep accumulating them.
              # NOTE this still means that user can press Alt-[ and some letter in quick succession
              # and it will accumulate rather than be interpreted as M-[.
              #
              if buff.length == 2 and k == 79
                # this is Alt-O and can be a F key in some terms like xterm-color
              elsif buff.length == 2 and k.chr != '['
                x = _evaluate_buff buff
        
                $key_chr = x
                return $key_int if x
              end
              #$log.debug "XXX:  getchar adding #{k}, #{k.chr} to buff #{buff} "
            else
              #$log.debug "  GOT -1 in escape "
              # it is -1 so evaluate
              x = _evaluate_buff buff
              $key_chr = x if x
              return $key_int if x
              $log.warn "getchar: window.rb 1256 Found no mapping for #{buff} "
              $key_chr = buff
              return $key_int
            end
          end
        end
        
        # what if keyname does not return anything
        if c > 127
          #$log.info "xxxgetchar: window.rb sending #{c} "
=begin
          ch =  FFI::NCurses::keyname(c) 
          # remove those ugly brackets around function keys
          if ch && ch[-1]==')'
            ch = ch.gsub(/[()]/,'')
          end
          if ch && ch.index("KEY_")
            ch = ch.gsub(/KEY_/,'')
          end
          ch = "<#{ch}>" if ch
          #return ch if ch
          $key_chr = ch if ch
          $key_chr = "UNKNOWN:#{c}" unless ch
          $log.warn "getchar: window.rb 1234 Found no mapping for #{c} " unless ch
=end
          #$key_chr = key_tos(ch)
          return c
        end
        if c
          #$key_chr =  c.chr 
          return c 
        end
    end


    def getchar_as_char
      $key_int = getchar
      $key_chr = key_tos( $key_int )
      return $key_chr
    end


=begin
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
    # FIXME = ESCESC 2727 - can't do this as will clash with Esc, M-(n).
    # this is a rework of the above but returns an int so that the existing programs can keep working.
    # We will store the char codes/ in a global string so user can get esp if unknown.
    # UNUSED since we are still using int codes.
    def getchar_as_char # -- {{{
        c = nil
        while true
          c = self.getch
          break if c != -1
        end
    
        cn = c
        #return FFI::NCurses::keyname(c)  if [10,13,127,0,32,8].include? c
        $key_int = c
        if cn >= 0 && cn < 128 && cn != 27
          $key_chr = key_tos(c)
          return $key_chr
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
    end # -- }}}
=end

    # Generate and return an int for a newkey which user has specified in yml file.
    # We use hash, which won't allow me to derive key string 
    # in case loop user can do:
    #    when KEY_ENTER
    #    when 32
    #    when $kh_int["S-F2"]
    def _get_int_for_newkey x
      # FIXME put the declaration somewhere else maybe in window cons ???
      y = $kh_int[x]
      # when i give user the hash, he can get the string back ???
      $kh_int[y] = x unless $kh_int.key? y
      return y
    end
    # check buffer if some key mapped in global kh for this
    # Otherwise if it is 2 keys then it is a Meta key
    # Can return nil if no mapping
    # @return [String] string code for key (since it is mostly from $kh. Also sets, $key_int
    private
    def _evaluate_buff buff
      if buff == 27.chr
        $key_int = 27
        #$escend = Time.now.to_f
        #elapsed = ($escend - $escstart)*1000
        #$log.debug " #{elapsed} evaluated to ESC"
        $key_chr = "<ESC>"
        return $key_chr
      end
      x=$kh[buff]
      if x
        $key_int = 9999
        $key_int = _get_int_for_newkey(x)
        $key_cache[$key_int] = x unless $key_cache.key? $key_int
        # FIXME currently 9999 signifies unknown key, but since this is derived from a user list
        #   we could have some dummy number being passed or set by user too.
        return "<#{x}>"
      end
      #$log.debug "XXX:  getchar returning with  #{buff}"
      if buff.size == 2
        ## possibly a meta/alt char
        k = buff[-1]
        $key_int = 128 + k.ord
        return key_tos( $key_int )
      end
      $key_int = 99999
      nil
    end

  end # class DefaultKeyReader -- }}}

end
