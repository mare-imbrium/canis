#!/usr/bin/env ruby
# header {
# vim: set foldmarker={,} foldlevel=0 foldmethod=marker :
# ----------------------------------------------------------------------------- #
#         File: table.rb
#  Description: A tabular widget based on textpad
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 2013-03-29 - 20:07
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-04-13 22:58
# ----------------------------------------------------------------------------- #
#   table.rb  Copyright (C) 2012-2014 kepler

# == CHANGES: 
#  - changed @content to @list since all multirow wids and utils expect @list
#  - changed name from tablewidget to table
#
# == TODO
#   _ compare to tabular_widget and see what's missing
#   _ filtering rows without losing data
#   . selection stuff
#   x test with resultset from sqlite to see if we can use Array or need to make model
#     should we use a datamodel so resultsets can be sent in, what about tabular
#   _ header to handle events ?
#  header }

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
# structures {
  # column data, one instance for each column
  # index is the index in the data of this column. This index will not change.
  # Order of printing columns is determined by the ordering of the objects.
  class ColumnInfo < Struct.new(:name, :index, :offset, :width, :align, :hidden, :attrib, :color, :bgcolor)
  end
  # a structure that maintains position and gives
  # next and previous taking max index into account.
  # it also circles. Can be used for traversing next component
  # in a form, or container, or columns in a table.
  class Circular < Struct.new(:max_index, :current_index)
    attr_reader :last_index
    attr_reader :current_index
    def initialize  m, c=0
      raise "max index cannot be nil" unless m
      @max_index = m
      @current_index = c
      @last_index = c
    end
    def next
      @last_index = @current_index
      if @current_index + 1 > @max_index
        @current_index = 0
      else
        @current_index += 1
      end
    end
    def previous
      @last_index = @current_index
      if @current_index - 1 < 0
        @current_index = @max_index
      else
        @current_index -= 1
      end
    end
    def is_last?
      @current_index == @max_index
    end
  end
# structures }
# sorter {
    # This is our default table row sorter.
    # It does a multiple sort and allows for reverse sort also.
    # It's a pretty simple sorter and uses sort, not sort_by.
    # Improvements welcome.
    # Usage: provide model in constructor or using model method
    # Call toggle_sort_order(column_index) 
    # Call sort. 
    # Currently, this sorts the provided model in-place. Future versions
    # may maintain a copy, or use a table that provides a mapping of model to result.
    # # TODO check if column_sortable
    class DefaultTableRowSorter
      attr_reader :sort_keys
      # model is array of data
      def initialize data_model=nil
        self.model = data_model
        @columns_sort = []
        @sort_keys = nil
      end
      def model=(model)
        @model = model
        @sort_keys = nil
      end
      def sortable colindex, tf
        @columns_sort[colindex] = tf
      end
      def sortable? colindex
        return false if @columns_sort[colindex]==false
        return true
      end
      # should to_s be used for this column
      def use_to_s colindex
        return true # TODO
      end
      # sorts the model based on sort keys and reverse flags
      # @sort_keys contains indices to sort on
      # @reverse_flags is an array of booleans, true for reverse, nil or false for ascending
      def sort
        return unless @model
        return if @sort_keys.empty?
        $log.debug "TABULAR SORT KEYS #{sort_keys} "
        # first row is the header which should remain in place
        # We could have kept column headers separate, but then too much of mucking around
        # with textpad, this way we avoid touching it
        header = @model.delete_at 0
        begin
          # next line often can give error "array within array" - i think on date fields that 
          #  contain nils
        @model.sort!{|x,y| 
          res = 0
          @sort_keys.each { |ee| 
            e = ee.abs-1 # since we had offsetted by 1 earlier
            abse = e.abs
            if ee < 0
              xx = x[abse]
              yy = y[abse]
              # the following checks are since nil values cause an error to be raised
              if xx.nil? && yy.nil?
                res = 0
              elsif xx.nil?
                res = 1
              elsif yy.nil?
                res = -1
              else
              res = y[abse] <=> x[abse]
              end
            else
              xx = x[e]
              yy = y[e]
              # the following checks are since nil values cause an error to be raised
              # whereas we want a nil to be wither treated as a zero or a blank
              if xx.nil? && yy.nil?
                res = 0
              elsif xx.nil?
                res = -1
              elsif yy.nil?
                res = 1
              else
              res = x[e] <=> y[e]
              end
            end
            break if res != 0
          }
          res
        }
        ensure
          @model.insert 0, header if header
        end
      end
      # toggle the sort order if given column offset is primary sort key
      # Otherwise, insert as primary sort key, ascending.
      def toggle_sort_order index
        index += 1 # increase by 1, since 0 won't multiple by -1
        # internally, reverse sort is maintained by multiplying number by -1
        @sort_keys ||= []
        if @sort_keys.first && index == @sort_keys.first.abs
          @sort_keys[0] *= -1 
        else
          @sort_keys.delete index # in case its already there
          @sort_keys.delete(index*-1) # in case its already there
          @sort_keys.unshift index
          # don't let it go on increasing
          if @sort_keys.size > 3
            @sort_keys.pop
          end
        end
      end
      def set_sort_keys list
        @sort_keys = list
      end
    end #class

    # sorter }
    # renderer {
  #
  # TODO see how jtable does the renderers and columns stuff.
  #
  # perhaps we can combine the two but have different methods or some flag
  # that way oter methods can be shared
    class DefaultTableRenderer

      # source is the textpad or extending widget needed so we can call show_colored_chunks
      # if the user specifies column wise colors
      def initialize source
        @source = source
        @y = '|'
        @x = '+'
        @coffsets = []
        @header_color = :white
        @header_bgcolor = :red
        @header_attrib = NORMAL
        @color = :white
        @bgcolor = :black
        @color_pair = $datacolor
        @attrib = NORMAL
        @_check_coloring = nil
        # adding setting column_model auto on 2014-04-10 - 10:53 why wasn;t this here already
        column_model(source.column_model)
      end
      def header_colors fg, bg
        @header_color = fg
        @header_bgcolor = bg
      end
      def header_attrib att
        @header_attrib = att
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
      def column_model c
        @chash = c
      end
      ##
      # Takes the array of row data and formats it using column widths
      # and returns a string which is used for printing
      #
      # TODO return an array so caller can color columns if need be
      def convert_value_to_text r  
        str = []
        fmt = nil
        field = nil
        # we need to loop through chash and get index from it and get that row from r
        each_column {|c,i|
          e = r[c.index]
          w = c.width
          l = e.to_s.length
          # if value is longer than width, then truncate it
          if l > w
            fmt = "%.#{w}s "
          else
            case c.align
            when :right
              fmt = "%#{w}s "
            else
              fmt = "%-#{w}s "
            end
          end
          field = fmt % e
          # if we really want to print a single column with color, we need to print here itself
          # each cell. If we want the user to use tmux formatting in the column itself ...
          # FIXME - this must not be done for headers.
          #if c.color
          #field = "#[fg=#{c.color}]#{field}#[/end]"
          #end
          str << field
        }
        return str
      end
      #
      # @param pad for calling print methods on
      # @param lineno the line number on the pad to print on
      # @param text data to print
      def render pad, lineno, str
        #lineno += 1 # header_adjustment
        # header_adjustment means columns have been set
        return render_header pad, lineno, 0, str if lineno == 0 && @source.header_adjustment > 0
        #text = str.join " | "
        #text = @fmstr % str
        text = convert_value_to_text str
        if @_check_coloring
          #$log.debug "XXX:  INSIDE COLORIIN"
          text = colorize pad, lineno, text
          return
        end
        # check if any specific colors , if so then print colors in a loop with no dependence on colored chunks
        # then we don't need source pointer
        render_data pad, lineno, text

      end
      # passes padded data for final printing or data row
      # this allows user to do row related coloring without having to tamper
      # with the headers or other internal workings. This will not be called
      # if column specific colorign is in effect.
      # @param text is an array of strings, in the order of actual printing with hidden cols removed
      def render_data pad, lineno, text
        text = text.join
        # FIXME why repeatedly getting this colorpair
        cp = @color_pair
        att = @attrib
        # added for selection, but will crash if selection is not extended !!! XXX
          if @source.is_row_selected? lineno
            att = REVERSE
            # FIXME currentl this overflows into next row
          end
        
        FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
        FFI::NCurses.mvwaddstr(pad, lineno, 0, text)
        FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      end

      def render_header pad, lineno, col, columns
        # I could do it once only but if user sets colors midway we can check once whenvever
        # repainting
        check_colors #if @_check_coloring.nil?
        #text = columns.join " | "
        #text = @fmstr % columns
        text = convert_value_to_text columns
        text = text.join
        bg = @header_bgcolor
        fg = @header_color
        att = @header_attrib
        #cp = $datacolor
        cp = get_color($datacolor, fg, bg)
        FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
        FFI::NCurses.mvwaddstr(pad, lineno, col, text)
        FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      end
      # check if we need to individually color columns or we can do the entire
      # row in one shot
      def check_colors
        each_column {|c,i|
          if c.color || c.bgcolor || c.attrib
            @_check_coloring = true
            return
          end
          @_check_coloring = false
        }
      end
      def each_column
        @chash.each_with_index { |c, i| 
          next if c.hidden
          yield c,i if block_given?
        }
      end
      def colorize pad, lineno, r
        # the incoming data is already in the order of display based on chash,
        # so we cannot run chash on it again, so how do we get the color info
        _offset = 0
        each_column {|c,i|
          text = r[i]
          color = c.color
          bg = c.bgcolor
          if color || bg
            cp = get_color(@color_pair, color || @color, bg || @bgcolor)
          else
            cp = @color_pair
          end
          att = c.attrib || @attrib
          FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
          FFI::NCurses.mvwaddstr(pad, lineno, _offset, text)
          FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
          _offset += text.length
        }
      end
    end
# renderer }

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
    require 'canis/core/include/listselectionmodel'
  class Table < TextPad

    dsl_accessor :print_footer
    #attr_reader :columns
    attr_accessor :table_row_sorter

    def initialize form = nil, config={}, &block

      # hash of column info objects, for some reason a hash and not an array
      @chash = []
      # chash should be an array which is basically the order of rows to be printed
      #  it contains index, which is the offset of the row in the data @list
      #  When printing we should loop through chash and get the index in data
      #
      # should be zero here, but then we won't get textpad correct
      @_header_adjustment = 0 #1
      @col_min_width = 3

      self.extend DefaultListSelection
      super
      create_default_renderer unless @renderer # 2014-04-10 - 11:01 
      $log.debug "XXX: jtable constructor after super"
      bind_key(?w, "next column") { self.next_column }
      bind_key(?b, "prev column") { self.prev_column }
      bind_key(?-, "contract column") { self.contract_column }
      bind_key(?+, "expand column") { self.expand_column }
      bind_key(?=, "expand column to width") { self.expand_column_to_width }
      bind_key(?\M-=, "expand column to width") { self.expand_column_to_max_width }
      bind_key(?\C-s, "Save as") { self.save_as(nil) }
      #@list_selection_model ||= DefaultListSelectionModel.new self
      set_default_selection_model unless @list_selection_model
    end
    def set_default_selection_model
      @list_selection_model = nil
      @list_selection_model = Canis::DefaultListSelectionModel.new self
    end
    
    # retrieve the column info structure for the given offset. The offset
    # pertains to the visible offset not actual offset in data model. 
    # These two differ when we move a column.
    # @return ColumnInfo object containing width align color bgcolor attrib hidden
    def get_column index
      return @chash[index] if @chash[index]
      # create a new entry since none present
      c = ColumnInfo.new
      c.index = index
      @chash[index] = c
      return c
    end
    ## 
    # returns collection of ColumnInfo objects
    def column_model
      @chash
    end

    # calculate pad width based on widths of columns
    def content_cols
      total = 0
      #@chash.each_pair { |i, c| 
      #@chash.each_with_index { |c, i| 
        #next if c.hidden
      each_column {|c,i|
        w = c.width
        # if you use prepare_format then use w+2 due to separator symbol
        total += w + 1
      }
      return total
    end

    # 
    # This calculates and stores the offset at which each column starts.
    # Used when going to next column or doing a find for a string in the table.
    # TODO store this inside the hash so it's not calculated again in renderer
    #
    def _calculate_column_offsets
      @coffsets = []
      total = 0

      #@chash.each_pair { |i, c| 
      #@chash.each_with_index { |c, i| 
        #next if c.hidden
      each_column {|c,i|
        w = c.width
        @coffsets[i] = total
        c.offset = total
        # if you use prepare_format then use w+2 due to separator symbol
        total += w + 1
      }
    end
    # Convert current cursor position to a table column
    # calculate column based on curpos since user may not have
    # user w and b keys (:next_column)
    # @return [Fixnum] column index base 0
    def _convert_curpos_to_column  #:nodoc:
      _calculate_column_offsets unless @coffsets
      x = 0
      @coffsets.each_with_index { |i, ix| 
        if @curpos < i 
          break
        else 
          x += 1
        end
      }
      x -= 1 # since we start offsets with 0, so first auto becoming 1
      return x
    end
    # jump cursor to next column
    # TODO : if cursor goes out of view, then pad should scroll right or left and down
    def next_column
      # TODO take care of multipliers
      _calculate_column_offsets unless @coffsets
      c = @column_pointer.next
      cp = @coffsets[c] 
      #$log.debug " next_column #{c} , #{cp} "
      @curpos = cp if cp
      down() if c < @column_pointer.last_index
    end
    # jump cursor to previous column
    # TODO : if cursor goes out of view, then pad should scroll right or left and down
    def prev_column
      # TODO take care of multipliers
      _calculate_column_offsets unless @coffsets
      c = @column_pointer.previous
      cp = @coffsets[c] 
      #$log.debug " prev #{c} , #{cp} "
      @curpos = cp if cp
      up() if c > @column_pointer.last_index
    end
    def expand_column
      x = _convert_curpos_to_column
      w = get_column(x).width
      column_width x, w+1 if w
      @coffsets = nil
      fire_dimension_changed
    end
    def expand_column_to_width w=nil
      x = _convert_curpos_to_column
      unless w
        # expand to width of current cell
        s = @list[@current_index][x]
        w = s.to_s.length + 1
      end
      column_width x, w
      @coffsets = nil
      fire_dimension_changed
    end
    # find the width of the longest item in the current columns and expand the width
    # to that.
    def expand_column_to_max_width
      x = _convert_curpos_to_column
      w = calculate_column_width x
      expand_column_to_width w
    end
    def contract_column
      x = _convert_curpos_to_column
      w = get_column(x).width 
      return if w <= @col_min_width
      column_width x, w-1 if w
      @coffsets = nil
      fire_dimension_changed
    end

    #def method_missing(name, *args)
    #@tp.send(name, *args)
    #end
    #
    # supply a custom renderer that implements +render()+
    # @see render
    def renderer r
      @renderer = r
    end
    def header_adjustment
      @_header_adjustment
    end

  ##
  # getter and setter for columns
  # 2014-04-10 - 13:49 
  # @param [Array] columns to set as Array of Strings
  # @return if no args, returns array of column names as Strings
  #
  def columns(*val)
    if val.empty?
      # returns array of column names as Strings
      @list[0]
    else
      array = val[0]
      @_header_adjustment = 1
      @list ||= []
      @list << array
      # This needs to go elsewhere since this method will not be called if file contains
      # column titles as first row.
      _init_model array
      self
    end
  end

    ##
    # Set column titles with given array of strings.
    # NOTE: This is only required to be called if first row of file or content does not contain
    # titles. In that case, this should be called before setting the data as the array passed
    # is appended into the content array.
    # @deprecated complicated, just use `columns()`
    def columns=(array)
      @_header_adjustment = 1
      # I am eschewing using a separate field for columns. This is simpler for textpad.
      # We always assume first row is columns.
      #@columns = array
      # should we just clear column, otherwise there's no way to set the whole thing with new data
      # but then if we need to change columns what do it do, on moving or hiding a column ?
      # Maybe we need a separate clear method or remove_all TODO
      @list ||= []
      @list << array
      # This needs to go elsewhere since this method will not be called if file contains
      # column titles as first row.
      _init_model array
      self
    end
    alias :headings= :columns=


    # size each column based on widths of this row of data.
    # Only changed width if no width for that column
    def _init_model array
      array.each_with_index { |c,i| 
        # if columns added later we could be overwriting the width
        c = get_column(i)
        c.width ||= 10
      }
      # maintains index in current pointer and gives next or prev
      @column_pointer = Circular.new array.size()-1
    end
    # size each column based on widths of this row of data.
    def model_row index
      array = @list[index]
      array.each_with_index { |c,i| 
        # if columns added later we could be overwriting the width
        ch = get_column(i)
        ch.width = c.to_s.length + 2
      }
      # maintains index in current pointer and gives next or prev
      @column_pointer = Circular.new array.size()-1
      self
    end
    # estimate columns widths based on data in first 10 or so rows
    # This will override any previous widths, so put custom widths
    # after calling this.
    def estimate_column_widths  
      each_column {|c,i|
        c.width  = suggest_column_width(i)
      }
      self
    end
    # calculates and returns a suggested columns width for given column
    # based on data (first 10 rows)
    # called by +estimate_column_widths+ in a loop
    def suggest_column_width col
      #ret = @cw[col] || 2
      ret = get_column(col).width || 2
      ctr = 0
      @list.each_with_index { |r, i| 
        #next if i < @toprow # this is also a possibility, it checks visible rows
        break if ctr > 10
        ctr += 1
        next if r == :separator
        c = r[col]
        x = c.to_s.length
        ret = x if x > ret
      }
      ret
    end

    #------- data modification methods ------#

    # I am assuming the column has been set using +columns=+
    # Now only data is being sent in
    # NOTE : calling set_content sends to TP's +text()+ which resets @list
    # @param lines is an array or arrays
    def text lines, fmt=:none
      # maybe we can check this out
      # should we not erase data, will user keep one column and resetting data ?
      # set_content assumes data is gone.
      @list ||= []  # this would work if no columns
      @list.concat( lines)
      fire_dimension_changed
      self
    end

    ##
    # set column array and data array in one shot
    # Erases any existing content
    def resultset columns, data
      # FIXME should clear so we don't lose link to renderer, do we ?
      @list = []
      _init_model columns
      @list << columns
      @_header_adjustment = 1
      
      @list.concat( data)
      fire_dimension_changed
      self
    end
    # Takes the name of a file containing delimited data
    #  and load it into the table.
    # This method will load and split the file into the table.
    # @param name is the file name
    # @param config is a hash containing:
    #   - :separator - field separator, default is TAB
    #   - :columns  - array of column names
    #                or true - first row is column names
    #                or false - no columns.
    #
    # == NOTE
    #   if columns is not mentioned, then it defaults to false
    #
    # == Example
    #
    #     table = Table.new ...
    #     table.filename 'contacts.tsv', :separator => '|', :columns => true
    #   
    def filename name, _config = {}
      arr = File.open(name,"r").read.split("\n")
      lines = []
      sep = _config[:separator] || _config[:delimiter] || '\t'
      arr.each { |l| lines << l.split(sep) }
      cc = _config[:columns]
      if cc.is_a? Array
        columns(cc)
        text(lines)
      elsif cc
        # cc is true, use first row as column names
        columns(lines[0])
        text(lines[1..-1])
      else
        # cc is false - no columns
        _init_model lines[0]
        text(lines)
      end
    end
    alias :load :filename

    # save the table as a file
    # @param String name of output file. If nil, user is prompted
    # Currently, tabs are used as delimiter, but this could be based on input
    # separator, or prompted.
    def save_as outfile
      unless outfile
        outfile = get_string "Enter file name to save as "
        return unless outfile
      end
      File.open(outfile, 'w') {|f| 
        @list.each {|r|
          line = r.join "\t"
          f.puts line
        }
      }
    end
#

    ## add a row to the table
    # The name add will be removed soon, pls use << instead.
    def add array
      unless @list
        # columns were not added, this most likely is the title
        @list ||= []
        _init_model array
      end
      @list << array
      fire_dimension_changed
      self
    end
    alias :<< :add

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
    #
    # clear the list completely
    def clear
      @selected_indices.clear
      super
    end

    # get the value at the cell at row and col
    # @return String
    def get_value_at row,col
      actrow = row + @_header_adjustment
      @list[actrow, col]
    end

    # set value at the cell at row and col
    # @param int row
    # @param int col
    # @param String value
    # @return self
    def set_value_at row,col,val
      actrow = row + @_header_adjustment
      @list[actrow , col] = val
      fire_row_changed actrow
      self
    end
    
    #------- column related methods ------#
    #
    # convenience method to set width of a column
    # @param index of column
    # @param width
    # For setting other attributes, use get_column(index)
    def column_width colindex, width
      get_column(colindex).width = width
      _invalidate_width_cache
    end
    # convenience method to set alignment of a column
    # @param index of column
    # @param align - :right (any other value is taken to be left)
    def column_align colindex, align
      get_column(colindex).align = align
    end
    # convenience method to hide or unhide a column
    # Provided since column offsets need to be recalculated in the case of a width
    # change or visibility change
    def column_hidden colindex, hidden
      get_column(colindex).hidden = hidden
      _invalidate_width_cache
    end
    # http://www.opensource.apple.com/source/gcc/gcc-5483/libjava/javax/swing/table/DefaultTableColumnModel.java
    def _invalidate_width_cache    #:nodoc:
      @coffsets = nil
    end
    ## 
    # should all this move into table column model or somepn
    # move a column from offset ix to offset newix
    def move_column ix, newix
      acol = @chash.delete_at ix 
      @chash.insert newix, acol
      _invalidate_width_cache
      #tmce = TableColumnModelEvent.new(ix, newix, self, :MOVE)
      #fire_handler :TABLE_COLUMN_MODEL_EVENT, tmce
    end
    def add_column tc
      raise "to figure out add_column"
      _invalidate_width_cache
    end
    def remove_column tc
      raise "to figure out add_column"
      _invalidate_width_cache
    end
    def calculate_column_width col, maxrows=99
      ret = 3
      ctr = 0
      @list.each_with_index { |r, i| 
        #next if i < @toprow # this is also a possibility, it checks visible rows
        break if ctr > maxrows
        ctr += 1
        #next if r == :separator
        c = r[col]
        x = c.to_s.length
        ret = x if x > ret
      }
      ret
    end
    ##
    # refresh pad onto window
    # overrides super
    def padrefresh
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

    def create_default_sorter
      raise "Data not sent in." unless @list
      @table_row_sorter = DefaultTableRowSorter.new @list
    end
    # set a default renderer
    #--
    #  we were not doing this automatically, so repaint was going to TP and failing on mvaddstr
    #  2014-04-10 - 10:57 
    #++
    def create_default_renderer
      r = DefaultTableRenderer.new self
      renderer(r)
    end
    def header_row?
      @prow == 0
    end

    def fire_action_event
      if header_row?
        if @table_row_sorter
          x = _convert_curpos_to_column
          c = @chash[x]
          # convert to index in data model since sorter only has data_model
          index = c.index
          @table_row_sorter.toggle_sort_order index
          @table_row_sorter.sort
          fire_dimension_changed
        end
      end
      super
    end
    ## 
    # Find the next row that contains given string
    # Overrides textpad since each line is an array
    # NOTE does not go to next match within row
    # NOTE: FIXME ensure_visible puts prow = current_index so in this case, the header
    #   overwrites the matched row.
    # @return row and col offset of match, or nil
    # @param String to find
    def next_match str
      _calculate_column_offsets unless @coffsets
      first = nil
      ## content can be string or Chunkline, so we had to write <tt>index</tt> for this.
      @list.each_with_index do |fields, ix|
        #col = line.index str
        #fields.each_with_index do |f, jx|
        #@chash.each_with_index do |c, jx|
          #next if c.hidden
        each_column do |c,jx|
          f = fields[c.index]
          # value can be numeric
          col = f.to_s.index str
          if col
            col += @coffsets[jx] 
            first ||= [ ix, col ]
            if ix > @current_index
              return [ix, col]
            end
          end
        end
      end
      return first
    end
    # yields each column to caller method
    # for true returned, collects index of row into array and returns the array
    # @returns array of indices which can be empty
    # Value yielded can be fixnum or date etc
    def matching_indices 
      raise "block required for matching_indices" unless block_given?
      @indices = []
      ## content can be string or Chunkline, so we had to write <tt>index</tt> for this.
      @list.each_with_index do |fields, ix|
        flag = yield ix, fields
        if flag
          @indices << ix 
        end
      end
      #$log.debug "XXX:  INDICES found #{@indices}"
      if @indices.count > 0
        fire_dimension_changed
        init_vars
      else
        @indices = nil
      end
      #return @indices
    end
    def clear_matches
      # clear previous match so all data can show again
      if @indices && @indices.count > 0
        fire_dimension_changed
        init_vars
      end
      @indices = nil
    end
    ## 
    # Ensure current row is visible, if not make it first row
    #  This overrides textpad due to header_adjustment, otherwise
    #  during next_match, the header overrides the found row.
    # @param current_index (default if not given)
    #
    def ensure_visible row = @current_index
      unless is_visible? row
          @prow = @current_index - @_header_adjustment
      end
    end
    #
    # yields non-hidden columns (ColumnInfo) and the offset/index
    # This is the order in which columns are to be printed
    def each_column
      @chash.each_with_index { |c, i| 
        next if c.hidden
        yield c,i if block_given?
      }
    end
    def render_all
      if @indices && @indices.count > 0
        @indices.each_with_index do |ix, jx|
          render @pad, jx, @list[ix]
        end
      else
        @list.each_with_index { |line, ix|
          #FFI::NCurses.mvwaddstr(@pad,ix, 0, @list[ix])
          render @pad, ix, line
        }
      end
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

  end # class Table

end # module
