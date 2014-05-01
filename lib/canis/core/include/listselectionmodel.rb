#!/usr/bin/env ruby -w
# ----------------------------------------------------------------------------- #
#         File: listselectionmodel.rb
#  Description: Used by textpad derivates to give selection of rows
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-04-10 - 21:04
#      License: Same as ruby license
#  Last update: 2014-05-01 01:10
# ----------------------------------------------------------------------------- #
#  listselectionmodel.rb  Copyright (C) 2012-2014 j kepler
# ----------------------------------------------------------------------------- #
#
require 'forwardable'

# The +DefaultListSelection+ mixin provides Textpad derived classes with
# selection methods and bindings.
# == Example
#  Inside the constructor of the multiline object use the following line, before the call to `super()`
#
#      self.extend DefaultListSelection
#      
# At any other portion, for example after the call to `super()` you may set the 
# default model if the user has not done so in the calling block
#
#      @list_selection_model ||= Canis::DefaultListSelectionModel.new self
# 
# When clearing data, as in `clear`, +selected_indices+ should also be cleared.
#
# == Note
#
#  This module does not take care of rendering a selected row. This must still be handled
#  by the default or custom renderer using `is_row_selected?`.
#
#  Note that changing the order of data, or deleting, inserting etc will not correct the selection
#  indices. Indices are assumed to be stable, and they may be cleared using `clear` on +@selected_indices+
#  if the data indices change.
#
module Canis
  extend self
  module DefaultListSelection
    def self.extended(obj)
      extend Forwardable
      # selection modes may be :multiple, :single or :none
      dsl_accessor :selection_mode
      # color of selected rows, and attribute of selected rows
      dsl_accessor :selected_color, :selected_bgcolor, :selected_attr
      # indices of selected rows
      dsl_accessor :selected_indices
      # model that takes care of selection operations
      dsl_accessor :list_selection_model
      #
      # all operations of selection are delegated to the ListSelectionModel
      def_delegators :@list_selection_model, :is_row_selected?, :toggle_row_selection, :select, :unselect, :is_selection_empty?, :clear_selection, :selected_rows, :select_all, :selected_values, :selected_value


      obj.instance_exec {
        @selected_indices = []
        @selection_mode = :multiple # default is multiple intervals
        #@list_selection_model = DefaultListSelectionModel.new obj
      }

    end
  end # mod DefaultListSelection
  # Whenever user selects one or more rows, this object is sent via event
  # giving start row and last row of selection, object
  # and type which is :INSERT :DELETE :CLEAR
  class ListSelectionEvent < Struct.new(:firstrow, :lastrow, :source, :type)
  end

  ##
  # Object that takes care of selection of rows.
  # This may be replace with a custom object at time of instantiation of list
  # Note that there are only two selection modes: single and multiple.
  # Multiple refers to multiple intervals. There is also a multiple row selection
  # mode, single interval, which only allows one range to be selected, much like a
  # text object, i.e. any text editor.
  #
  ## I am copying this from listselectable. that was a module so was included and shared variables
  # but now this is a class, and cannot access state as directly

  class DefaultListSelectionModel

    def initialize component
      raise "Components passed to DefaultListSelectionModel is nil" unless component
      @obj = component
    
      @selected_indices = @obj.selected_indices
      # in this case since it is called immediately upon extend, user cannot change this
      # Need a method to let user change after extending
      @selection_mode = @obj.selection_mode
      list_bindings
    end

    # change selection of current row on pressing space bar (or keybinding)
    # If mode is multiple, then this row is added to previous selections
    # @example
    #     bind_key(32) { toggle_row_selection }
    # 
    # 
    def toggle_row_selection crow=@obj.current_index
      @last_clicked = crow
      @repaint_required = true
      case @obj.selection_mode 
      when :multiple
        if @selected_indices.include? crow
          @selected_indices.delete crow
          lse = ListSelectionEvent.new(crow, crow, @obj, :DELETE)
          @obj.fire_handler :LIST_SELECTION_EVENT, lse
        else
          @selected_indices << crow
          lse = ListSelectionEvent.new(crow, crow, @obj, :INSERT)
          @obj.fire_handler :LIST_SELECTION_EVENT, lse
        end
      else
        # single - now change to use array only
        @selected_index = @selected_indices[0]
        if @selected_index == crow 
          @old_selected_index = @selected_index # 2011-10-15 so we can unhighlight
          @selected_index = nil
          @selected_indices.clear
          lse = ListSelectionEvent.new(crow, crow, @obj, :DELETE)
          @obj.fire_handler :LIST_SELECTION_EVENT, lse
        else
          @selected_indices[0] = crow
          @obj.fire_row_changed(@old_selected_index) if @old_selected_index
          @old_selected_index = crow # 2011-10-15 so we can unhighlight
          lse = ListSelectionEvent.new(crow, crow, @obj, :INSERT)
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
    # typically bound to Ctrl-Space (0)
    #
    # @example
    #
    #     bind_key(0) { range_select }
    #
    def range_select crow=@obj.current_index
      #alert "add to selection fired #{@last_clicked}"
      @last_clicked ||= crow
      min = [@last_clicked, crow].min
      max = [@last_clicked, crow].max
      case @obj.selection_mode 
      when :multiple
        if @selected_indices.include? crow
          # delete from last_clicked until this one in any direction
          min.upto(max){ |i| @selected_indices.delete i 
                         @obj.fire_row_changed i
          }
          lse = ListSelectionEvent.new(min, max, @obj, :DELETE)
          @obj.fire_handler :LIST_SELECTION_EVENT, lse
        else
          # add to selection from last_clicked until this one in any direction
          min.upto(max){ |i| @selected_indices << i unless @selected_indices.include?(i) 
                         @obj.fire_row_changed i
          }
          lse = ListSelectionEvent.new(min, max, @obj, :INSERT)
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
      lse = ListSelectionEvent.new(0, arr.size, @obj, :CLEAR)
      @obj.fire_handler :LIST_SELECTION_EVENT, lse
      arr = nil
    end

    # returns +true+ if given row has been selected
    # Now that we use only the array, the multiple check is good enough
    def is_row_selected? crow
      case @obj.selection_mode 
      when :multiple
        @selected_indices.include? crow
      else
        @selected_index = @selected_indices[0]
        crow == @selected_index
      end
    end
    alias :is_selected? is_row_selected?
   
    # after selecting, traverse selections forward
    def goto_next_selection
      return if selected_rows().length == 0 
      row = selected_rows().sort.find { |i| i > @obj.current_index }
      row ||= @obj.current_index
      #@obj.current_index = row
      @obj.goto_line row
    end
    
    # after selecting, traverse selections backward
    def goto_prev_selection
      return if selected_rows().length == 0 
      row = selected_rows().sort{|a,b| b <=> a}.find { |i| i < @obj.current_index }
      row ||= @obj.current_index
      #@obj.current_index = row
      @obj.goto_line row
    end
    # add the following range to selected items, unless already present
    # should only be used if multiple selection interval
    def add_row_selection_interval ix0, ix1
      return if @obj.selection_mode != :multiple
      @anchor_selection_index = ix0
      @lead_selection_index = ix1
      ix0.upto(ix1) {|i| 
                     @selected_indices  << i unless @selected_indices.include? i
                     @obj.fire_row_changed i
      }
      lse = ListSelectionEvent.new(ix0, ix1, @obj, :INSERT)
      @obj.fire_handler :LIST_SELECTION_EVENT, lse
      #$log.debug " DLSM firing LIST_SELECTION EVENT #{lse}"
    end

    # remove selected indices between given indices inclusive
    def remove_row_selection_interval ix0, ix1
      @anchor_selection_index = ix0
      @lead_selection_index = ix1
      arr = @selected_indices.dup # to un highlight
      @selected_indices.delete_if {|x| x >= ix0 and x <= ix1 }
      arr.each {|i| @obj.fire_row_changed(i) }
      lse = ListSelectionEvent.new(ix0, ix1, @obj, :DELETE)
      @obj.fire_handler :LIST_SELECTION_EVENT, lse
    end
    # convenience method to select next len rows
    def insert_index_interval ix0, len
      @anchor_selection_index = ix0
      @lead_selection_index = ix0+len
      add_row_selection_interval @anchor_selection_index, @lead_selection_index
    end
    # select all rows, you may specify starting row.
    # if header row, then 1 else should be 0. Actually we should have a way to determine
    # this, and the default should be zero.
    def select_all start_row=0 #+@_header_adjustment
      # don't select header row - need to make sure this works for all cases. we may 
      # need a variable instead of hardoded value
      add_row_selection_interval start_row, @obj.list.count()-1
    end

    # toggle selection of entire list
    # Requires application specific key binding
    def invert_selection start_row=0 #+@_header_adjustment
      start_row.upto(@obj.list.count()-1){|i| invert_row_selection i }
    end
     
    # toggles selection for given row
    # Typically called by invert_selection
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
    # TODO is this even needed, scrap
    def select_values values
      return unless values
      values.each do |val|
        row = @list.index val
        add_row_selection_interval row, row unless row.nil?
      end
    end
    # TODO is this even needed, scrap
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
    #
    # Asks user to enter a string or pattern for selecting rows
    # Selects rows based on pattern, leaving other selections as-is
    def ask_select prompt="Enter selection pattern: "
      ret = get_string prompt
      return if ret.nil? || ret ==  ""
      indices = get_matching_indices ret
      #$log.debug "listselectionmodel: ask_select got matches#{@indices} "
      return if indices.nil? || indices.empty?
      indices.each { |e|
        # will not work if single select !! FIXME
        add_row_selection_interval e,e
      }
    end
    # returns a list of matching indices using a simple regex match on given pattern
    # returns an empty list if no match
    def get_matching_indices pattern
      matches = []
      @obj.content.each_with_index { |e,i| 
        # convert to string for tables
        e = e.to_s unless e.is_a? String
        if e  =~ /#{pattern}/
          matches << i
        end
      }
      return matches
    end 
    # Asks user to enter a string or pattern for UNselecting rows
    # UNSelects rows based on pattern, leaving other selections as-is
    def ask_unselect prompt="Enter selection pattern: "
      ret = get_string prompt
      return if ret.nil? || ret ==  ""
      indices = get_matching_indices ret
      return if indices.nil? || indices.empty?
      indices.each { |e|
        # will not work if single select !! FIXME
        remove_row_selection_interval e,e
      }
    end

    ## 
    # bindings related to selection
    #
    def list_bindings
      # freeing space for paging, now trying out 'v' as selector. 2014-04-14 - 18:57 
      @obj.bind_key($row_selector || 'v'.ord, 'toggle selection') { toggle_row_selection }
      
      # the mode may be set to single after the constructor, so this would have taken effect.
      if @obj.selection_mode == :multiple
      # freeing ctrl_space for back paging, now trying out 'V' as selector. 2014-04-14 - 18:57 
        @obj.bind_key($range_selector || 'V'.ord, 'range select') { range_select }
        @obj.bind_key(?+, 'ask_select') { ask_select } 
        @obj.bind_key(?-, 'ask_unselect') { ask_unselect } 
        @obj.bind_key(?a, 'select_all') {select_all}
        @obj.bind_key(?*, 'invert_selection') { invert_selection }
        @obj.bind_key(?u, :clear_selection)
        @obj.bind_key([?g,?n], 'goto next selection'){ goto_next_selection } # mapping double keys like vim
        @obj.bind_key([?g,?p], 'goto prev selection'){ goto_prev_selection } # mapping double keys like vim
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
      ## FIXME we are not doing selectors at present. should we, else remove this
      if @show_selector
        @row_selected_symbol ||= '*'
        @row_unselected_symbol ||= ' '
        @left_margin ||= @row_selected_symbol.length
      end
    end
    # return the indices selected
    def selected_rows
      @selected_indices
    end
    # return the values selected
    def selected_values
      @obj.values_at(*@selected_indices)
    end
    # returns first selection, meant for convenience of single select listboxes
    # earlier called selected_item
    def selected_value
      return nil if @selected_indices.empty?
      @obj[@selected_indices.first]
      #selected_values.first
    end
  end # class
end # mod Canis
