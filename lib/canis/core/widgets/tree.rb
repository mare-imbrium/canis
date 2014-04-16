#!/usr/bin/env ruby
# header {{{
# vim: set foldlevel=0 foldmethod=marker :
# ----------------------------------------------------------------------------- #
#         File: tree.rb
#  Description: A tabular widget based on textpad
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 2014-04-16 13:56
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-04-17 00:33
# ----------------------------------------------------------------------------- #
#   tree.rb  Copyright (C) 2012-2014 kepler

# == CHANGES: 
#  - changed @content to @list since all multirow wids and utils expect @list
#  - changed name from tablewidget to table
#
# == TODO
#   [ ] if no columns, then init_model is called so chash is not cleared.
#   _ compare to tabular_widget and see what's missing
#   _ filtering rows without losing data
#   . selection stuff
#   x test with resultset from sqlite to see if we can use Array or need to make model
#     should we use a datamodel so resultsets can be sent in, what about tabular
#   _ header to handle events ?
#  header }}}

require 'logger'
require 'canis'
require 'canis/core/widgets/textpad'

## 
# The motivation to create yet another table widget is because tabular_widget
# is based on textview etc which have a lot of complex processing and rendering
# whereas textpad is quite simple. It is easy to just add one's own renderer
# making the code base simpler to understand and maintain.
#
#
module Canis
# structures {{{
  TreeSelectionEvent = Struct.new(:node, :tree, :state, :previous_node, :row_first)
# structures }}}
    # renderer {{{
  #
  # TODO see how jtable does the renderers and columns stuff.
  #
  # perhaps we can combine the two but have different methods or some flag
  # that way oter methods can be shared
    class DefaultTreeRenderer

      PLUS_PLUS = "++"
      PLUS_MINUS = "+-"
      PLUS_Q     = "+?"
      # source is the textpad or extending widget needed so we can call show_colored_chunks
      # if the user specifies column wise colors
      def initialize source
        @source = source
        @color = :white
        @bgcolor = :black
        @color_pair = $datacolor
        @attrib = NORMAL
        @_check_coloring = nil
        # adding setting column_model auto on 2014-04-10 - 10:53 why wasn;t this here already
        #tree_model(source.tree_model)
      end
      # set fg and bg color of content rows, default is $datacolor (white on black).
      def content_colors fg, bg
        @color = fg
        @bgcolor = bg
        @color_pair = get_color($datacolor, fg, bg)
      end
      def content_attrib att
        @attrib = att
      end
      #
      # @param pad for calling print methods on
      # @param lineno the line number on the pad to print on
      # @param text data to print
      def render pad, lineno, treearraynode
        parent = @source
        level = treearraynode.level
        node = treearraynode
        if parent.node_expanded? node
          icon = PLUS_MINUS  # can collapse
        else
          icon = PLUS_PLUS   # can expand
        end
        if node.children.size == 0
          icon = PLUS_Q # either no children or not visited yet
          if parent.has_been_expanded node
            icon = PLUS_MINUS # definitely no children, we've visited
          end
        end
        # adding 2 to level, that's the size of icon
        # XXX FIXME if we put the icon here, then when we scroll right, the icon will show, it shoud not
        # FIXME we ignore truncation etc on previous level and take the object as is !!!
        _value =  "%*s %s" % [ level+2, icon,  node.user_object ]
        len =  _value.length
        #graphic.printstring r, c, "%-*s" % [len, _value], @color_pair,@attr
        cp = @color_pair
        att = @attrib
        # added for selection, but will crash if selection is not extended !!! XXX
          if @source.is_row_selected? lineno
            att = REVERSE
            # FIXME currentl this overflows into next row
          end
        
        FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
        FFI::NCurses.mvwaddstr(pad, lineno, 0, _value)
        FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)

      end
      # check if we need to individually color columns or we can do the entire
      # row in one shot
    end
# renderer }}}

    #--
  # If we make a pad of the whole thing then the columns will also go out when scrolling
  # So then there's no point storing columns separately. Might as well keep in content
  # so scrolling works fine, otherwise textpad will have issues scrolling.
  # Making a pad of the content but not column header complicates stuff,
  # do we make a pad of that, or print it like the old thing.
    #++
    # A table widget containing rows and columns and the ability to resize and hide or align
    # columns. Also may have first row as column names.
    #
    # == NOTE
    #   The most important methods to use probably are `text()` or `resultset` or `filename` to load
    #   data. With `text` you will want to first specify column names with `columns()`.
    #
    #   +@current_index+ inherited from +Textpad+ continues to be the index of the list that has user's
    #   focus, and should be used for row operations.
    #
    #   In order to use Textpad easily, the first row of the table model is the column names. Data is maintained
    #   in an Array. Several operations are delegated to Array, or have the same name. You can get the list 
    #   using `list()` to run other Array operations on it.
    #
    #   If you modify the Array directly, you may have to use `fire_row_changed(index)` to reflect the update to 
    #   a single row. If you delete or add a row, you will have to use `fire_dimension_changed()`. However,
    #   internal functions do this automatically.
    #
    #require 'canis/core/include/listselectionmodel'
    require 'canis/core/widgets/tree/treemodel'
  class Tree < TextPad

    dsl_accessor :print_footer
    attr_reader :treemodel        # returns treemodel for further actions 2011-10-2 
    dsl_accessor :default_value  # node to show as selected - what if user doesn't have it?

    def initialize form = nil, config={}, &block

      @_header_adjustment = 0 #1
      @col_min_width = 3

      @expanded_state = {}
      super
      @_events.push(*[:ENTER_ROW, :LEAVE_ROW, :TREE_COLLAPSED_EVENT, :TREE_EXPANDED_EVENT, :TREE_SELECTION_EVENT, :TREE_WILL_COLLAPSE_EVENT, :TREE_WILL_EXPAND_EVENT])
      create_default_renderer unless @renderer # 2014-04-10 - 11:01 
      init_vars
      #set_default_selection_model unless @list_selection_model
    end

    # set the default selection model as the operational one
    def set_default_selection_model
      @list_selection_model = nil
      @list_selection_model = Canis::DefaultListSelectionModel.new self
    end
    def create_default_renderer
      renderer( DefaultTreeRenderer.new(self) )
    end
    def init_vars
      if @show_selector
        @row_selected_symbol ||= '>'
        @row_unselected_symbol ||= ' '
        @left_margin ||= @row_selected_symbol.length
      end
      @left_margin ||= 0
      #@one_key_selection = true if @one_key_selection.nil?
      @row_offset = @col_offset = 0 if @suppress_borders
      @internal_width = 2 # taking into account borders accounting for 2 cols
      @internal_width = 0 if @suppress_borders # should it be 0 ???
      super

    end
    # maps keys to methods
    # checks @key_map can be :emacs or :vim.
    def map_keys
      super
      @keys_mapped = true
      bind_key($row_selector, 'toggle row selection'){ toggle_row_selection() }
      bind_key(KEY_ENTER, 'toggle expanded state') { toggle_expanded_state() }
      bind_key(?o, 'toggle expanded state') { toggle_expanded_state() }
      bind_key(?f, 'first row starting with char'){ ask_selection_for_char() }
      #bind_key(?\M-v, 'one key selection toggle'){ @one_key_selection = !@one_key_selection }
      bind_key(?O, 'expand children'){ expand_children() }
      bind_key(?X, 'collapse children'){ collapse_children() }
      bind_key(?>, :scroll_right)
      bind_key(?<, :scroll_left)
      # TODO
      bind_key(?x, 'collapse parent'){ collapse_parent() }
      bind_key(?p, 'goto parent'){ goto_parent() }
      # this can be brought back into include and used from other textpad too.
      require 'canis/core/include/deprecated/listbindings'
      #ListBindings.bindings
      bindings
    end
    # Returns root if no argument given.
    # Now we return root if already set
    # Made node nillable so we can return root. 
    #
    # @raise ArgumentError if setting a root after its set
    #   or passing nil if its not been set.
    def root node=nil, asks_allow_children=false, &block
      if @treemodel
        return @treemodel.root unless node
        raise ArgumentError, "Root already set"
      end

      raise ArgumentError, "root: node cannot be nil" unless node
      @treemodel = Canis::DefaultTreeModel.new(node, asks_allow_children, &block)
    end

    # pass data to create this tree model
    # used to be list
    def data alist=nil

      # if nothing passed, print an empty root, rather than crashing
      alist = [] if alist.nil?
      @data = alist # data given by user
      case alist
      when Array
        @treemodel = Canis::DefaultTreeModel.new("/")
        @treemodel.root.add alist
      when Hash
        @treemodel = Canis::DefaultTreeModel.new("/")
        @treemodel.root.add alist
      when TreeNode
        # this is a root node
        @treemodel = Canis::DefaultTreeModel.new(alist)
      when DefaultTreeModel
        @treemodel = alist
      else
        if alist.is_a? DefaultTreeModel
          @treemodel = alist
        else
          raise ArgumentError, "Tree does not know how to handle #{alist.class} "
        end
      end
      # we now have a tree
      raise "I still don't have a tree" unless @treemodel
      set_expanded_state(@treemodel.root, true)
      convert_to_list @treemodel
      
      # added on 2009-01-13 23:19 since updates are not automatic now
      #@list.bind(:LIST_DATA_EVENT) { |e| list_data_changed() }
      #create_default_list_selection_model TODO
      fire_dimension_changed
      self
    end
    # private, for use by repaint
    def _list
      if @_structure_changed 
        @list = nil
        @_structure_changed = false
      end
      unless @list
        $log.debug " XXX recreating _list"
        convert_to_list @treemodel
        $log.debug " XXXX list: #{@list.size} : #{@list} "
      end
      return @list
    end
    # repaint whenever a change heppens
    # 2014-04-16 - 22:31 - I need to put a call to _list somewhere whenever a change happens
    # (i.e. recreate list from the tree model object)..
    def repaint
      # we need to see if structure changed then regenerate @list
      _list()
      super
    end
    def convert_to_list tree
      @list = get_expanded_descendants(tree.root)
      #$log.debug "XXX convert #{tree.root.children.size} "
      #$log.debug " converted tree to list. #{@list.size} "
    end
    def traverse node, level=0, &block
      raise "disuse"
      #icon = node.is_leaf? ? "-" : "+"
      #puts "%*s %s" % [ level+1, icon,  node.user_object ]
      yield node, level if block_given?
      node.children.each do |e| 
        traverse e, level+1, &block
      end
    end
    # return object under cursor
    # Note: this should not be confused with selected row/s. User may not have selected this.
    # This is only useful since in some demos we like to change a status bar as a user scrolls down
    # @since 1.2.0  2010-09-06 14:33 making life easier for others.
    def current_row
      @list[@current_index]
    end
    alias :text :current_row  # thanks to shoes, not sure how this will impact since widget has text.

    # show default value as selected and fire handler for it
    # This is called in repaint, so can raise an error if called on creation
    # or before repaint. Just set @default_value, and let us handle the rest.
    # Suggestions are welcome.
    def select_default_values
      return if @default_value.nil?
      # NOTE list not yet created
      raise "list has not yet been created" unless @list
      index = node_to_row @default_value
      raise "could not find node #{@default_value}, #{@list}  " unless index
      return unless index
      @current_index = index
      toggle_row_selection
      @default_value = nil
    end
    ### START FOR scrollable ###
    def get_content
      #@list 2008-12-01 23:13 
      @list_variable && @list_variable.value || @list 
      # called by next_match in listscrollable
      @list
    end
    def get_window
      @graphic 
    end
    ### END FOR scrollable ###
    # override widgets text
    def getvalue
      selected_row()
    end
    
    # supply a custom renderer that implements +render()+
    # @see render
    def renderer r
      @renderer = r
    end


    #------- data modification methods ------#


#

    ## add a row to the table
    # The name add will be removed soon, pls use << instead.
    def <<( array)
      unless @list
        # columns were not added, this most likely is the title
        @list ||= []
        _init_model array
      end
      @list << array
      fire_dimension_changed
      self
    end

    # delete a data row at index 
    #
    # NOTE : This does not adjust for header_adjustment. So zero will refer to the header if there is one.
    #   This is to keep consistent with textpad which does not know of header_adjustment and uses the actual
    #   index. Usually, programmers will be dealing with +@current_index+
    #
    def delete_at ix
      return unless @list
      raise ArgumentError, "Argument must be within 0 and #{@list.length}" if ix < 0 or ix >=  @list.length 
      fire_dimension_changed
      #@list.delete_at(ix + @_header_adjustment)
      @list.delete_at(ix)
    end
    
    ##
    # refresh pad onto window
    # overrides super due to header_adjustment and the header too
    def XXXpadrefresh
      top = @window.top
      left = @window.left
      sr = @startrow + top
      sc = @startcol + left
      # first do header always in first row
      retval = FFI::NCurses.prefresh(@pad,0,@pcol, sr , sc , 2 , @cols+ sc );
      # now print rest of data
      # h is header_adjustment
      h = 1 
      retval = FFI::NCurses.prefresh(@pad,@prow + h,@pcol, sr + h , sc , @rows + sr  , @cols+ sc );
      $log.warn "XXX:  PADREFRESH #{retval}, #{@prow}, #{@pcol}, #{sr}, #{sc}, #{@rows+sr}, #{@cols+sc}." if retval == -1
      # padrefresh can fail if width is greater than NCurses.COLS
    end

    # print footer containing line and total, overriding textpad which prints column offset also
    # This is called internally by +repaint()+ but can be overridden for more complex printing.
    def print_foot
      return unless @print_footer
      ha = @_header_adjustment
      # ha takes into account whether there are headers or not
      footer = "#{@current_index+1-ha} of #{@list.length-ha} "
      @graphic.printstring( @row + @height -1 , @col+2, footer, @color_pair || $datacolor, @footer_attrib) 
      @repaint_footer_required = false 
    end
    def is_row_selected? row=@current_index
      row == @selected_index
    end
    def selected_row
      @list[@selected_index].node
    end

    # An event is thrown when a row is selected or deselected.
    # Please note that when a row is selected, another one is automatically deselected.
    # An event is not thrown for that since your may not want to collapse that.
    # Only clicking on a selected row, will send a DESELECT on it since you may want to collapse it.
    # However, the previous selection is also present in the event object, so you can act upon it.
    # This is not used for expanding or collapsing, only for application to show some data in another
    # window or pane based on selection. Maybe there should not be a deselect for current row ?
    def toggle_row_selection
      node = @list[@current_index]
      previous_node = nil
      previous_node = @list[@selected_index] if @selected_index
      previous_index = nil
      if @selected_index == @current_index
        @selected_index = nil
        previous_index = @current_index
      else
        previous_index = @selected_index
        @selected_index = @current_index
      end
      state = @selected_index.nil? ? :DESELECTED : :SELECTED
      #TreeSelectionEvent = Struct.new(:node, :tree, :state, :previous_node, :row_first)
      @tree_selection_event = TreeSelectionEvent.new(node, self, state, previous_node, @current_index) #if @item_event.nil?
      fire_handler :TREE_SELECTION_EVENT, @tree_selection_event # should the event itself be ITEM_EVENT
      $log.debug " XXX tree selected #{@selected_index}/ #{@current_index} , #{state} "
      fire_row_changed @current_index if @current_index
      fire_row_changed previous_index if previous_index
      @repaint_required = true
    end
    def toggle_expanded_state row=@current_index
      state = row_expanded? row
      node  = row_to_node
      if node.nil?
        Ncurses.beep
        $log.debug " No such node on row #{row} "
        return
      end
      $log.debug " toggle XXX state #{state} #{node} "
      if state
        collapse_node node
      else
        expand_node node
      end
    end
    def row_to_node row=@current_index
      @list[row]
    end
    # convert a given node to row
    def node_to_row node
      crow = nil
      @list.each_with_index { |e,i| 
        if e == node
          crow = i
          break
        end
      }
      crow
    end
    # private
    # related to index in representation, not tree
    def row_selected? row
      @selected_index == row
    end
    # @return [TreeNode, nil] returns selected node or nil
 
    def row_expanded? row
      node = @list[row]
      node_expanded? node
    end
    def row_collapsed? row
      !row_expanded? row
    end
    def set_expanded_state(node, state)
      @expanded_state[node] = state
      @repaint_required = true
      _structure_changed true
    end
    def expand_node(node)
      #$log.debug " expand called on #{node.user_object} "
      state = true
      fire_handler :TREE_WILL_EXPAND_EVENT, node
      set_expanded_state(node, state)
      fire_handler :TREE_EXPANDED_EVENT, node
    end
    def collapse_node(node)
      $log.debug " collapse called on #{node.user_object} "
      state = false
      fire_handler :TREE_WILL_COLLAPSE_EVENT, node
      set_expanded_state(node, state)
      fire_handler :TREE_COLLAPSED_EVENT, node
    end
    # this is required to make a node visible, if you wish to start from a node that is not root
    # e.g. you are loading app in a dir somewhere but want to show path from root down.
    # NOTE this sucks since you have to click 2 times to expand it.
    def mark_parents_expanded node
      # i am setting parents as expanded, but NOT firing handlers - XXX separate this into expand_parents
      _path = node.tree_path
      _path.each do |e| 
        # if already expanded parent then break we should break
        set_expanded_state(e, true) 
      end
    end
    # goes up to root of this node, and expands down to this node
    # this is often required to make a specific node visible such 
    # as in a dir listing when current dir is deep in heirarchy.
    def expand_parents node
      _path = node.tree_path
      _path.each do |e| 
        # if already expanded parent then break we should break
        #set_expanded_state(e, true) 
        expand_node(e)
      end
    end
    # this expands all the children of a node, recursively
    # we can't use multiplier concept here since we are doing a preorder enumeration
    # we need to do a breadth first enumeration to use a multiplier
    #
    def expand_children node=:current_index
      $multiplier = 999 if !$multiplier || $multiplier == 0
      node = row_to_node if node == :current_index
      return if node.children.empty? # or node.is_leaf?
      #node.children.each do |e| 
        #expand_node e # this will keep expanding parents
        #expand_children e
      #end
      node.breadth_each($multiplier) do |e|
        expand_node e
      end
      $multiplier = 0
      _structure_changed true
    end
    def collapse_children node=:current_index
      $multiplier = 999 if !$multiplier || $multiplier == 0
      $log.debug " CCCC IINSIDE COLLLAPSE"
      node = row_to_node if node == :current_index
      return if node.children.empty? # or node.is_leaf?
      #node.children.each do |e| 
        #expand_node e # this will keep expanding parents
        #expand_children e
      #end
      node.breadth_each($multiplier) do |e|
        $log.debug "CCC collapsing #{e.user_object}  "
        collapse_node e
      end
      $multiplier = 0
      _structure_changed true
    end
    # collapse parent
    # can use multiplier.
    # # we need to move up also
    def collapse_parent node=:current_index
      node = row_to_node if node == :current_index
      parent = node.parent
      return if parent.nil?
      goto_parent node
      collapse_node parent
    end
    def goto_parent node=:current_index
      node = row_to_node if node == :current_index
      parent = node.parent
      return if parent.nil?
      crow = @current_index
      @list.each_with_index { |e,i| 
        if e == parent
          crow = i
          break
        end
      }
      @repaint_required = true
      #set_form_row  # will not work if off form
      set_focus_on crow
    end

    def has_been_expanded node
      @expanded_state.has_key? node
    end
    def node_expanded? node
      @expanded_state[node] == true
    end
    def node_collapsed? node
      !node_expanded?(node)
    end
    def get_expanded_descendants(node)
      nodes = []
      nodes << node
      traverse_expanded node, nodes
      $log.debug " def get_expanded_descendants(node) #{nodes.size} "
      return nodes
    end
    def traverse_expanded node, nodes
      return if !node_expanded? node
      #nodes << node
      node.children.each do |e| 
        nodes << e
        if node_expanded? e
          traverse_expanded e, nodes
        else
          next
        end
      end
    end

    #
    # To retrieve the node corresponding to a path specified as an array or string
    # Do not mention the root.
    # e.g. "ruby/1.9.2/io/console"
    # or %w[ ruby 1.9.3 io console ]
    # @since 1.4.0 2011-10-2 
    def get_node_for_path(user_path)
      case user_path
      when String
        user_path = user_path.split "/"
      when Array
      else
        raise ArgumentError, "Should be Array or String delimited with /"
      end
      $log.debug "TREE #{user_path} " if $log.debug? 
      root = @treemodel.root
      found = nil
      user_path.each { |e| 
        success = false
        root.children.each { |c| 
          if c.user_object == e
            found = c
            success = true
            root = c
            break
          end
        }
        return false unless success

      }
      return found
    end
    # default block
    # @since 1.5.0 2011-11-22 
    def command *args, &block
      bind :TREE_WILL_EXPAND_EVENT, *args, &block
    end
    private
    # please do not rely on this yet, name could change
    def _structure_changed tf=true
      @_structure_changed = tf
      @repaint_required = true
      fire_dimension_changed
      #@list = nil
    end

  end # class Table

end # module
