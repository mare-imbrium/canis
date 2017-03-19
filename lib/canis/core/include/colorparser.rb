# ------------------------------------------------------------ #
#         File: chunk.rb 
#  Description: Contains classes that implement the default native format
#               we use for colored lines display.
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 07.11.11 - 12:31 
#  Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2017-03-09 23:13
# ------------------------------------------------------------ #
#

module Canis
  module Chunks
    extend self

    # A chunk is a piece of text with associated color and attr.
    # Several such chunks make a ChunkLine.
    # 2014-05-24 - 11:52 adding parent, and trying to resolve at time of render
    #   so changes in form;s color can take effect without parsing the tree again.
    #
    # +color+ is a color pair which is already resolved with parent's color at time of 
    # parsing. We need to store bgcolor and color so we can resolve at render time if nil.
    #
    class Chunk

      # color_pair of associated text
      # text to print
      # attribute of associated text
      #attr_accessor :color, :text, :attr
      # hope no one is accessing chunk since format can change to a hash
      attr_reader :chunk
      attr_accessor :parent
      attr_writer :color, :bgcolor

      # earlier color was being resolved at parse time. Now with chunk change 2014-05-24 - 12:41 
      #  color should be nil if not specified. Do not use parent's color.
      #  Please set fgcolor and bgcolor if present, so we can resolve later.
      def initialize color_pair, text, attr
        @chunk = [ color_pair, text, attr ]
        #@color = color
        #@text  = text
        #@attr = attr
      end
      #
      # This is to be called at runtime by render_all or render to resolve
      # the color.
      # @return [color_pair, nil] color pair for chunk, if nil then substitute with 
      #   the default which will be form's color. If the form has set fg and bg, then nil
      #   should not be returned ever.
      def color_pair
        #@chunk[0] 
        # if the color was set, use return it.
        return @chunk[0] if @chunk[0]
        if @color && @bgcolor
          # color was not set, but fg and bg both were
          @chunk[0] = get_color(nil, @color, @bgcolor)
          return @chunk[0] if @chunk[0]
        end
        # return a resolved color_pair if we can, but do not store it in tree.
        # This will be resolved each time render is called from parent.
        return get_color(nil, self.color(), self.bgcolor())
      end
      def text
        @chunk[1]
      end
      def attr
        @chunk[2] || @parent.attr || NORMAL
      end

      # this returns the color of this chunk, else goes up the parents, and finally
      # if none, then returns the default fg color
      # NOTE: this is used at the time of rendering, not parsing
      #   This is to ensure that any changes in widgets colors are reflected in renderings
      #   without requiring the parse to be done again.
      #   Idiealy, the widget would return the form's color if its own was not set, however,
      #   i see that color has been removed from form. It should be there, so it reflects
      #   in all widgets.
      def color
        @color || @parent.color || $def_fg_color
      end
      # this returns the bgcolor of this chunk, else goes up the parents, and finally
      # if none, then returns the default bg color (global) set in colormap.rb
      # NOTE: this is used at the time of rendering, not parsing
      def bgcolor
        @bgcolor || @parent.bgcolor || $def_bg_color
      end
    end

    # consists of an array of chunks and corresponds to a line
    # to be printed.
    class ChunkLine < AbstractChunkLine

      # an array of chunks
      attr_reader :chunks

      def initialize arr=nil
        @chunks = arr.nil? ? Array.new : arr
      end
      def <<(chunk)
        raise ArgumentError, "Chunk object expected. Received #{chunk.class} " unless chunk.is_a? Chunk
        @chunks << chunk
      end
      alias :add :<<
      def each &block
        @chunks.each &block
      end
      #
      # Splits a chunk line giving text, color and attr
      # The purpose of this is to free callers such as window or pad from having to know the internals
      # of this implementation. Any substituing class should have a similar interface.
      # @yield text, color and attr to the block
      def each_with_color &block
        @chunks.each do |chunk| 
          case chunk
          when Chunks::Chunk
            color = chunk.color_pair
            attr = chunk.attr
            text = chunk.text
          when Array
            # for earlier demos that used an array
            color = chunk[0]
            attr = chunk[2]
            text = chunk[1]
          end
          yield text, color, attr
        end
      end

      # returns length of text in chunks
      def row_length
        result = 0
        @chunks.each { |e| result += e.text.length }
        return result
      end
      # returns match for str in this chunk
      # added 2013-03-07 - 23:59 
      # adding index on 2014-05-26 for multiple matches on one line.
      # 2014-05-28 - 12:02 may no longer be used since i have added to_s in next_match in textpad.
      def index str, offset = 0
        result = 0
        _end = 0
        @chunks.each { |e| txt = e.text; 
          _end += txt.length 
          if _end < offset
            result += e.text.length 
            next
          end

          ix =  txt.index(str) 
          if ix
            _off = result + ix
            return _off if _off > offset
          end
          result += e.text.length 
        }
        return nil
      end
      alias :length :row_length
      alias :size   :row_length

      # return a Chunkline containing only the text for the range requested
      def substring start, size
        raise "substring not implemented yet"
      end
      def to_s
        result = ""
        @chunks.each { |e| result << e.text }
        result
      end

      # added to take care of many string methods that are called.
      # Callers really don't know this is a chunkline, they assume its a string
      # 2013-03-21 - 19:01 
      def method_missing(sym, *args, &block)
        self.to_s.send sym, *args, &block
      end
      # print a chunkline 
      # NOTE: tested with pad only. Not with window.
      #  Moved from textpad, this is the one method textpad is to call.
      #  @param [Pad] pad on which to print
      #  @param [Integer] lineno to print (zero-based)
      #  @param [Integer] column to start printing on, usually 0
      #  @param [Integer] width of pad, usually @content_cols
      #  @param [color_pair] colorpair of textpad or widget
      #  @param [attr] attr of textpad or widget
      def print pad, lineno, col, width, color_pair, attr
        FFI::NCurses.wmove pad, lineno, col
        a = get_attrib attr

        show_colored_chunks pad, width, color_pair, a
      end
      # moved from textpad.rb. Note that this does printing for a pad not window
      #  so not yet tested if window is passed. Called by +print+.
      def show_colored_chunks(pad, width, defcolor = nil, defattr = nil)

        self.each_with_color do |text, color, attrib|

          color ||= defcolor
          attrib ||= defattr || NORMAL

          #$log.debug "XXX: CHUNK textpad #{text}, cp #{color} ,  attrib #{attrib}. "
          FFI::NCurses.wcolor_set(pad, color,nil) if color
          FFI::NCurses.wattron(pad, attrib) if attrib
          _print(pad, text, width)
          FFI::NCurses.wattroff(pad, attrib) if attrib
        end
      end
      # called only by show_colored_chunks
      def _print(pad, string, _width )
        w = _width == 0? Ncurses.COLS : _width
        FFI::NCurses.waddnstr(pad,string.to_s, w) # changed 2011 dts  
      end
    end

    # This class does not do the actual parsing which must be done by a class
    #   based on the actual format of the marked up document. 
    #   However, this class converts the parsed fragments to a Chunkline
    #   which is an array of Chunks,
    class ColorParser
      attr_reader :stylesheet
      # hash containing color, bgcolor and attr for a given style
      attr_writer :style_map
      def initialize cp
        # in some cases like statusline where it requests window to do some parsing, we will never know who
        #  the parent is. We could somehow get the window, and from there the form ???
        @parents = nil

        chunk_parser cp

        if cp.is_a? Hash
          @color = cp[:color]
          @bgcolor = cp[:bgcolor]
          @attr = cp[:attr]
        end
        if cp.is_a? TextPad
          self.form = cp
        end
        @attr     ||= FFI::NCurses::A_NORMAL
        @color      ||= $def_fg_color
        @bgcolor    ||= $def_bg_color
        @color_pair = get_color($datacolor, @color, @bgcolor)
        @color_array = [@color]
        @bgcolor_array = [@bgcolor]
        @attrib_array = [@attr]
        @color_pair_array = [@color_pair]
      end
      # this is the widget actually that created the parser
      def form=(f)
        @parents = [f]
      end
      public
      # set a stylesheet -- this is a file path containing yaml
      # a style_map is loaded from the stylesheet
      # Sending a symbol such as :help will load style_help.yml
      # @param [String, Symbol] s is a pathname for stylesheet or symbol pointing to a stylesheet
      def stylesheet=(s)
        return unless s
        if s.is_a? Symbol
          s = CANIS_DOCPATH + "style_#{s}.yml"
        end
        @stylesheet = s
        if File.exist? s
          require 'yaml'
          @style_map = YAML::load( File.open( File.expand_path(s) ))
        else
          raise "Could not find stylesheet file #{s}"
        end
      end
      # what if a text pad changes it's content type, should be not allow it to just
      #  use the same parser with a changed internal parser
      # UNUSED as yet
      def content_type ct
        return if ct == @content_type
        @content_type = ct
        self.chunk_parser ct
      end
      # supply with a color parser, if you supplied formatted text
      def chunk_parser f
        if f.is_a? Hash
          self.stylesheet = f[:stylesheet]
          content_type = f[:content_type]
        elsif f.is_a? TextPad
          ff = f.document
          self.stylesheet = ff.stylesheet
          content_type = ff.content_type
        elsif f.is_a? Symbol
          content_type = f
        else
          @chunk_parser = f
          return
        end
        @content_type = content_type
        $log.debug "XXX:  chunk_parser setting in CP to #{f}, content+type is #{content_type} "
        require 'canis/core/include/canisparser'
        @chunk_parser ||= CanisParser[content_type]
        raise "colorparser could not find a parser for #{content_type} " unless @chunk_parser
=begin
        if content_type == :tmux
          @chunk_parser = get_default_color_parser()
        elsif content_type == :ansi
          require 'canis/core/util/ansiparser'
          @chunk_parser = AnsiParser.new
        else
          @chunk_parser = f
        end
=end
      end

      # since 2014-05-19 - 13:14 
      # converts a style name given in a document to color, bg, and attr from a stylesheet
      def resolve_style style
        if @style_map
          # style_map contains a map for each style
          retval =  @style_map[style]
          raise "Invalid style #{style} in document" unless retval
          return retval
        end
        raise "Style given in document, but no stylesheet provided"
      end
      # parse array of Strings into array of Chunks (Chunklines)
      # @param [Array<String>] formatted text to be parsed into chunks
      # @return [Array<Abstractchunkline>] array of text in our native format (chunklines)
      # 2014-09-11 - 19:48 added colorp and attr so that incorrect default is not picked
      #     object such as textpad can send in default, textdocument not does so.
      def parse_text formatted_text, colorp=nil, attr=nil
        l = []
        formatted_text.each { |e| 
          l << convert_to_chunk(e, colorp, attr)
        }
        return l
      end
      #
      # Takes a formatted string and converts the parsed parts to chunks.
      #
      # @param [String] takes the entire line or string and breaks into an array of chunks
      # @yield chunk if block
      # @return [ChunkLine] # [Array] array of chunks
      # @since 1.4.1   2011-11-3 experimental, can change
      # 2014-05-24 - 12:54 NEW As of now since this is called at parse time
      #   colors must not be hardcoded, unless both fg and bg are given for a chunk.
      #   The color_pair should be resolved at render time using parent.
      public
      def convert_to_chunk s, colorp=$datacolor, att=FFI::NCurses::A_NORMAL

        raise "You have not set parent of this using form(). Try setting window.form " unless @parents
        @chunk_parser ||= get_default_color_parser()
        res = ChunkLine.new
        # stack the values, so when user issues "/end" we can pop earlier ones

        _color, _bgcolor = ColorMap.get_colors_for_pair colorp # 2014-08-31 - 13:31 
        newblockflag = false
        @chunk_parser.parse_format(s) do |p|
          case p
          when Array
            newblockflag = true
            ## got color / attr info, this starts a new span

            # added style 2014-05-19 - 12:57 maybe should be a hash
            #color, bgcolor, attr , style = *p
            lc, lb, la, ls = *p
            if ls
              #sc, sb, sa = resolve_style ls
              map = resolve_style ls
              #$log.debug "  STYLLE #{ls} : #{map} "
              lc ||= map[:color]
              lb ||= map[:bgcolor]
              la ||= map[:attr]
            end
            # 2014-09-01 should i set these to _color and _bgcolor if nil. NOTE
            @_bgcolor = lb
            @_color = lc
            if la
              @attr = get_attrib la
            end
            @_color_pair = nil
            @_color_pair = colorp # 2014-08-31 - 13:20 
            # 2014-09-01 - 11:52 if only one of the two is given we were ignoring, now we 
            #  need to derive the other one
            if lc && lb
              # we know only store color_pair if both are mentioned in style or tag
              @_color_pair = get_color(colorp, lc, lb)
              # added next two conditions on 2014-09-01 - 11:56 to take care of only one mentioned in
              # #{ block.
            elsif lc
              @_color_pair = get_color(colorp, lc, _bgcolor)
            elsif lb
              @_color_pair = get_color(colorp, _color, lb)
            end


          when :endcolor

            # end the current (last) span
            @parents.pop unless @parents.count == 1
            @_bgcolor = @_color = nil
            @_color_pair = nil
            @attr = nil

            # trying out 2014-08-31 - 13:09 since we have to respect passed in colors
            @_color ,  @_bgcolor = _color, _bgcolor
            @_color_pair = colorp
            @attr = att

            #$log.debug "XXX: CHUNK end parents:#{@parents.count}, last: #{@parents.last} "
          when :reset   # ansi has this
            # end all previous colors
            # end the current (last) span
            # maybe we need to remove all parents except for first
            @parents.pop unless @parents.count == 1
            @_bgcolor = @_color = nil
            @_color_pair = nil
            @attr = nil
            
            # trying out 2014-08-31 - 13:09 since we have to respect passed in colors
            @_color, @_bgcolor = _color, _bgcolor
            @_color_pair = colorp
            @attr = att


          when String

            ## create the chunk
            #$log.debug "XXX:  CHUNK     using on #{p}  : #{@_color_pair} , #{@attr}, fg: #{@_color}, #{@_bgcolor}, parent: #{@parents.last} " # 2011-12-10 12:38:51

            # trying out 2014-08-31 - 13:09 since we have to respect passed in colors
            @_color ||= _color
            @_bgcolor ||= _bgcolor
            @color_pair ||= colorp
            @attr ||= att
            chunk = Chunk.new @_color_pair, p, @attr
            chunk.color = @_color
            chunk.bgcolor = @_bgcolor
            chunk.parent = @parents.last
            if newblockflag
              @parents << chunk
              #$log.debug "XXX: CHUNK start parents:#{@parents.count}, #{@parents.last} "
              newblockflag = true
            end
            if block_given?
              yield chunk
            else
              res << chunk
            end
          end
        end # parse
        return res unless block_given?
      end
      alias :parse_line :convert_to_chunk

      # returns an instance of the default color parser (tmux parser)
      def get_default_color_parser
        #require 'canis/core/util/defaultcolorparser'
        #@chunk_parser || DefaultColorParser.new

        require 'canis/core/include/canisparser'
        @chunk_parser ||= CanisParser[:tmux]
      end
    end # class
  end
end
