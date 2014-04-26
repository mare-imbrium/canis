=begin
  * Name: rcommandwindow: pops up a status message at bottom of screen
          creating a new window, so we don't have to worry about having window
          handle.

  * Description   
  * Author: jkepler (ABCD)
  * Date: 2008-11-19 12:49 
  * License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
  * file separated on 2009-01-13 22:39 

  == Changes
 Have removed a lot of stuff that was either a duplication of other stuff, or that was not really
 adding any value. 
 
== Issues

   Only display_menu is of any use, and can be taken out and placed in some util or extra.
   It is called by numbered_menu which can be retained.
   display_menu is used by Promptmenu too.

=end
require 'canis'

module Canis
  ##
  #  Creates a window at the bottom of the screen for some operations.
  #  Used for some operations such as:
  #    - display a menu
  #    - display some interactive text
  #    - display some text 
  #
  class CommandWindow
    include Canis::Utils
    dsl_accessor :box
    dsl_accessor :title
    attr_reader :config
    attr_reader :layout
    attr_reader :window     # required for keyboard or printing
    dsl_accessor :height, :width, :top, :left  #  2009-01-06 00:05 after removing meth missing

    def initialize form=nil, aconfig={}, &block  # --- {{{
      @config = aconfig
      @config.each_pair { |k,v| instance_variable_set("@#{k}",v) }
      instance_eval &block if block_given?
      if @layout.nil? 
          set_layout(1,Ncurses.COLS, -1, 0) 
      end
      @height = @layout[:height]
      @width = @layout[:width]
      @window = Canis::Window.new(@layout)
      @start = 0 # row for display of text with paging
      @list = []
      if @box == :border
        @window.box 0,0
      elsif @box
        @window.attron(Ncurses.COLOR_PAIR($normalcolor) | Ncurses::A_REVERSE)
        @window.mvhline 0,0,1,@width
        @window.printstring 0,0,@title, $normalcolor #, 'normal' if @title
        @window.attroff(Ncurses.COLOR_PAIR($normalcolor) | Ncurses::A_REVERSE)
      else
        #@window.printstring 0,0,@title, $normalcolor,  'reverse' if @title
        title @title
      end
      @window.wrefresh
      @panel = @window.panel
      Ncurses::Panel.update_panels
      @window.wrefresh
      @row_offset = 0
      if @box
        @row_offset = 1
      end
    end  # --- }}}

    # not sure if this is really required. print_string is just fine.
    # print a string.
    # config can be :x :y :color_pair
    def print_str text, config={}
      win = config.fetch(:window, @window) # assuming its in App
      x = config.fetch :x, 0 
      y = config.fetch :y, 0
      color = config[:color_pair] || $datacolor
      raise "no window for ask print in #{self.class} name: #{name} " unless win
      color=Ncurses.COLOR_PAIR(color);
      win.attron(color);
      win.mvprintw(x, y, "%s" % text);
      win.attroff(color);
      win.refresh # FFI NW 2011-09-9  , added back gets overwritten
    end



    # ---- windowing functions {{{
    ##
    ## message box
    def stopping?
      @stop
    end

    # todo handle mappings, so user can map keys TODO
    def handle_keys
      begin
        while((ch = @window.getchar()) != 999 )
          case ch
          when -1
            next
          else
            press ch
            break if @stop
            yield ch if block_given?
          end
        end
      ensure
        destroy  
      end
      return #@selected_index
    end

    # handles a key, commandline
    def press ch 
      ch = ch.getbyte(0) if ch.class==String ## 1.9
      $log.debug " XXX press #{ch} " if $log.debug? 
      case ch
      when -1
        return
      when KEY_F1, 27, ?\C-q.getbyte(0)   
        @stop = true
        return
      when KEY_ENTER, 10, 13
        #$log.debug "popup ENTER : #{@selected_index} "
        #$log.debug "popup ENTER :  #{field.name}" if !field.nil?
        @stop = true
        return
      when ?\C-d.getbyte(0)
        @start += @height-1
        bounds_check
      when KEY_UP
        @start -= 1
        @start = 0 if @start < 0
      when KEY_DOWN
        @start += 1
        bounds_check
      when ?\C-b.getbyte(0)
        @start -= @height-1
        @start = 0 if @start < 0
      when 0
        @start = 0
      end
      Ncurses::Panel.update_panels();
      Ncurses.doupdate();
      @window.wrefresh
    end
    # might as well add more keys for paging.
    def configure(*val , &block)
      case val.size
      when 1
        return @config[val[0]]
      when 2
        @config[val[0]] = val[1]
        instance_variable_set("@#{val[0]}", val[1]) 
      end
      instance_eval &block if block_given?
    end
    def cget param
      @config[param]
    end

    def set_layout(height=0, width=0, top=0, left=0)
      # negative means top should be n rows from last line. -1 is last line
      if top < 0
        top = Ncurses.LINES-top
      end
      @layout = { :height => height, :width => width, :top => top, :left => left } 
      @height = height
      @width = width
    end
    def destroy
      $log.debug "DESTROY : rcommandwindow"
      if @window
        begin
          panel = @window.panel
          Ncurses::Panel.del_panel(panel.pointer) if panel
          @window.delwin
        rescue => exc
        end
      end
    end
    # refresh whatevers painted onto the window
    def refresh
      Ncurses::Panel.update_panels();
      Ncurses.doupdate();
      @window.wrefresh
    end
    # clears the window, leaving the title line as is, from row 1 onwards
    def clear
      @window.wmove 1,1
      @window.wclrtobot
      @window.box 0,0 if @box == :border
      # lower line of border will get erased currently since we are writing to 
      # last line FIXME
    end
    # ---- windowing functions }}}

    # modify the window title, or get it if no params passed.
    def title t=nil  # --- {{{
      return @title unless t
      @title = t
      @window.printstring 0,0,@title, $normalcolor,  'reverse' if @title
    end  # --- }}}

    #
    # Displays list in a window at bottom of screen, if large then 2 or 3 columns.
    # @param [Array] list of string to be displayed
    # @param [Hash]  configuration options: indexing and indexcolor
    # indexing - can be letter or number. Anything else will be ignored, however
    #  it will result in first letter being highlighted in indexcolor
    # indexcolor - color of mnemonic, default green
    def display_menu list, options={}  # --- {{{
      indexing = options[:indexing]
      indexcolor = options[:indexcolor] || get_color($normalcolor, :yellow, :black)
      indexatt = Ncurses::A_BOLD
      #
      # the index to start from (used when scrolling a long menu such as file list)
      startindex = options[:startindex] || 0

      max_cols = 3 #  maximum no of columns, we will reduce based on data size
      l_succ = "`"
      act_height = @height
      if @box
        act_height = @height - 2
      end
      lh = list.size
      if lh < act_height
        $log.debug "DDD inside one window" if $log.debug? 
        list.each_with_index { |e, i| 
          text = e
          case e
          when Array
            text = e.first + " ..."
          end
          if indexing == :number
            mnem = i+1
            text = "%d. %s" % [i+1, text] 
          elsif indexing == :letter
            mnem = l_succ.succ!
            text = "%s. %s" % [mnem, text] 
          end
          @window.printstring i+@row_offset, 1, text, $normalcolor  
          if indexing
            @window.mvchgat(y=i+@row_offset, x=1, max=1, indexatt, indexcolor, nil)
          end
        }
      else
        $log.debug "DDD inside two window" if $log.debug? 
        row = 0
        h = act_height
        cols = (lh*1.0 / h).ceil
        cols = max_cols if cols > max_cols
        # sometimes elements are large like directory paths, so check size
        datasize = list.first.length
        if datasize > @width/3 # keep safety margin since checking only first row
          cols = 1
        elsif datasize > @width/2
          cols = [2,cols].min
        end
        adv = (@width/cols).to_i
        colct = 0
        col = 1
        $log.debug "DDDcols #{cols}, adv #{adv} size: #{lh} h: #{act_height} w #{@width} " if $log.debug? 
        list.each_with_index { |e, i| 
          text = e
          # signify that there's a deeper level
          case e
          when Array
            text = e.first + "..."
          end
          if indexing == :number
            mnem = i+1
            text = "%d. %s" % [mnem, text] 
          elsif indexing == :letter
            mnem = l_succ.succ!
            text = "%s. %s" % [mnem, text] 
          end
          # print only within range and window height
          #if i >= startindex && row < @window.actual_height
          if i >= startindex && row < @window.height
            $log.debug "XXX: MENU #{i} > #{startindex} row #{row} col #{col} "
            @window.printstring row+@row_offset, col, text, $normalcolor  
            if indexing
              @window.mvchgat(y=row+@row_offset, x=col, max=1, indexatt, indexcolor, nil)
            end
          colct += 1
          if colct == cols
            col = 1
            row += 1
            colct = 0
          else
            col += adv
          end
          end # startindex
        }
      end
      Ncurses::Panel.update_panels();
      Ncurses.doupdate();
      @window.wrefresh
    end # --- }}}


  end # class CommandWindow

  # presents given list in numbered format in a window above last line
  # and accepts input on last line
  # The list is a list of strings. e.g.
  #      %w{ ruby perl python haskell }
  # Multiple levels can be given as:
  #      list = %w{ ruby perl python haskell }
  #      list[0] = %w{ ruby ruby1.9 ruby 1.8 rubinius jruby }
  # In this case, "ruby" is the first level option. The others are used
  # in the second level. This might make it clearer. first3 has 2 choices under it.
  #      [ "first1" , "first2", ["first3", "second1", "second2"], "first4"]
  #
  # Currently, we return an array containing each selected level
  #
  # @return [Array] selected option/s from list
  def numbered_menu list1, config={}
    if list1.nil? || list1.empty?
      #say_with_pause "empty list passed to numbered_menu"  # 2014-04-25
       # remove bottomline
      print_error_message "Empty list passed to numbered_menu"
      return nil
    end
    prompt = config[:prompt] || "Select one: "
    require 'canis/core/util/rcommandwindow'
    layout = { :height => 5, :width => Ncurses.COLS-1, :top => Ncurses.LINES-6, :left => 0 }
    rc = CommandWindow.new nil, :layout => layout, :box => true, :title => config[:title]
    w = rc.window
    # should we yield rc, so user can bind keys or whatever
    # attempt a loop so we do levels.
    retval = []
    begin
      while true
        rc.display_menu list1, :indexing => :number
        #ret = ask(prompt, Integer ) { |q| q.in = 1..list1.size }
        # FIXME valid range won't work here since on_leave is not
        # triggered.
        ret = rb_gets(prompt) {|f| f.datatype = 1.class ; f.type :integer; f.valid_range(1..list1.size)}
        val = list1[ret-1]
        if val.is_a? Array
          retval << val[0]
          $log.debug "NL: #{retval} "
          list1 = val[1..-1]
          rc.clear
        else
          retval << val
          $log.debug "NL1: #{retval} "
          break
        end
      end
    ensure
      rc.destroy
      rc = nil
    end
    #list1[ret-1]
    $log.debug "NL2: #{retval} , #{retval.class} "
    retval
  end
  # NOTE:  moved from bottomline since it used commandwindow but now we;ve
  # moved away from ListObject to view. and i wonder what this really
  # gives ?
  # WARNING: if you actually use this, please copy it to your app, since
  # it may be removed. I don;t see what real purpose it achieves. It is
  # now a wrapper over Canis::Viewer.view
  # 
  # Displays text at the bottom of the screen, close the screen with
  # ENTER. 
  # @param text can be file name or Array of Strings.
  # @param config is a Hash. :height which will be from bottom of screen
  # and defaults to 15.
  # All other config elements are passed to +view+. See viewer.rb.
  def display_text text, config={}
    ht = config[:height] || 15
    sh = Ncurses.LINES-1
    sc = Ncurses.COLS-0
    layout = { :height => ht, :width => Ncurses.COLS-1, :top => Ncurses.LINES-ht+1, :left => 0 }
    layout = [ 10,0,20,80]
    layout = [ sh-ht ,0,ht,sc]
    config[:layout] = layout
    config[:close_key] = KEY_ENTER
    $log.debug "XXX:  DISP TEXT #{config[:title]} "
    view(text, config) do |t|
      t.suppress_borders true
    end
  end
  # return a blank if user quits list, or the value
  # can we prevent a user from quitting, he must select ? 
  # Can we suppress borders but have a reverse bar above, like the old
  # one ?
  def display_list text, config={}
    $log.debug "XXX:  DISP #{config[:title]} "
    ret = display_text text, config
  end
end # module
