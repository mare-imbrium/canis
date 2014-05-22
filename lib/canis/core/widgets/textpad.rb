#!/usr/bin/env ruby
# header {{{
# vim: set foldlevel=0 foldmethod=marker :
# ----------------------------------------------------------------------------- #
#         File: textpad.rb
#  Description: A class that displays text using a pad.
#         The motivation for this is to put formatted text and not care about truncating and 
#         stuff. Also, there will be only one write, not each time scrolling happens.
#         I found textview code for repaint being more complex than required.
#       Author: jkepler http://github.com/mare-imbrium/mancurses/
#         Date: 2011-11-09 - 16:59
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-05-23 01:21
#
#  == CHANGES
#   - changed @content to @list since all multirow widgets use that and so do utils etc
#  == TODO 
#  Take care of 3 cases:
#     1. complete data change, then recreate pad, and call init_vars resetting row, col and curpos etc
#        This is done by method text().
#     2. row added or minor change - recreate pad, repaint data but don't call initvars. must maintain cursor
#        ignore recreate of pad if width or ht is less than w and h of container.
#     3. only rewrite a row - row data changed, no recreate pad or anything else
#
# ----------------------------------------------------------------------------- #
# header }}}
#
require 'canis'
require 'canis/core/include/bordertitle'
require 'forwardable'

include Canis
module Canis
  extend self
  class TextPad < Widget # 
    include BorderTitle
    extend Forwardable

# ---- Section initialization start ----- {{{
    # boolean, whether border to be suppressed or not, default false
    dsl_accessor :suppress_borders
    # boolean, whether footer is to be printed or not, default true
    dsl_accessor :print_footer
    #dsl_accessor :list_footer # attempt at making a footer object
    # index of focussed row, starting 0, index into the data supplied
    attr_reader :current_index
    # rows is the actual number of rows the pad has which is slightly less than height (taking
    #  into account borders. Same for cols and width.
    attr_reader :rows , :cols
    dsl_accessor :footer_attrib   # bold, reverse, normal
    # adding these only for debugging table, to see where cursor is.
    attr_reader :lastrow, :lastcol
    # for external methods or classes to advance cursor
    #attr_accessor :curpos
    # the object that handles keys that are sent to this object by the form.
    # This widget creates its own default handler if not overridden by user.
    attr_accessor :key_handler

    # an array of 4 items for h w t and l which can be nil, padrefresh will check
    # its bounds against this to ensure no caller messes up.
    dsl_accessor :fixed_bounds
    # You may pass height, width, row and col for creating a window otherwise a fullscreen window
    # will be created. If you pass a window from caller then that window will be used.
    # Some keys are trapped, jkhl space, pgup, pgdown, end, home, t b
    # This is currently very minimal and was created to get me started to integrating
    # pads into other classes such as textview.

    # a map of symbols and patterns, used currently in jumping to next or prev occurence of that
    #  pattern. Default contains :word. Callers may add patterns, or modify existing ones and
    #  create key bindings for the same.
    attr_reader :text_patterns
    # type of content in case parsing is required. Values :tmux, :ansi, :none
    attr_accessor :content_type
    # path of yaml file which contains conversion of style names to color, bgcolor and attrib
    attr_accessor :stylesheet

    def initialize form=nil, config={}, &block

      @editable = false
      @focusable = true
      @config = config
      @row = @col = 0
      @prow = @pcol = 0
      @startrow = 0
      @startcol = 0
      register_events( [:ENTER_ROW, :PRESS])
      @text_patterns = {}
      @text_patterns[:word] =  /[[:punct:][:space:]]\w/
      super

      init_vars
    end
    def init_vars
      $multiplier = 0
      @oldindex = @current_index = 0
      # column cursor
      @prow = @pcol = @curpos = 0
      if @row && @col
        @lastrow = @row + @row_offset
        @lastcol = @col + @col_offset
      end
      @repaint_required = true
      @parse_required = true
      map_keys unless @mapped_keys
    end

    # calculates the dimensions of the pad which will be used when the pad refreshes, taking into account
    # whether borders are printed or not. This must be called whenever there is a change in height or width 
    # otherwise @rows will not be recalculated.
    # Internal.
    def __calc_dimensions
      ## NOTE 
      #  ---------------------------------------------------
      #  Since we are using pads, you need to get your height, width and rows correct
      #  Make sure the height factors in the row, else nothing may show
      #  ---------------------------------------------------
      
     
      raise " CALC inside #{@name} h or w is nil #{@height} , #{@width} " if @height.nil? or @width.nil?
      @rows = @height
      @cols = @width
      # NOTE XXX if cols is > COLS then padrefresh can fail
      @startrow = @row
      @startcol = @col
      unless @suppress_borders
        @row_offset = @col_offset = 1
        @startrow += 1
        @startcol += 1
        @rows -=3  # 3 is since print_border_only reduces one from width, to check whether this is correct
        @cols -=3
        @scrollatrows = @height - 3
      else
        # no borders printed
        @rows -= 1  # 3 is since print_border_only reduces one from width, to check whether this is correct
        ## if next is 0 then padrefresh doesn't print, gives -1 sometimes.
        ## otoh, if we reduce 1, then there is a blank or white left at 128 since clear_pad clears 128
        # but this only writes 127 2014-05-01 - 12:31 CLEAR_PAD
        #@cols -=0
        @cols -=1
        @scrollatrows = @height - 1 # check this out 0 or 1
        @row_offset = @col_offset = 0 
      end
      @top = @row
      @left = @col
      @lastrow = @row + @row_offset
      @lastcol = @col + @col_offset
    end
    # returns the row and col where the cursor is initially placed, and where printing starts from.
    def rowcol #:nodoc:
      return @row+@row_offset, @col+@col_offset
    end

    # update the height
    # This also calls fire_dimension_changed so that the dimensions can be recalculated
    def height=(val)
      super
      fire_dimension_changed
    end
    # set the width
    # This also calls fire_dimension_changed so that the dimensions can be recalculated
    def width=(val)
      super
      fire_dimension_changed
    end
# ---- Section initialization end ----- }}}
# ---- Section pad related start ----------- {{{

    private
    ## creates the pad
    def create_pad
      destroy if @pad
      #$log.debug "XXXCP: create_pad #{@content_rows} #{@content_cols} , w:#{@width} c #{@cols} , r: #{@rows}" 
      #@pad = FFI::NCurses.newpad(@content_rows, @content_cols)
      @pad = @window.get_pad(@content_rows, @content_cols )

    end

    private
    # create and populate pad
    def populate_pad
      @_populate_needed = false
      @content_rows = @list.count

      # content_rows can be more than size of pad, but never less. Same for cols.
      @content_cols = content_cols()
      @content_rows = @rows if @content_rows < @rows
      @content_cols = @cols if @content_cols < @cols

      create_pad

      # clearstring is the string required to clear the pad to background color
      @clearstring = nil
      $log.debug "  populate pad color = #{@color} , bg = #{@bgcolor} "
      cp = get_color($datacolor, @color, @bgcolor)
      # commenting off next line meant that textdialog had a black background 2014-05-01 - 23:37 
      @cp = FFI::NCurses.COLOR_PAIR(cp)
      # we seem to be clearing always since a pad is often reused. so making the variable whenever pad created.
      #if cp != $datacolor
        #@clearstring ||= " " * @width
        @clearstring = " " * @width
      #end
      # clear pad was needed in some places, or else previous data was still showing (bline.rb)
      # However, it is creating problems in other places, esp if the bg is white, as in messageboxes
      # textdialog etc.
      # Removing on 2014-05-01 - 01:49 till we fix messagebox issue FIXME
      
      # once again trying but only for datacolor.
      clear_pad

      Ncurses::Panel.update_panels
      render_all

    end

    # clear the pad.
    # There seem to be some cases when previous content of a pad remains
    # in the last row or last col. So we clear.
    # WARNING : pad can only clear the portion of the component placed on the window.
    # As of 2014-05-01 - 16:07 this is no longer called since it messes with messagboxes.
    # If you make this operational, pls test testmessageboxes.rb and look for black areas
    # and see if the left-most column is missing.
    def clear_pad
      # this still doesn't work since somehow content_rows is less than height.
      # this is ineffectual if the rest of the code is functioning.
      # But REQUIRED for listbox which has its own clear_row needed in cases of white background.
      # as in testmessagebox.rb 5
      (0..@content_rows).each do |n|
        clear_row @pad, n
      end
      # next part is messing up messageboxes which have a white background
      # so i use this copied from print_border
      # In messageboxes the border is more inside. but pad cannot clear the entire
      # window. The component may be just a part of the window.
      r,c = rowcol
      ww=width-2
      startcol = 1
      startcol = 0 if @suppress_borders
      # need to account for borders. in col+1 and ww
      ww=@width-0 if @suppress_borders
      color = @cp || $datacolor # check this out XXX @cp is already converted to COLOR_PAIR !!
      color = get_color($datacolor, @color, @bgcolor)
      att = @attrib || NORMAL
      sp = " "
      #if color == $datacolor
      $log.debug "  clear_pad: colors #{@cp}, ( #{@bgcolor} #{@color} ) #{$datacolor} , attrib #{@attrib} . r #{r} w #{ww}, h #{@height} top #{@window.top}  "
      # 2014-05-15 - 11:01 seems we were clearing an extra row at bottom. 
        (r+1).upto(r+@height-startcol-1) do |rr|
          @window.printstring( rr, @col+0,sp*ww , color, att)
        end
      #end
    end
    # destroy the pad, this needs to be called from somewhere, like when the app
    # closes or the current window closes , or else we could have a seg fault
    # or some ugliness on the screen below this one (if nested).

    # Now since we use get_pad from window, upon the window being destroyed,
    # it will call this. Else it will destroy pad
    def destroy
      FFI::NCurses.delwin(@pad) if @pad # when do i do this ? FIXME
      @pad = nil
    end
    # write pad onto window
    #private
    # padrefresh can fail if width is greater than NCurses.COLS
    # padrefresh can fail if height (@rows + sr) is greater than NCurses.LINES or tput lines
    #   try reducing height when creating textpad.
    public
    def padrefresh
      # startrow is the row of TP plus 1 for border
      top = @window.top
      left = @window.left
      sr = @startrow + top
      sc = @startcol + left
      ser = @rows + sr
      sec = @cols + sc

      if @fixed_bounds
        #retval = FFI::NCurses.prefresh(@pad,@prow,@pcol, sr , sc , ser , sec );
        $log.debug "PAD going into fixed_bounds with #{@fixed_bounds}"
        sr = @fixed_bounds[0] if @fixed_bounds[0]
        sc = @fixed_bounds[1] if @fixed_bounds[1]
        ser = @fixed_bounds[2] if @fixed_bounds[2]
        sec = @fixed_bounds[3] if @fixed_bounds[3]
      end

      # this is a fix, but the entire popup is not moved up. title and borders are still
      # drawn in wrong positions, and left there after popup is off.
      maxr = FFI::NCurses.LINES - 1
      maxc = FFI::NCurses.COLS
      if ser > maxr
        $log.warn "XXX PADRE ser > max. sr= #{sr} and ser #{ser}. sr:#{@startrow}+ #{top} , sc:#{@startcol}+ #{left},  rows:#{@rows}+ #{sr} cols:#{@cols}+ #{sc}  top #{top} left #{left} "
        #_t = ser - maxr
        #ser = maxr
        #sr -= _t
        #$log.warn "XXX PADRE after correcting ser #{sr} and #{ser} "
      end
      # there are some freak cases where prow or pcol comes as -1, but prefresh does not return a -1. However, this 
      # could affect some other calculation somewhere.

      retval = FFI::NCurses.prefresh(@pad,@prow,@pcol, sr , sc , ser , sec );
      $log.warn "XXXPADREFRESH #{retval} #{self.class}, #{@prow}, #{@pcol}, #{sr}, #{sc}, #{ser}, #{sec}." if retval == -1
      # remove next debug statement after some testing DELETE
      $log.debug "0PADREFRESH #{retval} #{self.class}, #{@prow}, #{@pcol}, #{sr}, #{sc}, #{ser}, #{sec}." if retval == 0
      if retval < 0
        Ncurses.beep
        if sr > maxr
          $log.warn "XXXPADREF #{sr} should be <= #{maxr} "
        end
        if sc < 0 || sc >= maxc
          $log.warn "XXXPADREF #{sc} should be less than #{maxc} "
        end
        if ser > maxr || ser < sr
          $log.warn "XXXPADREF #{ser} should be less than #{maxr} and gt #{sr}  "
        end
        if sec > maxc || sec < sc
          $log.warn "XXXPADREF #{sec} should be less than #{maxc} and gt #{sc}  "
        end
        $log.warn "XXXPADRE sr= #{sr} and ser #{ser}. sr:#{@startrow}+ #{top} , sc:#{@startcol}+ #{left},  rows:#{@rows}+ #{sr} cols:#{@cols}+ #{sc}  top #{top} left #{left} "
      end
      #$log.debug "XXX:  PADREFRESH #{retval} #{self.class}, #{@prow}, #{@pcol}, #{sr}, #{sc}, #{ser}, #{sec}." if retval == 0
      # padrefresh can fail if width is greater than NCurses.COLS
      # or if height exceeds tput lines. As long as content is less, it will work
      # the moment content_rows exceeds then this issue happens. 
      # @rows + sr < tput lines
      #FFI::NCurses.prefresh(@pad,@prow,@pcol, @startrow + top, @startcol + left, @rows + @startrow + top, @cols+@startcol + left);
    end
    # length of longest string in array
    # This will give a 'wrong' max length if the array has ansi color escape sequences in it
    # which inc the length but won't be printed. Such lines actually have less length when printed
    # So in such cases, give more space to the pad.
    def content_cols
      longest = @list.max_by(&:length)
      ## 2013-03-06 - 20:41 crashes here for some reason when man gives error message no man entry
      return 0 unless longest
      longest.length
    end
    public
    # to be called with program / user has added a row or changed column widths so that 
    # the pad needs to be recreated. However, cursor positioning is maintained since this
    # is considered to be a minor change. 
    # We do not call `init_vars` since user is continuing to do some work on a row/col.
    def fire_dimension_changed
      # recreate pad since width or ht has changed (row count or col width changed)
      @_populate_needed = true
      @repaint_required = true
      @repaint_all = true
      @parse_required = true
      @__first_time = nil
    end
    # repaint only one row since content of that row has changed. 
    # No recreate of pad is done.
    def fire_row_changed ix
      return if ix >= @list.length
      clear_row @pad, ix
      #render @pad, ix, @list[ix]
      render @pad, ix, @native_text[ix]
    
    end
# ---- end pad related ----- }}}
# ---- Section render related  ----- {{{
    #
    # iterate through content rendering each row
    # 2013-03-27 - 01:51 separated so that widgets with headers such as tables can
    # override this for better control
    def render_all
      @native_text ||= @list
      #@list.each_with_index { |line, ix|
      @native_text.each_with_index { |line, ix|
        #FFI::NCurses.mvwaddstr(@pad,ix, 0, @list[ix])
        render @pad, ix, line
      }
    end

    public
    # supply a custom renderer that implements +render()+
    # @see render
    def renderer r
      @renderer = r
    end
    #
    # default method for rendering a line
    # If it is a chunkline, then we take care of it.
    # Only if it is a String do we pass to renderer.
    # Should a renderer be allowed to handle chunks. Or be yielded chunks?
    #
    def render pad, lineno, text
      if text.is_a? AbstractChunkLine
        FFI::NCurses.wmove @pad, lineno, 0
        a = get_attrib @attrib
      
        show_colored_chunks text, nil, a
        return
      end
      if @renderer
        @renderer.render @pad, lineno, text
      else
        ## messabox does have a method to paint the whole window in bg color its in rwidget.rb
        att = NORMAL
        FFI::NCurses.wattron(@pad, @cp | att)
        FFI::NCurses.mvwaddstr(@pad,lineno, 0, @clearstring) if @clearstring
        FFI::NCurses.mvwaddstr(@pad,lineno, 0, @list[lineno])

        #FFI::NCurses.mvwaddstr(pad, lineno, 0, text)
        FFI::NCurses.wattroff(@pad, @cp | att)
      end
    end
    ## ---- the next 2 methods deal with printing chunks
    # we should put it int a common module and include it
    # in Window and Pad stuff and perhaps include it conditionally.

    ## 2013-03-07 - 19:57 changed width to @content_cols since data not printing
    # in some cases fully when ansi sequences were present int some line but not in others
    # lines without ansi were printing less by a few chars.
    # This was prolly copied from rwindow, where it is okay since its for a specific width
    def print(string, _width = @content_cols)
      #return unless visible?
      w = _width == 0? Ncurses.COLS : _width
      FFI::NCurses.waddnstr(@pad,string.to_s, w) # changed 2011 dts  
    end

    def show_colored_chunks(chunks, defcolor = nil, defattr = nil)
      #return unless visible?
      chunks.each_with_color do |text, color, attrib|

        color ||= defcolor
        attrib ||= defattr || NORMAL

        #$log.debug "XXX: CHUNK textpad #{text}, cp #{color} ,  attrib #{attrib}. #{cc}, #{bg} "
        FFI::NCurses.wcolor_set(@pad, color,nil) if color
        FFI::NCurses.wattron(@pad, attrib) if attrib
        print(text)
        FFI::NCurses.wattroff(@pad, attrib) if attrib
      end
    end

    # before updating a single row in a table 
    # we need to clear the row otherwise previous contents can show through
    def clear_row pad, lineno
      if @renderer
        # required for listrenderer
        if @renderer.respond_to? :clear_row
          @renderer.clear_row pad, lineno
        end
      else
        @clearstring ||= " " * @width
        # what about bg color ??? XXX, left_margin and internal width
        #cp = get_color($datacolor, @color, @bgcolor)
        cp = @cp || FFI::NCurses.COLOR_PAIR($datacolor)
        att = @attrib || NORMAL
        FFI::NCurses.wattron(pad,cp | att)
        FFI::NCurses.mvwaddstr(pad,lineno, 0, @clearstring) 
        FFI::NCurses.wattroff(pad,cp | att)
      end
    end

    # print footer containing line and position
    def print_foot #:nodoc:
      return unless @print_footer
      return unless @suppress_borders
      footer = "R: #{@current_index+1}, C: #{@curpos+@pcol}, #{@list.length} lines  "
      @graphic.printstring( @row + @height -1 , @col+2, footer, @color_pair || $datacolor, @footer_attrib) 
=begin
      if @list_footer
        if false
          # if we want to print ourselves
          footer = @list_footer.text(self)
          footer_attrib = @list_footer.config[:attrib] ||  Ncurses::A_REVERSE
          #footer = "R: #{@current_index+1}, C: #{@curpos+@pcol}, #{@list.length} lines  "
          $log.debug " print_foot calling printstring with #{@row} + #{@height} -1, #{@col}+2"
          @graphic.printstring( @row + @height -1 , @col+2, footer, @color_pair || $datacolor, footer_attrib) 
        end
        # use default print method which only prints on left
        @list_footer.print self
      end
=end
      @repaint_footer_required = false # 2010-01-23 22:55 
    end



    # ---- Section render related  end ----- }}}
# ---- Section data related start {{{
    
    # supply a filename as source for textpad
    # Reads up file into @list
    # One can optionally send in a method which takes a filename and returns an array of data
    # This is required if you are processing files which are binary such as zip/archives and wish
    # to print the contents. (e.g. cygnus gem sends in :get_file_contents).
    #      filename("a.c", method(:get_file_contents))
    #
    def filename(filename, reader=nil)
      @file = filename
      unless File.exists? filename
        alert "#{filename} does not exist"
        return
      end
      @filetype = File.extname filename
      if reader
        @list = reader.call(filename)
      else
        @list = File.open(filename,"r").read.split("\n")
      end
      if @filetype == ""
        if @list.first.index("ruby")
          @filetype = ".rb"
        end
      end
      init_vars
      @repaint_all = true
      @_populate_needed = true
    end

    ## NOTE this breaks widgets and everyone's text which returns text of object
    # also list by itself should return the list as in listbox,  not just set
    # Supply an array of string to be displayed
    # This will replace existing text

    # display text given in an array format. This is the principal way of giving content
    # to a textpad, other than filename().
    # @param Array of lines
    # @param format (optional) can be :tmux :ansi or :none
    # If a format other than :none is given, then formatted_text is called.
    def text(*val)
      if val.empty?
        return @list
      end
      lines = val[0]
      raise "Textpad: text() received nil" unless lines
      fmt = val.size == 2 ? val[1] : :none
      case fmt
      when Hash
        #raise "textpad.text expected content_type in Hash : #{fmt}" 
        c = fmt[:content_type] 
        t = fmt[:title]
        @title = t if t
        @content_type = c if c
        @stylesheet = fmt[:stylesheet] if fmt.key? :stylesheet
        $log.debug "  TEXTPAD text() got  #{@content_type} and #{@stylesheet} "
        fmt = c
        #raise "textpad.text expected content_type in Hash : #{fmt}" unless fmt
      when Symbol
      else
        raise "textpad.text expected symbol or content_type in Hash" 
      end

      ## some programs like testlistbox which uses multibuffers calls this with a config
      # in arg2 containing :content_type and :title 


      # added so callers can have one interface and avoid an if condition
      #return formatted_text(lines, fmt) unless @content_type == :none
      # 2014-05-20 - 13:21 change and simplication of conversion process
      # We maintain original text in @list
      # but use another variable for native format (chunks).
      @parse_required = true
      if @content_type
        parse_formatted_text lines, :content_type => @content_type, :stylesheet => @stylesheet
      end

      return @list if lines.empty?
      @list = lines
      @_populate_needed = true
      @repaint_all = true
      @repaint_required = true
      init_vars
      self
    end
    alias :list :text
    # for compat with textview, FIXME keep one consistent name for this
    alias :set_content :text
    def content
      raise "content is nil " unless @list
      return @list
    end
    alias :get_content :content
    # 
    # pass in formatted text along with parser (:tmux or :ansi)
    # This text contains markup such as ansi, or tmux
    # NOTE this does not call init_vars, i think it should, text() does
    def formatted_text text, fmt
      raise "deprecated formatted_text"

      #require 'canis/core/include/chunk'
      @formatted_text = text
      @color_parser = fmt
      @repaint_required = true
      _convert_formatted
      # don't know if start is always required. so putting in caller
      #goto_start
      #remove_all
    end
    def _convert_formatted
      raise "deprecated _convert_formatted"
      if @formatted_text
        l = parse_formatted_text(@color_parser, @formatted_text)
        text(l)
        @formatted_text = nil
      end
    end
      # This has been moved from rwidget since only used here.
      #
      # Converts formatted text into chunkline objects.
      #
      # To print chunklines you may for each row:
      #       window.wmove row+height, col
      #       a = get_attrib @attrib
      #       window.show_colored_chunks content, color, a
      #
      # @param [color_parser] object or symbol :tmux, :ansi
      #       the color_parser implements parse_format, the symbols
      #       relate to default parsers provided.
      # @param [String] string containing formatted text
      #def parse_formatted_text(color_parser, formatted_text)

    # This is now to be called at start when text is set,
    # and whenever there is a data modification.
    # This updates @native_text, so how do we parse just a line or remainder of a document
    #    from a line onwards. FIXME
    # @param [Array<String>] original content sent in by user
    #     which may contain markup
    # @param [Hash] config containing
    #    content_type
    #    stylesheet
    # @return [Chunklines] content in array of chunks.
      def parse_formatted_text(formatted_text, config=nil)
        return unless @parse_required

        config ||= { :content_type => @content_type, :stylesheet => @stylesheet }

        require 'canis/core/include/chunk'
        cp = Chunks::ColorParser.new config
        l = []
        formatted_text.each { |e| 
          l << cp.convert_to_chunk(e) 
        }
        cp = nil
        @parse_required = false
        @native_text = l
      end
    #
    # returns focussed value (what cursor is on)
    # This may not be a string. A tree may return a node, a table an array or row
    def current_value
      @native_text[@current_index]
    end
    ## NOTE : 2014-04-09 - 14:05 i think this does not have line wise operations since we deal with 
    #    formatting of data
    #    But what if data is not formatted. This imposes a severe limitation. listbox does have linewise
    #    operations, so lets try them
    #
    ## append a row to the list
    # @deprecated pls use << or push as per Array semantics
    def append text
      raise "append: deprecated pls use << or push as per Array semantics"
      @list ||= []
      @list.push text
      fire_dimension_changed
      self
    end
    # @deprecated : row_count used just for compat, use length or size
    def row_count ; @list.length ; end  

    ## ------ LIST / ARRAY OPERATIONS ----
    # All multirow widgets must use Array semantics 2014-04-10 - 17:29 
    # NOTE some operations will make selected indices in selection modules invalid
    # clear will need to clear indices, delete_at and insert may need to also adjust
    # selection or focus index/es.
    #
    # delegate some operations to Array
    # ---- operations that reference Array, no modifications
    def_delegators :@list, :include?, :each, :values_at, :size, :length, :[]

    # ---- operations that modify data
    # delegate some modify operations to Array: insert, clear, delete_at, []= <<
    # However, we should check if content array is nil ?
    # fire_dim is called, although it is not required in []=
    %w[ insert delete_at << push].each { |e| 
      eval %{
      def #{e}(*args)
        @list ||= []
        fire_dimension_changed
        @parse_required = true
        @list.send(:#{e}, *args)
        self
      end
      }
    }
    # clear all items in the object.
    # NOTE: requires to be separate since init_vars is called to reset index of focus etc.
    # Also, listbox will extend this to clear selected_indices
    def clear
      return unless @list
      @list.clear
      @native_text.clear
      fire_dimension_changed
      init_vars
    end
    # update the value at index with given value, returning self
    # FIXME the native row has to be recalculated.
    def []=(index, val)
      @list[index]=val
      fire_row_changed index
      self
    end
    # ---- Section data related end }}}




   #---- Section: movement -----# {{{
    # goto first line of file
    public
    def goto_start
      #@oldindex = @current_index
      $multiplier ||= 0
      if $multiplier > 0
        goto_line $multiplier - 1
        return
      end
      @current_index = 0
      @curpos = @pcol = @prow = 0
      @prow = 0
      $multiplier = 0
    end

    # goto last line of file
    def goto_end
      #@oldindex = @current_index
      $multiplier ||= 0
      if $multiplier > 0
        goto_line $multiplier - 1
        return
      end
      @current_index = @list.count() - 1
      @prow = @current_index - @scrollatrows
      $multiplier = 0
    end
    def goto_line line
      ## we may need to calculate page, zfm style and place at right position for ensure visible
      #line -= 1
      @current_index = line
      ensure_visible line
      bounds_check
      $multiplier = 0
    end
    def top_of_window
      @current_index = @prow 
      $multiplier ||= 0
      if $multiplier > 0
        @current_index += $multiplier
        $multiplier = 0
      end
    end
    def bottom_of_window
      @current_index = @prow + @scrollatrows
      $multiplier ||= 0
      if $multiplier > 0
        @current_index -= $multiplier
        $multiplier = 0
      end
    end

    def middle_of_window
      @current_index = @prow + (@scrollatrows/2)
      $multiplier = 0
    end

    # move down a line mimicking vim's j key
    # @param [int] multiplier entered prior to invoking key
    def down num=(($multiplier.nil? or $multiplier == 0) ? 1 : $multiplier)
      #@oldindex = @current_index if num > 10
      @current_index += num
      # no , i don't like this here. it scrolls up too much making prow = current_index
      unless is_visible? @current_index
        #alert "#{@current_index} not visible prow #{@prow} #{@scrollatrows} "
          @prow += num
      end
      #ensure_visible
      $multiplier = 0
    end

    # move up a line mimicking vim's k key
    # @param [int] multiplier entered prior to invoking key
    def up num=(($multiplier.nil? or $multiplier == 0) ? 1 : $multiplier)
      #@oldindex = @current_index if num > 10
      @current_index -= num
      #unless is_visible? @current_index
        #if @prow > @current_index
          ##$status_message.value = "1 #{@prow} > #{@current_index} "
          #@prow -= 1
        #else
        #end
      #end
      $multiplier = 0
    end

    # scrolls window down mimicking vim C-e
    # @param [int] multiplier entered prior to invoking key
    def scroll_window_down num=(($multiplier.nil? or $multiplier == 0) ? 1 : $multiplier)
      @prow += num
        if @prow > @current_index
          @current_index += 1
        end
      #check_prow
      $multiplier = 0
    end

    # scrolls window up mimicking vim C-y
    # @param [int] multiplier entered prior to invoking key
    def scroll_window_up num=(($multiplier.nil? or $multiplier == 0) ? 1 : $multiplier)
      @prow -= num
      unless is_visible? @current_index
        # one more check may be needed here TODO
        @current_index -= num
      end
      $multiplier = 0
    end

    # scrolls lines a window full at a time, on pressing SPACE or C-d or pagedown
    def scroll_forward
      #@oldindex = @current_index
      @current_index += @scrollatrows
      @prow = @current_index - @scrollatrows
    end

    # scrolls lines backward a window full at a time, on pressing pageup 
    # C-u may not work since it is trapped by form earlier. Need to fix
    def scroll_backward
      #@oldindex = @current_index
      @current_index -= @scrollatrows
      @prow = @current_index - @scrollatrows
    end
    def goto_last_position
      return unless @oldindex
      tmp = @current_index
      @current_index = @oldindex
      @oldindex = tmp
      bounds_check
    end
    def scroll_right
      # I don't think it will ever be less since we've increased it to cols
      if @content_cols <= @cols
        maxpcol = 0
        @pcol = 0
      else
        maxpcol = @content_cols - @cols - 1
        @pcol += 1
        @pcol = maxpcol if @pcol > maxpcol
      end
      # to prevent right from retaining earlier painted values
      # padreader does not do a clear, yet works fine.
      # OK it has an update_panel after padrefresh, that clears it seems.
      #this clears entire window not just the pad
      #FFI::NCurses.wclear(@window.get_window)
      # so border and title is repainted after window clearing
      #
      # Next line was causing all sorts of problems when scrolling  with ansi formatted text
      #@repaint_all = true
    end
    def scroll_left
      @pcol -= 1
    end
    #
    # jumps cursor to next word, like vim's w key
    #
    def forward_word
        #forward_regex(/[[:punct:][:space:]]\w/)
        forward_regex(:word)
    end
    # jump to the next occurence of given regex in the current line.
    # It only jumps to next line after exhausting current.
    # @param [Regexp] passed to String.index
    def forward_regex regex
      if regex.is_a? Symbol
        regex = @text_patterns[regex]
        raise "Pattern specified #{regex} does not exist in text_patterns " unless regex
      end
      $multiplier = 1 if !$multiplier || $multiplier == 0
      line = @current_index
      buff = @native_text[line].to_s
      return unless buff
      pos = @curpos || 0 # list does not have curpos
      $multiplier.times {
        found = buff.index(regex, pos)
        if !found
          # if not found, we've lost a counter
          if line+1 < @native_text.length
            line += 1
          else
            return
          end
          pos = 0
        else
          pos = found + 1
        end
        $log.debug " forward_word: pos #{pos} line #{line} buff: #{buff}"
      }
      $multiplier = 0
      @current_index = line
      @curpos = pos
      ensure_visible
      @repaint_required = true
    end
    # jump to previous word, like vim's "b"
    def backward_word
        #backward_regex(/[[:punct:][:space:]]\w/)
        backward_regex(:word)
    end
    # jump to previous occurence of given regexp
    # @param [Regexp] pattern to go back to.
    def backward_regex regex
      if regex.is_a? Symbol
        regex = @text_patterns[regex]
        raise "Pattern specified #{regex} does not exist in text_patterns " unless regex
      end
      $multiplier = 1 if !$multiplier || $multiplier == 0
      line = @current_index
      buff = @native_text[line].to_s
      return unless buff
      pos = @curpos || 0 # list does not have curpos
      $multiplier.times {
        found = buff.rindex(regex, pos-2)
        if !found || found == 0
          # if not found, we've lost a counter
          if pos > 0
            pos = 0
          elsif line > 0
            line -= 1
            pos = @native_text[line].to_s.size
          else
            return
          end
        else
          pos = found + 1
        end
        $log.debug " backward_word: pos #{pos} line #{line} buff: #{buff}"
      }
      $multiplier = 0
      @current_index = line
      @curpos = pos
      ensure_visible
      @repaint_required = true
    end
    #
    # move cursor forward by one char (currently will not pan)
    def cursor_forward
      $multiplier = 1 if $multiplier == 0
      if @curpos < @cols
        @curpos += $multiplier
        if @curpos > @cols
          @curpos = @cols
        end
        @repaint_required = true
      end
      $multiplier = 0
    end
    #
    # move cursor backward by one char (currently will not pan)
    def cursor_backward
      $multiplier = 1 if $multiplier == 0
      if @curpos > 0
        @curpos -= $multiplier
        @curpos = 0 if @curpos < 0
        @repaint_required = true
      end
      $multiplier = 0
    end
    # moves cursor to end of line also panning window if necessary
    # NOTE: if one line on another page (not displayed) is way longer than any
    # displayed line, then this will pan way ahead, so may not be very intelligent
    # in such situations.
    def cursor_eol
      # pcol is based on max length not current line's length
      @pcol = @content_cols - @cols - 1
      @curpos = @native_text[@current_index].size
      @repaint_required = true
    end
    # 
    # moves cursor to start of line, panning if required
    def cursor_bol
      # copy of C-a - start of line
      @repaint_required = true if @pcol > 0
      @pcol = 0
      @curpos = 0
    end
    # 
    # return true if the given row is visible
    def is_visible? index
      j = index - @prow #@toprow
      j >= 0 && j <= @scrollatrows
    end
#---- Section: movement end -----# }}}
#---- Section: internal stuff start -----# {{{
    public
    def create_default_keyhandler
      @key_handler = DefaultKeyHandler.new self
    end
    #
    def handle_key ch
      return :UNHANDLED unless @list

      unless @key_handler
        create_default_keyhandler
      end
      @oldrow = @prow
      @oldcol = @pcol
      $log.debug "XXX: TEXTPAD got #{ch} prow = #{@prow}"
      ret = @key_handler.handle_key(ch)
    end
    # this is a barebones handler to be used only if an overriding key handler
    # wishes to fall back to default processing after it has handled some keys.
    # The complete version is in Defaultkeyhandler.
    # BUT the key will be executed again.
    def _handle_key ch
      begin
        ret = process_key ch, self
        $multiplier = 0
        bounds_check
      rescue => err
        $log.error " TEXTPAD ERROR INS #{err} "
        $log.debug(err.backtrace.join("\n"))
        alert "#{err}"
        #textdialog ["Error in TextPad: #{err} ", *err.backtrace], :title => "Exception"
      ensure
        padrefresh
        Ncurses::Panel.update_panels
      end
      return 0
    end


    #
    # event when user hits ENTER on a row, user would bind :PRESS
    # callers may use +text()+ to get the value of the row, +source+ to get parent object.
    #
    #     obj.bind :PRESS { |eve| eve.text } 
    #
    def fire_action_event
      return if @list.nil? || @list.size == 0
      require 'canis/core/include/ractionevent'
      aev = TextActionEvent.new self, :PRESS, current_value().to_s, @current_index, @curpos
      fire_handler :PRESS, aev
    end
    # 
    # execute binding when a row is entered, used more in lists to display some text
    # in a header or footer as one traverses
    #
    def on_enter_row arow
      return nil if @list.nil? || @list.size == 0

      @repaint_footer_required = true
      #alert "on_enter rr #{@repaint_required}, #{@repaint_all} oi #{@oldindex}, ci #{@current_index}, or #{@oldrow}  "

      ## can this be done once and stored, and one instance used since a lot of traversal will be done
      require 'canis/core/include/ractionevent'
      aev = TextActionEvent.new self, :ENTER_ROW, current_value().to_s, @current_index, @curpos
      fire_handler :ENTER_ROW, aev
      #@repaint_required = true
    end

    #
    # called when this widget is entered, by form
    def on_enter
      set_form_row
    end
    # called by form
    def set_form_row
      setrowcol @lastrow, @lastcol
    end
    # called by form
    def set_form_col
    end

    private
    
    # check that current_index and prow are within correct ranges
    # sets row (and someday col too)
    # sets repaint_required

    public
    def bounds_check
      r,c = rowcol
      @current_index = 0 if @current_index < 0
      @current_index = @list.count()-1 if @current_index > @list.count()-1
      ensure_visible

      check_prow
      #$log.debug "XXX: PAD BOUNDS ci:#{@current_index} , old #{@oldrow},pr #{@prow}, max #{@maxrow} pcol #{@pcol} maxcol #{@maxcol}"
      @crow = @current_index + r - @prow
      @crow = r if @crow < r
      # 2 depends on whetehr suppress_borders
      if @suppress_borders
        @crow = @row + @height -1 if @crow >= r + @height -1
      else
        @crow = @row + @height -2 if @crow >= r + @height -2
      end
      setrowcol @crow, @curpos+c
      lastcurpos @crow, @curpos+c
      if @oldindex != @current_index
        on_leave_row @oldindex if respond_to? :on_leave_row
        on_enter_row @current_index
        @oldindex = @current_index
      end
      if @oldrow != @prow || @oldcol != @pcol
        # only if scrolling has happened.
        @repaint_required = true
      end
    end
    # 
    # save last cursor position so when reentering, cursor can be repositioned
    def lastcurpos r,c
      @lastrow = r
      @lastcol = c
    end


    # check that prow and pcol are within bounds
    #
    def check_prow
      @prow = 0 if @prow < 0
      @pcol = 0 if @pcol < 0

      cc = @list.count

      if cc < @rows
        @prow = 0
      else
        maxrow = cc - @rows - 1
        if @prow > maxrow
          @prow = maxrow
        end
      end
      # we still need to check the max that prow can go otherwise
      # the pad shows earlier stuff.
      # 
      return
    end
    public
    def repaint
      unless @__first_time
        __calc_dimensions
        @__first_time = true
      end
      return unless @list # trying out since it goes into padrefresh even when no data 2014-04-10 - 00:32 
      @graphic = @form.window unless @graphic
      @window ||= @graphic
      raise "Window not set in textpad" unless @window

      ## 2013-03-08 - 21:01 This is the fix to the issue of form callign an event like ? or F1
      # which throws up a messagebox which leaves a black rect. We have no place to put a refresh
      # However, form does call repaint for all objects, so we can do a padref here. Otherwise,
      # it would get rejected. UNfortunately this may happen more often we want, but we never know
      # when something pops up on the screen.
      $log.debug "  repaint textpad RR #{@repaint_required} #{@window.top} "
      unless @repaint_required
        print_foot if @repaint_footer_required  # set in on_enter_row
        # trying out removing this, since too many refreshes 2014-05-01 - 12:45 
        #padrefresh 
        return 
      end
      # if repaint is required, print_foot not called. unless repaint_all is set, and that 
      # is rarely set.
      
      #_convert_formatted
      # Now this is being called every time a repaint happens, it should only be called if data has changed.
      if @content_type
        parse_formatted_text @list, :content_type => @content_type, :stylesheet => @stylesheet
      end

      # in textdialog, @window was nil going into create_pad 2014-04-15 - 01:28 

      # creates pad and calls render_all
      populate_pad if @_populate_needed

      _do_borders
      print_foot if @repaint_footer_required  # if still not done

      padrefresh
      # in some cases next line prevents overlapped window from refreshing again, leaving black rows.
      # removing it causes problems in other cases. (tasks.rb, confirm window. dbdemo, F2 closing)
      Ncurses::Panel.update_panels
      @repaint_required = false
      @repaint_all = false
    end

    def _do_borders
      unless @suppress_borders
        if @repaint_all
          ## XXX im not getting the background color.
          #@window.print_border_only @top, @left, @height-1, @width, $datacolor
          clr = get_color $datacolor, @color, @bgcolor
          #@window.print_border @top, @left, @height-1, @width, clr
          @window.print_border_only @top, @left, @height-1, @width, clr
          print_title

          # oldrow changed to oldindex 2014-04-13 - 16:55 
          @repaint_footer_required = true if @oldindex != @current_index 
          print_foot if @print_footer && !@suppress_borders && @repaint_footer_required

          @window.wrefresh
        end
      end
    end

    #
    # key mappings
    #
    # TODO take from listbindings so that emacs and vim can be selected. also user can change in one place.
    def map_keys
      @mapped_keys = true
      bind_key([?g,?g], 'goto_start'){ goto_start } # mapping double keys like vim
      bind_key(279, 'goto_start'){ goto_start } 
      bind_keys([?G,277], 'goto end'){ goto_end } 
      bind_keys([?k,KEY_UP], "Up"){ up } 
      bind_keys([?j,KEY_DOWN], "Down"){ down } 
      bind_key(?\C-e, "Scroll Window Down"){ scroll_window_down } 
      bind_key(?\C-y, "Scroll Window Up"){ scroll_window_up } 
      bind_keys([32,338, ?\C-d], "Scroll Forward"){ scroll_forward } 
      # adding CTRL_SPACE as back scroll 2014-04-14 
      bind_keys([0,?\C-b,339], "Scroll Backward"){ scroll_backward } 
      # the next one invalidates the single-quote binding for bookmarks
      #bind_key([?',?']){ goto_last_position } # vim , goto last row position (not column)
      bind_key(?/, :ask_search)
      bind_key(?n, :find_more)
      bind_key([?\C-x, ?>], :scroll_right)
      bind_key([?\C-x, ?<], :scroll_left)
      bind_key(?\M-l, :scroll_right)
      bind_key(?\M-h, :scroll_left)
      bind_key(?L, :bottom_of_window)
      bind_key(?M, :middle_of_window)
      bind_key(?H, :top_of_window)
      bind_key(?w, :forward_word)
      bind_key(?b, :backward_word)
      bind_key(?l, :cursor_forward)
      bind_key(?h, :cursor_backward)
      bind_key(?$, :cursor_eol)
      bind_key(KEY_ENTER, :fire_action_event)
    end
    # convenience method to return byte -- is it used ???
    private
    def key x
      x.getbyte(0)
    end

# ----------- end internal stuff --------------- }}}
    public
# ---- Section search related start ----- {{{
    ## 
    # Ask user for string to search for
    # This uses the dialog, but what if user wants the old style.
    # Isn't there a cleaner way to let user override style, or allow user
    # to use own UI for getting pattern and then passing here.
    # @param str default nil. If not passed, then user is prompted using get_string dialog
    #    This allows caller to use own method to prompt for string such as 'get_line' or 'rbgetstr' /
    #    'ask()'
    def ask_search str=nil
      # the following is a change that enables callers to prompt for the string
      # using some other style, basically the classical style and send the string in
      str = get_string("Enter pattern: ", :title => "Find pattern") unless str
      return if str.nil? 
      str = @last_regex if str == ""
      return if !str or str == ""
      ix = next_match str
      return unless ix
      @last_regex = str

      #@oldindex = @current_index
      @current_index = ix[0]
      @curpos = ix[1]
      ensure_visible
    end
    ## 
    # Find next matching row for string accepted in ask_search
    #
    def find_more
      return unless @last_regex
      ix = next_match @last_regex
      return unless ix
      #@oldindex = @current_index
      @current_index = ix[0]
      @curpos = ix[1]
      ensure_visible
    end

    ## 
    # Find the next row that contains given string
    # @return row and col offset of match, or nil
    # @param String to find
    def next_match str
      return unless str
      first = nil
      ## content can be string or Chunkline, so we had to write <tt>index</tt> for this.
      ## =~ does not give an error, but it does not work.
      @native_text.each_with_index do |line, ix|
        _col = line.index str
        if _col
          first ||= [ ix, _col ]
          if ix > @current_index
            return [ix, _col]
          end
        end
      end
      return first
    end
    def next_regex regex
      if regex.is_a? Symbol
        regex = @text_patterns[regex]
        raise "Pattern specified #{regex} does not exist in text_patterns " unless regex
      end
      @last_regex = regex
      find_more 
    end
    ## 
    # Ensure current row is visible, if not make it first row
    # NOTE - need to check if its at end and then reduce scroll at rows, check_prow does that
    # 
    # @param current_index (default if not given)
    #
    def ensure_visible row = @current_index
      unless is_visible? row
          @prow = row
      end
    end

    # returns the row offset of the focussed row, based on what is visible
    # this takes into account scrolling, and is useful if some caller needs to know
    # where the current index is actually being displayed (example if it wishes to display
    # a popup at that row)
    # An argument is not being taken since the index should be visible.
    def visual_index 
      row = @current_index
      row - @prow
    end



    # ---- Section search related end ----- }}}
##---- dead unused {{{
    ## some general methods for highlighting a row or changing attribute. However, these
    # will change the moment panning is done, or a repaint happens.
    # If these should be maintained then they should be called from the repaint method
    #
    # This was just indicative, and is not used anywhere
    def DEADhighlight_row index = @current_index, cfg={}
      return unless index 
      c = 0 # we are using pads so no col except for left_margin if present
      # in a pad we don't need to convert index to printable
      r = index
      defcolor = cfg[:defaultcolor] || $promptcolor
      acolor ||= get_color defcolor, cfg[:color], cfg[:bgcolor]
      att = FFI::NCurses::A_REVERSE
      att = get_attrib(cfg[:attrib]) if cfg[:attrib]
      #@graphic.mvchgat(y=r, x=c, @width-2, att , acolor , nil)
      FFI::NCurses.mvwchgat(@pad, y=r, x=c, @width-2, att, acolor, nil)
    end
##---- dead unused }}}

  end  # class textpad 
# renderer {{{
  # a test renderer to see how things go
  class DefaultFileRenderer
    attr_accessor :default_colors

    def initialize
      @default_colors = [:white, :black, NORMAL]
      @pair = get_color($datacolor, @default_colors.first, @default_colors[1])
    end

    def color_mappings hash
      @hash = hash
    end
    def insert_mapping regex, dim
      @hash ||= {}
      @hash[regex] = dim
    end
    def match_line line
      @hash.each_pair {| k , p|
        if line =~ k
          return p
        end
      }
      return @default_colors
    end
    def render pad, lineno, text
      if @hash
        dim = match_line text
        fg = dim.first
        bg = dim[1] || @default_colors[1]
        if dim.size == 3
          att = dim.last
        else
          att = @default_colors.last
        end
        cp = get_color($datacolor, fg, bg)
      else
        cp = @pair
        att = @default_colors[2]
      end

      FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      FFI::NCurses.mvwaddstr(pad, lineno, 0, text)
      FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
    end
    #
    # @param pad for calling print methods on
    # @param lineno the line number on the pad to print on
    # @param text data to print
    def OLDrender pad, lineno, text
      bg = :black
      fg = :white
      att = NORMAL
      #cp = $datacolor
      cp = get_color($datacolor, fg, bg)
      ## XXX believe it or not, the next line can give you "invalid byte sequence in UTF-8
      # even when processing filename at times. Or if its an mp3 or non-text file.
      if text =~ /^\s*# / || text =~ /^\s*## /
        fg = :red
        #att = BOLD
        cp = get_color($datacolor, fg, bg)
      elsif text =~ /^\s*#/
        fg = :blue
        cp = get_color($datacolor, fg, bg)
      elsif text =~ /^\s*(class|module) /
        fg = :cyan
        att = BOLD
        cp = get_color($datacolor, fg, bg)
      elsif text =~ /^\s*def / || text =~ /^\s*function /
        fg = :yellow
        att = BOLD
        cp = get_color($datacolor, fg, bg)
      elsif text =~ /^\s*(end|if |elsif|else|begin|rescue|ensure|include|extend|while|unless|case |when )/
        fg = :magenta
        att = BOLD
        cp = get_color($datacolor, fg, bg)
      elsif text =~ /^\s*=/
        # rdoc case
        fg = :blue
        bg = :white
        cp = get_color($datacolor, fg, bg)
        att = REVERSE
      end
      FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      FFI::NCurses.mvwaddstr(pad, lineno, 0, text)
      FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)

    end
  end
# renderer }}}
# This is the default key handler.
  # It takes care of catching numbers so that vim's movement can use numeric args. 
  # That is taken care of by multiplier. Other than that it has the key_map process the key.
  #
  class DefaultKeyHandler # ---- {{{
    def initialize source
      @source = source
    end

    def handle_key ch
      begin
        case ch
        when ?0.getbyte(0)..?9.getbyte(0)
          if ch == ?0.getbyte(0) && $multiplier == 0
            @source.cursor_bol
            return 0
          end
          # storing digits entered so we can multiply motion actions
          $multiplier *= 10 ; $multiplier += (ch-48)
          return 0
        when ?\C-c.getbyte(0)
          $multiplier = 0
          return 0
        else
          # check for bindings, these cannot override above keys since placed at end
          begin
            ret = @source.process_key ch, self
            $multiplier = 0
            @source.bounds_check
            ## If i press C-x > i get an alert from rwidgets which blacks the screen
            # if i put a padrefresh here it becomes okay but only for one pad,
            # i still need to do it for all pads.
          rescue => err
            $log.error " TEXTPAD ERROR INS #{err} "
            $log.debug(err.backtrace.join("\n"))
            alert "#{err}"
            #textdialog ["Error in TextPad: #{err} ", *err.backtrace], :title => "Exception"
          end
          # --- NOTE ABOUT BLACK RECT LEFT on SCREEN {{{
          ## NOTE if textpad does not handle the event and it goes to form which pops
          # up a messagebox, then padrefresh does not happen, since control does not 
          # come back here, so a black rect is left on screen
          # please note that a bounds check will not happen for stuff that 
          # is triggered by form, so you'll have to to it yourself or 
          # call setrowcol explicity if the cursor is not updated
          # --- }}}

          return :UNHANDLED if ret == :UNHANDLED
        end
      rescue => err
        $log.error " TEXTPAD ERROR 591 #{err} "
        $log.debug( err) if err
        $log.debug(err.backtrace.join("\n")) if err
        # NOTE: textdialog itself is based on this class.
        alert "#{err}"
        #textdialog ["Error in TextPad: #{err} ", *err.backtrace], :title => "Exception"
        $error_message.value = ""
      ensure
        @source.padrefresh
        Ncurses::Panel.update_panels
      end
      return 0
    end # def
  end # class }}}
end # mod
