#!/usr/bin/env ruby
# ----------------------------------------------------------------------------- #
#         File: listbox.rb
#  Description: A list box based on textpad
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 2014-04-06 - 19:37 
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-04-12 00:18
# ----------------------------------------------------------------------------- #
#   listbox.rb Copyright (C) 2012-2014 kepler

require 'logger'
require 'canis'
require 'canis/core/widgets/textpad'
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
#   [ ] selected_color - IMP we have no way of knowing what is selected right now
#   [ ] focussed color - this could be part of textpad too. row under cursor
#   [ ] rlist has menu actions that can use prompt menu or popup ?
#   [ ] move listselectionhandler into independent class so others can use, such as table
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
  #
  class Listbox < TextPad

    extend Forwardable

    # boolean, should a selector character be shown on the left of data for selected rows.
    dsl_property :show_selector
    # should textpads content_cols also add left_margin ? XXX
    dsl_property :left_margin


    # justify text to :left :right or :center TODO
    dsl_accessor :justify # will be picked up by renderer

    # should focussed line be shown in a different way, usually BOLD
    dsl_accessor :should_show_focus

    def initialize form = nil, config={}, &block

      @left_margin = 0
      @should_show_focus = true

      self.extend DefaultListSelection
      super
      # textpad takes care of enter_row and press
      @_events.push(*[:LEAVE_ROW, :LIST_SELECTION_EVENT])

      # if user has not specified a selection model, install default
      unless @selection_mode == :none
        unless @list_selection_model
          @list_selection_model = Canis::DefaultListSelectionModel.new self
        end
      end
      # if user has not specified a renderer, install default
      unless @renderer
        @renderer = ListRenderer.new self
      end
    end


    # http://www.opensource.apple.com/source/gcc/gcc-5483/libjava/javax/swing/table/DefaultTableColumnModel.java
    #
    # clear the list completely
    def clear
      @selected_indices.clear
      super
    end
    alias :remove_all :clear

    # This is called whenever user leaves a row
    # Fires handler for leave_row
    def on_leave_row arow
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

  end # class listbox


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
      # internal width based on both borders - earlier internal_width which we need
      @int_w = 3 
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
      # Strangely in testlistbox1 unselecting removes the entire lines REVERSE
      # but in testlistbox.rb the previous selected lines REV only partially goes
      # so we have to make the entire line in current attrib
      sele = true
      if sele
        FFI::NCurses.mvwchgat(pad, y=lineno, x=@left_margin, @obj.width - @left_margin - @int_w, att, cp, nil)
      end
    end
    # clear row before writing so previous contents are erased and don't show through
    # I could do this everytime i write but trying to make it faster
    # and only call this if +fire_row_changed+ is called.
    # @param - pad
    # @param - line number (index of row to clear)
    def clear_row pad, lineno
      clearstring = " " * (@obj.width - @left_margin - @int_w)
      FFI::NCurses.mvwaddstr(pad,lineno, @left_margin, clearstring) 
    end
  end
end # module
