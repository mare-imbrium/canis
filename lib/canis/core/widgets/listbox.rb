#!/usr/bin/env ruby
# ----------------------------------------------------------------------------- #
#         File: listbox.rb
#  Description: A list box based on textpad
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 2014-04-06 - 19:37 
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-07-07 00:36
# ----------------------------------------------------------------------------- #
#   listbox.rb Copyright (C) 2012-2014 kepler

require 'canis'
require 'forwardable'
require 'canis/core/include/listselectionmodel'
## 
# A listbox based on textpad. 
# Contains a scrollable array of Strings. The list is selectable too.
# In place editing is not provided, however editing in a separate box
# has been implemented in various examples.
# Essentially, the listbox only adds selection to the textpad.
# TODO
# ----
#   [ ] focussed_color - this could be part of textpad too. row under cursor
#   [ ] rlist has menu actions that can use prompt menu or popup ?
#   [ ] nothing has been done about show_selector -- consider whether to knock off
#
#
# CHANGES
# -------
# - removed Array operations to Textpad, some renaming 2014-04-10 - 20:50 
#
#
module Canis

  ##
  # A scrollable, selectable array of strings.
  # Delegates display to ListRenderer
  # Delegates selection to Defaultlistselection (/include/listselectionmodel.rb)
  # Due to extending Defaultlistselection, methods are not visible here.
  # Selection methods are (the first three are what programmers will use the most):
  #
  #    -  `selected_values` : returns values selecteda (multiple selection)
  #    -  `selected_value`  : returns value of row selected (single selection)
  #    -  `selected_rows`   : same as selected_indices, indices of selected items
  #
  #    -  `toggle_row_selection` : toggles current row, called by key $row_selector
  #    -  `select`               : select given or current row
  #    -  `unselect`             : unselects given or current row
  #    -  `is_row_selected?`     : determine if given row is selected
  #    -  `is_selection_empty?`  : has anything been selected
  #    -  `clear_selection`      : clear selection
  #    -  `select_all`           : select all rows
  #
  # Listbox also fires a ListSelectionEvent whose type can be:
  #
  #    - :INSERT , a row or rows added to selection
  #    - :DELETE , a row or rows removed from selection
  #    - :CLEAR , all selection cleared
  #
  # == Examples
  #
  #    mylist = %w[john tim matz shougo _why sean aaron]
  #    l = Listbox.new @form, :row => 5, :col => 4, :height => 10, :width => 20, :list => mylist
  # 
  # Inside a Flow:
  #
  #   lb = listbox :list => mylist, :title => 'Contacts', :width_pc => 50, :selection_mode => :single
  #
  class Listbox < TextPad

    extend Forwardable

    # boolean, should a selector character be shown on the left of data for selected rows.
    dsl_property :show_selector
    # should textpads content_cols also add left_margin ? XXX
    # how much space to leave on left, currently 0, was used with selector character once
    dsl_property :left_margin

    # justify text to :left :right or :center (renderer to take care of this).
    dsl_accessor :justify

    # should focussed line be shown in a different way, currently BOLD, default true
    dsl_accessor :should_show_focus

    def initialize form = nil, config={}, &block

      @left_margin = 0
      @should_show_focus = true

      register_events([:LEAVE_ROW, :LIST_SELECTION_EVENT])
      self.extend DefaultListSelection
      super
      # textpad takes care of enter_row and press
      #@_events.push(*[:LEAVE_ROW, :LIST_SELECTION_EVENT])
      bind_key(?f, 'next row starting with char'){ set_selection_for_char(nil) }

      # if user has not specified a selection model, install default
      unless @selection_mode == :none
        unless @list_selection_model
          create_default_selection_model
        end
      end
      # if user has not specified a renderer, install default
      unless @renderer
        create_default_renderer
      end
    end
    # create a default renderer since user has not specified
    # Widgets inheriting this with a differernt rendering such as tree
    # can overrider this.
    def create_default_renderer
      r = ListRenderer.new self
      renderer(r)
    end
    def renderer *val
      if val.empty?
        return @renderer
      end
      @renderer = val[0]
    end
    # create a default selection model
    # Widgets inheriting this may override this
    def create_default_selection_model
      list_selection_model(Canis::DefaultListSelectionModel.new self)
    end


    # http://www.opensource.apple.com/source/gcc/gcc-5483/libjava/javax/swing/table/DefaultTableColumnModel.java
    #
    # clear the list completely of data, including selections
    def clear
      @selected_indices.clear
      super
    end
    alias :remove_all :clear

    # This is called whenever user leaves a row
    # Fires handler for leave_row
    def on_leave_row arow
      # leave this out, since we are not painting on exit of widget 2014-07-02 - 17:51 
      #if @should_show_focus
        #fire_row_changed arow
      #end
      fire_handler :LEAVE_ROW, self
    end
    # This is called whenever user enters a row
    def on_enter_row arow
      super
      # TODO check if user wants focus to be showed
      ## this results in the row being entered and left being evaluated and repainted
      # which means that the focussed row can be bolded. The renderer's +render+ method will be triggered
      if @should_show_focus
        fire_row_changed @oldindex
        fire_row_changed arow
      end
    end
    #def on_leave
      #super
      #on_leave_row @current_index if @current_index
    #end
    # get a char ensure it is a char or number
    # In this state, it could accept control and other chars.
    private
    def _ask_a_char
      ch = @graphic.getch
      #message "achar is #{ch}"
      if ch < 26 || ch > 255
        @graphic.ungetch ch
        return :UNHANDLED
      end
      return ch.chr
    end
    public
    # sets the selection to the next row starting with char
    # Trying to return unhandled is having no effect right now. if only we could pop it into a
    # stack or unget it.
    def set_selection_for_char char=nil
      char = _ask_a_char unless char
      return :UNHANDLED if char == :UNHANDLED
      #alert "got #{char}"
      @oldrow = @current_index
      @last_regex = /^#{char}/i
      ix = next_regex @last_regex
      return unless ix
      @current_index = ix[0] 
      #alert "curr ind #{@current_index} "
      @search_found_ix = @current_index
      @curpos = ix[1]
      ensure_visible
      return @current_index
    end
    # Find the next row that contains given string
    # @return row and col offset of match, or nil
    # @param String to find
    def  next_regex str
      first = nil
      ## content can be string or Chunkline, so we had to write <tt>index</tt> for this.
      ## =~ does not give an error, but it does not work.
      @list.each_with_index do |line, ix|
        col = line =~ /#{str}/
        if col
          first ||= [ ix, col ]
          if ix > @current_index
            return [ix, col]
          end
        end
      end
      return first
    end

  end # class listbox


  ## Takes care of rendering the list.
  # In the case of a List we take care of selected indices.
  # Also, focussed row is shown in bold, although we can make that optional and configurable
  # A user wanting a different rendering of listboxes may either extend this class
  # or completely replace it and set it as the renderer.
  class ListRenderer < AbstractTextPadRenderer
    # text to be placed in the left margin. This requires that a left margin be set in the source
    # object.
    attr_accessor :left_margin_text
    attr_accessor :row_focussed_attr

    def initialize source
      @source = source
      # internal width based on both borders - earlier internal_width which we need
      @int_w = 3 
      # 3 leaves a blank black in popuplists as in testlistbox.rb F4
      # setting it as 2 means that in some cases, the next line first character
      #   gets overwritten with traversal
      #@int_w = 2 
    end
    # This is called prior to render_all, and may not be called when a single row is rendered
    #  as in fire_row_changed
    def pre_render
      super
      @selected_indices = @source.selected_indices
      @left_margin = @source.left_margin
      @bg = @source.bgcolor
      @fg = @source.color
      @attr = NORMAL
      @row_focussed_attr ||= $row_focussed_attr
    end

    #
    # @param pad for calling print methods on
    # @param lineno the line number on the pad to print on
    # @param text data to print
    #--
    # NOTE: in some cases like testlistbox.rb if a line is updated then the newly printed
    # value may not overwrite the entire line, addstr seems to only write the text no more
    # Fixed with +clear_row+ 
    #++
    def render pad, lineno, text
      sele = false
=begin
      bg = @source.bgcolor
      fg = @source.color
      att = NORMAL
      cp = get_color($datacolor, fg, bg)
=end
      bg = @bg || @source.bgcolor
      fg = @fg || @source.color
      att = @attr || NORMAL
      cp = get_color($datacolor, fg, bg)

      if @selected_indices.include? lineno
        # print selected row in reverse
        sele = true
        fg = @source.selected_color || fg
        bg = @source.selected_bgcolor || bg
        att = @source.selected_attr || REVERSE
        cp = get_color($datacolor, fg, bg)
      elsif lineno == @source.current_index 
        # print focussed row in different attrib
        if @source.should_show_focus
          # bold was supposed to be if the object loses focus, but although render is called
          #  however, padrefresh is not happening since we do not paint on exiting a widget
          att = BOLD
          if @source.focussed
            att = @row_focussed_attr 
          end
        end
        # take current index into account as BOLD
        # and oldindex as normal
      end
      FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      FFI::NCurses.mvwaddstr(pad, lineno, 0, @left_margin_text) if @left_margin_text
      FFI::NCurses.mvwaddstr(pad, lineno, @left_margin, text)
      FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)

      # the above only sets the attrib under the text not the whole line, we 
      # need the whole line to be REVERSE
      # Strangely in testlistbox1 unselecting removes the entire lines REVERSE
      # but in testlistbox.rb the previous selected lines REV only partially goes
      # so we have to make the entire line in current attrib
      sele = true
      if sele
        FFI::NCurses.mvwchgat(pad, y=lineno, x=@left_margin, @source.width - @left_margin - @int_w, att, cp, nil)
      end
    end
    # clear row before writing so previous contents are erased and don't show through
    # I could do this everytime i write but trying to make it faster
    # and only call this if +fire_row_changed+ is called.
    # NOTE: in clear_row one is supposed to clear to the width of the pad, not window
    #   otherwise on scrolling you might get black bg if you have some other color bg.
    #   This is mostly important if you have a bgcolor that is different from the terminal
    #   bgcolor.
    # @param - pad
    # @param - line number (index of row to clear)
    def _clear_row pad, lineno
      raise "unused"
      @color_pair ||= get_color($datacolor, @source.color, @source.bgcolor)
      cp = @color_pair
      att = NORMAL
      @_clearstring ||= " " * (@source.width - @left_margin - @int_w)
      # with int_w = 3 we get that one space in popuplist
      # added attr on 2014-05-02 - 00:16 otherwise a list inside a white bg messagebox shows
      # empty rows in black bg.
      FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      FFI::NCurses.mvwaddstr(pad,lineno, @left_margin, @_clearstring) 
      FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
    end
  end
end # module
