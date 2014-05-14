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

  # this is taken from view and replaces the call to view, since we were
  # modifying view a bit too much to fit it into the needs here.
  #
    def command_list content, config={}, &block  #:yield: textpad
      wt = 0 # top margin
      wl = 0 # left margin
      wh = Ncurses.LINES-wt # height, goes to bottom of screen
      ww = Ncurses.COLS-wl  # width, goes to right end
      layout = { :height => wh, :width => ww, :top => wt, :left => wl } 
      if config.has_key? :layout
        layout = config[:layout]
        case layout
        when Array
          wh, ww, wt, wl = layout
          layout = { :height => wh, :width => ww, :top => wt, :left => wl } 
        when Hash
          # okay
        end
      end

      fp = config[:title] || ""
      pf = config.fetch(:print_footer, false)
      ta = config.fetch(:title_attrib, 'bold')
      fa = config.fetch(:footer_attrib, 'bold')
      b_ah = config[:app_header]
      type = config[:content_type]

      v_window = Canis::Window.new(layout)
      v_form = Canis::Form.new v_window
      v_window.name = "command-list"
      colors = Ncurses.COLORS
      back = :blue
      back = 235 if colors >= 256
      blue_white = get_color($datacolor, :white, back)

      tprow = 0
      ah = nil
      if b_ah
        ah = ApplicationHeader.new v_form, "", :text_center => fp
        tprow += 1
      end

      textview = TextPad.new v_form do
        name   "CommandList" 
        row  tprow
        col  0
        width ww
        height wh-tprow # earlier 2 but seems to be leaving space.
        title fp
        title_attrib ta
        print_footer pf
        footer_attrib fa
        #border_attrib :reverse
        border_color blue_white
      end

      t = textview
      items = {:header => ah}
      begin
        textview.set_content content, :content_type => type
        if block_given?
          if block.arity > 0
            yield textview, items
          else
            textview.instance_eval(&block)
          end
        end
      v_form.repaint
      v_window.wrefresh
      Ncurses::Panel.update_panels
      retval = ""
      # allow closing using q and Ctrl-q in addition to any key specified
      #  user should not need to specify key, since that becomes inconsistent across usages
      #  NOTE: no longer can we close with just a q since often apps using this trap char keys
      #  NOTE: 2727 is no longer operational, so putting just ESC
        while((ch = v_window.getchar()) != ?\C-q.getbyte(0) )
          # ideally we should be throwing a close rather than this since called will need keys.
          retval = textview.current_value() if ch == config[:close_key] 
          break if ch == config[:close_key] || ch == 3|| ch == 27 # removed double esc 2014-05-04 - 17:30 
          # if you've asked for ENTER then i also check for 10 and 13
          retval = textview.current_value() if (ch == 10 || ch == 13) && config[:close_key] == KEY_ENTER
          break if (ch == 10 || ch == 13) && config[:close_key] == KEY_ENTER
          v_form.handle_key ch
          v_form.repaint
        end
      rescue => err
          $log.error " command-list ERROR #{err} "
          $log.debug(err.backtrace.join("\n"))
          alert "#{err}"
          #textdialog ["Error in command-list: #{err} ", *err.backtrace], :title => "Exception"
      ensure
        v_window.destroy if !v_window.nil?
      end
      return retval
    end
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
      draw_box
      @window.wrefresh
      @panel = @window.panel
      Ncurses::Panel.update_panels
      @window.wrefresh
      @row_offset = 0
      if @box
        @row_offset = 1
      end
    end  # --- }}}

    # draw the box, needed to redo this upon clear since clearing of windows
    # was removing the top border 2014-05-04 - 20:14 
    def draw_box
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
    end

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
      win.refresh 
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
    def show
      @window.show
    end
    # this really helps if we are creating another window over this and we find the lower window
    # still showing through. destroy does not often work so this clears current window.
    # However, lower window may still have a black region. FIXME
    def hide
      @window.hide
      Window.refresh_all
    end
    def destroy
      @window.destroy
    end
    def OLDdestroy
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
      #@window.box 0,0 if @box == :border
      draw_box
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
      #indexcolor = options[:indexcolor] || get_color($normalcolor, :yellow, :black)
      indexcolor = $datacolor || 7 # XXX above line crashing on choose()
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

  # a generic key dispatcher that can be used in various classes for handling keys,
  # setting key_map and processing keys.
  module KeyDispatcher # --- {{{

    # key handler of Controlphandler 
    # This sets +@keyint+ with the value  read by window.
    # This sets +@keychr+ with the +chr+ value of +ch+ if ch between 32 and 127 exclusive.
    # @param [Fixnum] ch is key read by window.
    def handle_key ch
      $log.debug "  KeyDispatcher GOT KEY #{ch} "
      @keyint = ch
      @keychr = nil
      chr = nil
      chr = ch.chr if ch > 32 and ch < 127
      @keychr = chr

      ret = process_key ch
      # revert to the basic handling of key_map and refreshing pad.
      #####
      # NOTE
      # this is being done where we are creating some kind of front for a textpad by using +view+
      # so we steal some keys, and pass the rest to +view+. Otherwise, next line is not needed.
      # +@source+ typically would be handle to textpad yielded by +view+.
      #####
      @source._handle_key(ch) if ret == :UNHANDLED and @source
    end

    # checks the key against +@key_map+ if its set
    # @param [Fixnum] ch character read by +Window+
    # @return [0, :UNHANDLED] 0 if processed, :UNHANDLED if not processed so higher level can process
    def process_key ch
      chr = nil
      if ch > 0 and ch < 256
        chr = ch.chr
      end
      return :UNHANDLED unless @key_map
      @key_map.each_pair do |k,p|
        $log.debug "KKK:  processing key #{ch}  #{chr} "
        if (k == ch || k == chr)
          $log.debug "KKK:  checking match == #{k}: #{ch}  #{chr} "
          # compare both int key and chr
          $log.debug "KKK:  found match 1 #{ch}  #{chr} "
          p.call(self, ch)
          return 0
        elsif k.respond_to? :include?
            $log.debug "KKK:  checking match include #{k}: #{ch}  #{chr} "
            # this bombs if its a String and we check for include of a ch.
          if !k.is_a?( String ) && (k.include?( ch ) || k.include?(chr))
            $log.debug "KKK:  found match include #{ch}  #{chr} "
            p.call(self, ch)
            return 0
          end
        elsif k.is_a? Regexp
          if k.match(chr)
            $log.debug "KKK:  found match regex #{ch}  #{chr} "
            p.call(self, ch)
            return 0
          end
        end
      end
      return :UNHANDLED
    end
    # setting up some keys
    # This is currently an insertion key map, if you want a String named +@buffer+ updated.
    # Expects buffer_changed and set_buffer to exist as well as +buffer()+.
    # TODO add left and right arrow keys for changing insertion point. And other keys.
    # XXX Why are we trying to duplicate a Field here ??
    def default_string_key_map
      require 'canis/core/include/action'
      @key_map ||= {}
      @key_map[ Regexp.new('[a-zA-Z0-9_\.\/]') ] = Action.new("Append to pattern") { |obj, ch|
        obj.buffer << ch.chr
        obj.buffer_changed
      }
      @key_map[ [127, ?\C-h.getbyte(0)] ] = Action.new("Delete Prev Char") { |obj, ch|
        # backspace
        buff = obj.buffer
        buff = buff[0..-2] unless buff == ""
        obj.set_buffer buff
      }
    end

    # convenience method to bind a key or array /range of keys, or regex to a block
    # @param [int, String, #include?, Regexp] keycode If the user presses this key, then execute given block
    # @param [String, Action] descr is either a textual description of the key
    #     or an Action object
    # @param [block] unless an Action object has been passed, a block is passed for execution
    #
    # @example
    #     bind_key '%', 'Do something' {|obj, ch| actions ... }
    #     bind_key [?\C-h.getbyte(0), 127], 'Delete something' {|obj, ch| actions ... }
    #     bind_key Regexp.new('[a-zA-Z_\.]'), 'Append char' {|obj, ch| actions ... }
    # TODO test this
    def bind_key keycode, descr, &block
      if descr.is_a? Action
        @key_map[keycode] = descr
     else
       @key_map[keycode] = Action.new(descr), block
     end
    end
  end # module }}}

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
        # if class is specifited then update type in Field
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

  # This is a variation of display_list which is more for selecting a file, or dir.
  # It maps some keys to go up to parent dir, and to step into directory under cursor
  # if you are in directory mode.
  # @param [String] (optional) glob is a glob to apply when creating a listing
  # @param [Hash] config options for configuring the listing
  # @option config [Boolean] :recursive Should listing recurse, default true
  # @option config [Boolean] :dirs Should list directories only, default false
  # @option config [String] :startdir Directory to use as current
  #  You may also add other config pairs to be passed to textpad such as title
  #
  # NOTE: if you pass a glob, then :recursive will not apply. You must specify
  # recursive by prepending "**/" or inserting it in the appropriate place such 
  # as "a/b/c/**/*rb". We would not know where to place the "**/".
  #
  # @example list directories recursively
  #
  #    str = choose_file  :title => "Select a file", 
  #       :recursive => true,
  #       :dirs => true,
  #
  def choose_file glob, config={}
    if glob.is_a? Hash
      config = glob
      glob = nil
    end
    frec = true
    frec = config.delete :recursive if config.key? :recursive
    fdir = config.delete :dirs
    if glob.nil?
      glob = "*"
      if frec
        glob = "**/*"
      end
      if fdir
        glob << "/"
      end
    end
    maxh = 15
    # i am not going through that route, since going up and down a dir will be difficult in a generic
    # case the glob has the dir in it, or i pass directory to the handler.
    # why not Dir.pwd in next line ?? XXX
    #directory = Pathname.new(File.expand_path(File.dirname($0)))
    #_d = config.delete :directory
    #if _d
      #directory = Pathname.new(File.expand_path(_d))
    #end
    directory = config.delete :directory
    # this keeps going up with each invocation if I send ".."
    Dir.chdir(directory) if directory
    command = config.delete(:command)
    text = Dir.glob(glob)
    #text = Dir[File.join(directory.to_s, glob)]
    if !text or text.empty?
      text = ["No entries"]
    end
    if text.size < maxh
      config[:height] = text.size + 1
    end
    # calc window coords
    _update_default_settings config
    default_layout = config[:layout]
    config[:close_key] = 1001
    command_list(text, config) do |t, hash|
      t.suppress_borders  = true
      t.print_footer = false
      #t.fixed_bounds config.delete(:fixed_bounds)
      t.key_handler = ControlPHandler.new(t)
      t.key_handler.maxht = maxh
      t.key_handler.default_layout = default_layout
      t.key_handler.header = hash[:header]
      t.key_handler.recursive_search(glob)
      t.key_handler.directory_key_map
    end
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
    _update_default_settings config
    if text.is_a? String
      if File.exists? text
        text = File.open(text, 'r').read.split("\n")
      end
    end
    command_list(text, config) do |t|
      t.suppress_borders true
      t.print_footer false
    end
  end
  # update given hash with layout, close_key and app_header
  # so this is shared across various methods.
  # The layout created is weighted to the bottom, so it is always ending at the second last row
  def _update_default_settings config={}
    ht = config[:height] || 15
    sh = Ncurses.LINES-1
    sc = Ncurses.COLS-0
    layout = [ ht, sc, sh-ht ,0]
    config[:layout] = layout
    config[:close_key] = KEY_ENTER
    config[:app_header] = true
    # repeated resetting seems to play with left and other things.
    # let's say we know that my window will always have certain settings, then let me do a check for them in padrefresh
    # in this window the only thing changing is the top (based on rows). all else is same.
    #config[:fixed_bounds] = [nil, 0, sh, sc]
  end
  # create a new layout array based on size of data given
  # The layout created is weighted to the bottom, so it is always ending at the second last row
  # The +top+ keeps changing based on height.
  def _new_layout size
    ht = size
    #ht = 15
    sh = Ncurses.LINES-1
    sc = Ncurses.COLS-0
    layout = [ ht, sc, sh-ht ,0]
  end
  # return a blank if user quits list, or the value
  # can we prevent a user from quitting, he must select ? 
  #
  # Display a list of valies given in +text+ and allows user to shrink the list based on keys entered
  # much like control-p.
  #
  # @param [Array<String>] array of Strings to print
  # @param [ Hash ] config hash passed to Viewer.view
  #    May contain +:command+ which is a Proc that replenishes the list everytime user
  #    enters a key (updates the search string). The proc is supplied user-entered string.
  #    The following example is a proc that matches all the files returned by Dir.glob
  #    with the user entered string.
  #
  #     Proc.new {|str| Dir.glob("**/*").select do |p| p.index str; end }
  #
  # @return [ String ] text of line user pressed ENTER on, or "" if user pressed ESC or C-c
  # x show keys entered
  # x shrink the pad based on results
  # x if no results show somethinf like "No entries". or don't change
  # TODO take left and right arrow key and adjust insert point
  # TODO have some proc so user can keep querying, rather than passing a list. this way if the 
  # list is really long, all values don't need to be passed.
  def display_list text, config={}
    maxh = 15
    _update_default_settings config
    default_layout = config[:layout].dup
    command = config.delete(:command)
    command_list(text, config) do |t, hash|
      t.suppress_borders true
      t.print_footer false
      #t.fixed_bounds config.delete(:fixed_bounds)
      t.key_handler = ControlPHandler.new(t)
      t.key_handler.maxht = maxh
      t.key_handler.default_layout = default_layout
      t.key_handler.header = hash[:header]
      t.key_handler.command = command if command
    end
  end

  # This is a keyhandler that traps some keys, much like control-p which filters down a list
  # based on some alpha numeric chars. The rest, such as arrow-keys, are passed to the key_map
  #
  class ControlPHandler # --- {{{
    require 'canis/core/include/action'
    include Canis::KeyDispatcher

    attr_accessor :maxht
    attr_accessor :default_layout
    # string the user is currently entering in (pattern to filter on)
    attr_accessor :buffer
    # application_header object whose text can be changed
    attr_accessor :header
    attr_accessor :key_map
    attr_reader :source
    attr_reader :keyint
    attr_reader :keychr
    def initialize source
      @source = source
      @list = source.text
      # backup of data to refilter from if no command given to update
      @__list = @list
      @buffer = ""
      @maxht ||=15
      default_string_key_map
      default_key_map
      @no_match = false
    end

    # a default proc to requery data based on glob supplied and the pattern user enters
    def recursive_search glob="**/*"
      @command = Proc.new {|str| Dir.glob(glob).select do |p| p.index str; end }
    end

    # specify command to requery data
    def command &block
      @command = block
    end

    # signal that the data has changed and should be redisplayed
    # with window resizing etc.
    def data_changed list
      sz = list.size
      @source.text(list)
      wh = @source.form.window.height
      @source.form.window.hide
      th = @source.height
      sh = Ncurses.LINES-1
      if sz < @maxht
        # rows is less than tp size so reduce tp and window
        @source.height = sz
        nl = _new_layout sz+1
        $log.debug "XXX:  adjust ht to #{sz} layout is #{nl} size is #{sz}"
        @source.form.window.resize_with(nl)
        #Window.refresh_all
      else
        # expand the window ht to maxht
        tt = @maxht-1
        @source.height = tt
        nl = _new_layout tt+1
        $log.debug "XXX:  increase ht to #{tt} def layout is #{nl} size is #{sz}"
        @source.form.window.resize_with(nl)
      end

      @source.fire_dimension_changed

      @source.init_vars # do if rows is less than current_index.
      @source.set_form_row
      @source.form.window.show

      #Window.refresh_all
      @source.form.window.wrefresh
      Ncurses::Panel.update_panels();
      Ncurses.doupdate();
    end
    # modify the pattern (used if some procs are trying to change using handle to self)
    def set_buffer str
      @buffer = str
      buffer_changed
    end
    # signal that the user has added or deleted a char from the pattern
    # and data should be requeried, etc
    #
    def buffer_changed
      # display the pattern on the header
      @header.text1(">>>#{@buffer}_") if @header
      @header.text_right(Dir.pwd) if @header
      @no_match = false

      if @command
        @list = @command.call(@buffer)
      else
        @list = @__list.select do |line|
          line.index @buffer
        end
      end
      sz = @list.size
      if sz == 0
        Ncurses.beep
        #return 1
        #this should make ENTER and arrow keys unusable except for BS or Esc, 
        @list = ["No entries"]
        @no_match = true
      end
      data_changed @list
      0
    end

    # key handler of Controlphandler which overrides KeyDispatcher since we need to
    # intercept KEY_ENTER
    # @param [Fixnum] ch is key read by window.
    # WARNING: Please note that if this is used in +Viewer.view+, that +view+
    # has already trapped CLOSE_KEY which is KEY_ENTER/13 for closing, so we won't get 13 
    # anywhere
    def handle_key ch
      $log.debug "  HANDLER GOT KEY #{ch} "
      @keyint = ch
      @keychr = nil
      # accumulate keys in a string
      # need to track insertion point if user uses left and right arrow
        @buffer ||= ""
        chr = nil
        chr = ch.chr if ch > 47 and ch < 127
        @keychr = chr
        # Don't let user hit enter or keys if no match
        if [13,10, KEY_ENTER, KEY_UP, KEY_DOWN].include? ch
          if @no_match
            $log.warn "XXX:  KEY GOT WAS #{ch},  #{chr} "
            # viewer has already blocked KEY_ENTER !
            return 0 if [13,10, KEY_ENTER, KEY_UP, KEY_DOWN].include? ch
          else
            if [13,10, KEY_ENTER].include? ch
              @source.form.window.ungetch(1001)
              return 0
            end
          end
        end
        ret = process_key ch
        # revert to the basic handling of key_map and refreshing pad.
        # but this will rerun the keys and may once again run a mapping.
        @source._handle_key(ch) if ret == :UNHANDLED
    end

    # setting up some keys
    def default_key_map
      tp = source
      source.bind_key(?\M-n.getbyte(0), 'goto_end'){ tp.goto_end } 
      source.bind_key(?\M-p.getbyte(0), 'goto_start'){ tp.goto_start } 
    end

    # specific actions for directory listers
    # currently for stepping into directory under cursor
    # and going to parent dir.
    def directory_key_map
      @key_map["<"] = Action.new("Goto Parent Dir") { |obj|
        # go to parent dir
        $log.debug "KKK:  called proc for <"
        Dir.chdir("..")
        obj.buffer_changed
      }
      @key_map[">"] = Action.new("Change Dir"){ |obj|
        $log.debug "KKK:  called proc for > : #{obj.current_value} "
        # step into directory

        dir = obj.current_value
        if File.directory? dir
          Dir.chdir dir
          obj.buffer_changed
        end
      }
    end

    # the line on which focus is.
    def current_value
      @source.current_value
    end
  end # -- class }}}

end # module
