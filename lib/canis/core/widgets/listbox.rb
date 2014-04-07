#!/usr/bin/env ruby
# ----------------------------------------------------------------------------- #
#         File: listbox.rb
#  Description: A list box based on textpad
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 2014-04-06 - 19:37 
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-04-08 01:38
# ----------------------------------------------------------------------------- #
#   listbox.rb Copyright (C) 2012-2014 kepler

require 'logger'
require 'canis'
require 'canis/core/widgets/textpad'
require 'forwardable'

## 
# A listbox based on textpad. 
# Contains a scrollable array of Strings. The list is selectable too.
# In place editing is not provided, however editing in a separate box
# has been implemented in various examples.
# TODO
#   _ compare to rlist and see what's missing
#   [ ] selected_color - IMP we have no way of knowing what is selected right now
#   [ ] focussed color - this could be part of textpad too. row under cursor
#
#
#   old rlist actually does a coloring of selected rows in the repaint loop checking each rows select status
#
#
module Canis

  ##
  # A scrollable, selectable array of strings.
  #
  class Listbox < TextPad

    extend Forwardable

    dsl_property :show_selector # boolean
    # should textpads content_cols also add left_margin ? XXX
    dsl_property :left_margin
    # already in textpad, so what was it doing in tablewidget?
    #dsl_accessor :print_footer
    # selection mode :multiple, :single and :none 
    dsl_accessor :selection_mode
    dsl_accessor :selected_color, :selected_bgcolor, :selected_attr
    # justify text to :left :right or :center TODO
    dsl_accessor :justify # will be picked up by renderer
    # index of selected row
    attr_accessor :selected_index
    # index of selected rows, if multiple selection asked for
    dsl_accessor :selected_indices
    # model that takes care of selection operations
    attr_accessor :list_selection_model

    # avoiding for the while
    #dsl_accessor :should_show_focus

    def initialize form = nil, config={}, &block

      @selected_indices = []
      @selected_index = nil
      @selection_mode = :multiple # default is multiple, anything else given becomes single
      @left_margin = 0

      super
      # textpad takes care of enter_row and press
      @_events.push(*[:LEAVE_ROW, :LIST_SELECTION_EVENT])

      unless @list_selection_model
        @list_selection_model = DefaultListSelectionModel.new self
      end
      unless @renderer
        @renderer = ListRenderer.new self
      end
    end

    # all operations of selection are delegated to the ListSelectionModel
    def_delegators :@list_selection_model, :toggle_row_selection, :select, :unselect, :is_row_selected?, :is_selection_empty?, :clear_selection, :remove_index, :selected_rows, :select_all

    

    ## add a row to the list
    def add text
      unless @content
        # columns were not added, this most likely is the title
        @content ||= []
      end
      #@content << array
      @content.push text
      fire_dimension_changed
      self
    end
    alias :append :add
    # http://www.opensource.apple.com/source/gcc/gcc-5483/libjava/javax/swing/table/DefaultTableColumnModel.java
    #
    # get element at
    # @param [Fixnum] index for element
    # @return [Object] element
    # @since 1.2.0  2010-09-06 14:33 making life easier for others.
    def [](off0)
      @content[off0]
    end
    # return object under cursor
    # Note: this should not be confused with selected row/s. User may not have selected this.
    # This is only useful since in some demos we like to change a status bar as a user scrolls down
    # @since 1.2.0  2010-09-06 14:33 making life easier for others.
    def current_value
      @content[@current_index]
    end
    def remove_all
      return if @content.nil? || @content.empty? 
      @content = []
      init_vars
    end
    # delegate some operations to Array
    def_delegators :@content, :include?, :each, :values, :size

    # delegate some modify operations to Array: insert, clear, delete_at, []= <<
    # However, we should check if content array is nil ?
    # fire_dim is called, although it is not required in []=
    %w[ insert clear delete_at []= << ].each { |e| 
      eval %{
      def #{e}(*args)
         fire_dimension_changed
         @content.send(:#{e}, *args)
      end
      }
    }

    # TODO needs to be called from whereever on_enter_row is called
    def on_leave_row arow
      fire_handler :LEAVE_ROW, self
    end
    def on_enter_row arow
      super
      ## this results in the row being entered and left being evaluated and repainted
      # which means that the focussed row can be bolded. The renderer's +render+ method will be triggered
      fire_row_changed @oldindex
      fire_row_changed arow
    end

    def map_keys
      super

      unbind_key(32)

      bind_key($row_selector || 32, 'toggle selection') { toggle_row_selection @current_index }
    end

    def repaintXX


      super

      # in pads index of row does not need to be converted to printable_row as was the case in window
      # here we can just go and highlight a row straight onto the pad, we can check that the pad has that
      # height.
      #
      # this is happening after the next keystroke
      # also repaint itself needs to take care of this when it draws a new pad
      #
      if @selected_indices.size > 0
        highlight_row @selected_indices.last, { :defaultcolor => $datacolor, :color => @selected_color ||  @color, :bgcolor => @selected_bgcolor || @bgcolor, :attrib => FFI::NCurses::A_REVERSE} 
      #highlight_row @selected_indices.last, { :color => @selected_color, :bgcolor => @selected_bgcolor, :attrib => FFI::NCurses::A_REVERSE} 
      end
    end


  end # class listbox

  class ListSelectionEvent < Struct.new(:firstrow, :lastrow, :source, :type)
  end

  ## I am copying this from listselectable. that was a module so was included and shared variables
  # but now this is a class, and cannot access state as directly

  class DefaultListSelectionModel

    def initialize component
      @obj = component
      #@selected_indices = []
      @selected_indices = @obj.selected_indices
      @selection_mode = @obj.selection_mode
      list_bindings
    end
    # @group selection related

    # change selection of current row on pressing space bar
    # If mode is multiple, then other selections are cleared and this is added
    # @example
    #     bind_key(32) { toggle_row_selection }
    # current_index is not account for header_adjustment
    # if current row is selected in mulitple we should deselect ?? FIXME
    def toggle_row_selection crow=@obj.current_index
      @last_clicked = crow
      @repaint_required = true
      case @selection_mode 
      when :multiple
        if @selected_indices.include? crow
          @selected_indices.delete crow
          lse = ListSelectionEvent.new(crow, crow, self, :DELETE)
          @obj.fire_handler :LIST_SELECTION_EVENT, lse
        else
          @selected_indices << crow
          lse = ListSelectionEvent.new(crow, crow, self, :INSERT)
          @obj.fire_handler :LIST_SELECTION_EVENT, lse
        end
      else
        # single - now change to use array only
        @selected_index = @selected_indices[0]
        if @selected_index == crow 
          @old_selected_index = @selected_index # 2011-10-15 so we can unhighlight
          @selected_index = nil
          @selected_indices.clear
          lse = ListSelectionEvent.new(crow, crow, self, :DELETE)
          @obj.fire_handler :LIST_SELECTION_EVENT, lse
        else
          @selected_indices[0] = crow
          @obj.fire_row_changed(@old_selected_index) if @old_selected_index
          @old_selected_index = crow # 2011-10-15 so we can unhighlight
          lse = ListSelectionEvent.new(crow, crow, self, :INSERT)
          @obj.fire_handler :LIST_SELECTION_EVENT, lse
        end
      end
      @obj.fire_row_changed crow
      #alert "toggling #{@selected_indices.join(',')}"
    end
    #
    # Range select.
    # Only for multiple mode.
    # Uses the last row clicked on, till the current one.
    # If user clicks inside a selcted range, then deselect from last click till current (remove from earlier)
    # If user clicks outside selected range, then select from last click till current (add to earlier)
    # typically bound to Ctrl-Space
    # @example
    #     bind_key(0) { add_to_selection }
    def add_to_selection crow=@obj.current_index
      #alert "add to selection fired #{@last_clicked}"
      @last_clicked ||= crow
      min = [@last_clicked, crow].min
      max = [@last_clicked, crow].max
      case @selection_mode 
      when :multiple
        if @selected_indices.include? crow
          # delete from last_clicked until this one in any direction
          min.upto(max){ |i| @selected_indices.delete i 
                         @obj.fire_row_changed i
          }
          lse = ListSelectionEvent.new(min, max, self, :DELETE)
          @obj.fire_handler :LIST_SELECTION_EVENT, lse
        else
          # add to selection from last_clicked until this one in any direction
          min.upto(max){ |i| @selected_indices << i unless @selected_indices.include?(i) 
                         @obj.fire_row_changed i
          }
          lse = ListSelectionEvent.new(min, max, self, :INSERT)
          @obj.fire_handler :LIST_SELECTION_EVENT, lse
        end
      else
      end
      @last_clicked = crow # 2014-04-08 - 01:21 this was missing, i think it is required
      self
    end
    # clears selected indices, typically called when multiple select
    # Key binding is application specific
    def clear_selection
      return if @selected_indices.nil? || @selected_indices.empty?
      arr = @selected_indices.dup # to un highlight
      @selected_indices.clear
      arr.each {|i| @obj.fire_row_changed(i) }
      @selected_index = nil
      @old_selected_index = nil
      #  User should ignore first two params
      lse = ListSelectionEvent.new(0, arr.size, self, :CLEAR)
      @obj.fire_handler :LIST_SELECTION_EVENT, lse
      arr = nil
    end
    def is_row_selected crow
      case @selection_mode 
      when :multiple
        @selected_indices.include? crow
      else
        @selected_index = @selected_indices[0]
        crow == @selected_index
      end
    end
    alias :is_selected? is_row_selected
    # FIXME add adjustment and test
    def goto_next_selection
      return if selected_rows().length == 0 
      row = selected_rows().sort.find { |i| i > @obj.current_index }
      row ||= @obj.current_index
      @obj.current_index = row
      @repaint_required = true # fire list_select XXX
    end
    # FIXME add adjustment and test
    def goto_prev_selection
      return if selected_rows().length == 0 
      row = selected_rows().sort{|a,b| b <=> a}.find { |i| i < @obj.current_index }
      row ||= @obj.current_index
      @obj.current_index = row
      @repaint_required = true # fire list_select XXX
    end
    # add the following range to selected items, unless already present
    # should only be used if multiple selection interval
    def add_selection_interval ix0, ix1
      return if @selection_mode != :multiple
      @anchor_selection_index = ix0
      @lead_selection_index = ix1
      ix0.upto(ix1) {|i| @selected_indices  << i unless @selected_indices.include? i
                     @obj.fire_row_changed i
      }
      lse = ListSelectionEvent.new(ix0, ix1, self, :INSERT)
      @obj.fire_handler :LIST_SELECTION_EVENT, lse
      #$log.debug " DLSM firing LIST_SELECTION EVENT #{lse}"
    end
    alias :add_row_selection_interval :add_selection_interval
    def remove_selection_interval ix0, ix1
      @anchor_selection_index = ix0
      @lead_selection_index = ix1
      @selected_indices.delete_if {|x| x >= ix0 and x <= ix1}
      lse = ListSelectionEvent.new(ix0, ix1, self, :DELETE)
      @obj.fire_handler :LIST_SELECTION_EVENT, lse
    end
    alias :remove_row_selection_interval :remove_selection_interval
    # convenience method to select next len rows
    def insert_index_interval ix0, len
      @anchor_selection_index = ix0
      @lead_selection_index = ix0+len
      add_selection_interval @anchor_selection_index, @lead_selection_index
    end
    # select all rows, you may specify starting row.
    # if header row, then 1 else should be 0. Actually we should have a way to determine
    # this, and the default should be zero.
    def select_all start_row=0 #+@_header_adjustment
      # don't select header row - need to make sure this works for all cases. we may 
      # need a variable instead of hardoded value
      add_row_selection_interval start_row, @obj.list.count()
    end
    def invert_selection start_row=0 #+@_header_adjustment
      start_row.upto(row_count()){|i| invert_row_selection i }
    end
     
    def invert_row_selection row=@obj.current_index
      @repaint_required = true
      if is_selected? row
        remove_row_selection_interval(row, row)
      else
        add_row_selection_interval(row, row) 
      end
    end
    # selects all rows with the values given, leaving existing selections
    # intact. Typically used after accepting search criteria, and getting a list of values
    # to select (such as file names). Will not work with tables (array or array)
    def select_values values
      return unless values
      values.each do |val|
        row = @list.index val
        add_row_selection_interval row, row unless row.nil?
      end
    end
    # unselects all rows with the values given, leaving all other rows intact
    # You can map "-" to ask_select and call this from there.
    #   bind_key(?+, :ask_select) # --> calls select_values
    #   bind_key(?-, :ask_unselect)
    def unselect_values values
      return unless values
      values.each do |val|
        row = @list.index val
        remove_row_selection_interval row, row unless row.nil?
      end
    end
    # please override this, this is just very basic and default
    # Please implement get_matching_indices(String).
    def ask_select prompt="Enter selection pattern: "
      ret = ask(prompt, String) {|q| yield q if block_given? }
      return if ret.nil? || ret ==  ""
      indices = get_matching_indices ret
      return if indices.nil? || indices.empty?
      indices.each { |e|
        # will not work if single select !! FIXME
        add_row_selection_interval e,e
      }
      @repaint_required = true
    end
    def get_matching_indices pattern
      alert "please implement this method get_matching_indices(pattern)->[] in your class  "
      return []
    end # mod
    # Applications may call this or just copy and modify

    ## 
    # bindings related to selection
    #
    def list_bindings
      # what about users wanting 32 and ENTER to also go to next row automatically
      # should make that optional, TODO
      @obj.bind_key($row_selector || 32, 'toggle selection') { toggle_row_selection }
      # 2013-03-24 - 14:46 added condition so single select does not get these
      if @selection_mode == :multiple
        @obj.bind_key(0, 'range select') { add_to_selection }
        @obj.bind_key(?+, :ask_select) # --> calls select_values
        @obj.bind_key(?-, :ask_unselect) # please implement FIXME TODO
        @obj.bind_key(?a, :select_all)
        @obj.bind_key(?*, :invert_selection)
        @obj.bind_key(?u, :clear_selection)
      end
      @_header_adjustment ||= 0 #  incase caller does not use
      #@obj._events << :LIST_SELECTION_EVENT unless @obj._events.include? :LIST_SELECTION_EVENT
    end
    def list_init_vars
      # uncommenting since link with obj will be broken
      #@selected_indices = []
      @selected_index = nil
      @old_selected_index = nil
      #@row_selected_symbol = ''
      if @show_selector
        @row_selected_symbol ||= '*'
        @row_unselected_symbol ||= ' '
        @left_margin ||= @row_selected_symbol.length
      end
    end
    # paint the selector. Called from repaint, prior to printing data row
    # remember to set left_margin at top of repaint method as:
    #    @left_margin ||= @row_selected_symbol.length
    def paint_selector crow, r, c, acolor, attrib
      selected = is_row_selected crow
      selection_symbol = ''
      if @show_selector
        if selected
          selection_symbol = @row_selected_symbol
        else
          selection_symbol =  @row_unselected_symbol
        end
        @graphic.printstring r, c, selection_symbol, acolor,attrib
      end
    end
    def selected_rows
      @selected_indices
    end
  end # class

  ## Takes care of rendering the list.
  # In the case of a List we take care of selected indices.
  # Also, focussed row is shown in bold, although we can make that optional and configurable
  # A user wanting a different rendering of listboxes may either extend this class
  # or completely replace it and set it as the renderer.
  class ListRenderer
    def initialize obj
      @obj = obj
      @selected_indices = obj.selected_indices
      @left_margin = obj.left_margin
    end
    #
    # @param pad for calling print methods on
    # @param lineno the line number on the pad to print on
    # @param text data to print
    def render pad, lineno, text
      sele = false
      bg = @obj.bgcolor
      fg = @obj.color
      att = NORMAL
      #cp = $datacolor
      cp = get_color($datacolor, fg, bg)
      if @selected_indices.include? lineno
        # print selected row in reverse
        sele = true
        fg = @obj.selected_color || fg
        bg = @obj.selected_bgcolor || bg
        att = @obj.selected_attr || REVERSE
        cp = get_color($datacolor, fg, bg)
      elsif lineno == @obj.current_index
        # print focussed row in bold
        att = BOLD
        # take current index into account as BOLD
        # and oldindex as normal
      end
      FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      FFI::NCurses.mvwaddstr(pad, lineno, @left_margin, text)
      FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)

      # the above only sets the attrib under the text not the whole line, we 
      # need the whole line to be REVERSE
      if sele
        FFI::NCurses.mvwchgat(pad, y=lineno, x=@left_margin, @obj.width-2, att, cp, nil)
      end
    end
  end
end # module
