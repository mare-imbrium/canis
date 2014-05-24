# ------------------------------------------------------------ #
#         File: chunk.rb 
#  Description: 
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 07.11.11 - 12:31 
#  Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-05-23 19:44
# ------------------------------------------------------------ #
#

module Canis
  module Chunks
    extend self

    # A chunk is a piece of text with associated color and attrib.
    # Several such chunks make a ChunkLine.
    class Chunk

      # color_pair of associated text
      # text to print
      # attribute of associated text
      #attr_accessor :color, :text, :attrib
      attr_reader :chunk

      def initialize color, text, attrib
        @chunk = [ color, text, attrib ]
        #@color = color
        #@text  = text
        #@attrib = attrib
      end
      def color
        @chunk[0]
      end
      def text
        @chunk[1]
      end
      def attrib
        @chunk[2]
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
      # Splits a chunk line giving text, color and attrib
      # The purpose of this is to free callers such as window or pad from having to know the internals
      # of this implementation. Any substituing class should have a similar interface.
      # @yield text, color and attrib to the block
      def each_with_color &block
        @chunks.each do |chunk| 
          case chunk
          when Chunks::Chunk
            color = chunk.color
            attrib = chunk.attrib
            text = chunk.text
          when Array
            # for earlier demos that used an array
            color = chunk[0]
            attrib = chunk[2]
            text = chunk[1]
          end
          yield text, color, attrib
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
      def index str
        result = 0
        @chunks.each { |e| txt = e.text; 
          ix =  txt.index(str) 
          return result + ix if ix
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
    end
    class ColorParser
      attr_reader :stylesheet
      # hash containing color, bgcolor and attrib for a given style
      attr_writer :style_map
      def initialize cp
        color_parser cp

        if cp.is_a? Hash
          @color = cp[:color]
          @bgcolor = cp[:bgcolor]
          @attrib = cp[:attr]
        end
        @attrib     ||= FFI::NCurses::A_NORMAL
        @color      ||= :white
        @bgcolor    ||= :black
        @color_pair = get_color($datacolor, @color, @bgcolor)
        @color_array = [@color]
        @bgcolor_array = [@bgcolor]
        @attrib_array = [@attrib]
        @color_pair_array = [@color_pair]
      end

      # since 2014-05-19 - 13:14 
      # converts a style name given in a document to color, bg, and attrib from a stylesheet
      def resolve_style style
        if @style_map
          # style_map contains a map for each style
          retval =  @style_map[style]
          raise "Invalid style #{style} in document" unless retval
          return retval
        end
        raise "Style given in document, but no stylesheet provided"
      end
      #
      # Takes a formatted string and converts the parsed parts to chunks.
      #
      # @param [String] takes the entire line or string and breaks into an array of chunks
      # @yield chunk if block
      # @return [ChunkLine] # [Array] array of chunks
      # @since 1.4.1   2011-11-3 experimental, can change
      public
      def convert_to_chunk s, colorp=$datacolor, att=FFI::NCurses::A_NORMAL

        @color_parser ||= get_default_color_parser()
        ## defaults
        color_pair = @color_pair
        attrib = @attrib
        #res = []
        res = ChunkLine.new
        color = @color
        bgcolor = @bgcolor
        # stack the values, so when user issues "/end" we can pop earlier ones

        @color_parser.parse_format(s) do |p|
          case p
          when Array
            ## got color / attrib info, this starts a new span

            # added style 2014-05-19 - 12:57 maybe should be a hash
            #color, bgcolor, attrib , style = *p
            lc, lb, la, ls = *p
            if ls
              #sc, sb, sa = resolve_style ls
              map = resolve_style ls
              $log.debug "  STYLLE #{ls} : #{map} "
              lc ||= map[:color]
              lb ||= map[:bgcolor]
              la ||= map[:attrib]
            end
            if la
              @attrib = get_attrib la
            end
            if lc || lb
              @color = lc ? lc : @color_array.last
              @bgcolor = lb ? lb : @bgcolor_array.last
              @color_array << @color
              @bgcolor_array << @bgcolor
              @color_pair = get_color($datacolor, @color, @bgcolor)
            end
            @color_pair_array << @color_pair
            @attrib_array << @attrib
            $log.debug "XXX: CHUNK start cp=#{@color_pair} , a=#{@attrib} :: c:#{lc} b:#{lb} : @c:#{@color} @bg: #{@bgcolor} "
            $log.debug "XXX: CHUNK start arr #{@color_pair_array} :: #{@attrib_array} ::#{@color_array} ::: #{@bgcolor_array} "

          when :endcolor

            # end the current (last) span
            @color_pair_array.pop
            @color_pair = @color_pair_array.last
            @attrib_array.pop
            @attrib = @attrib_array.last
            # why are we nt popping the color and bgcolor array dts
            @color_array.pop unless @color_array.count == 1
            @bgcolor_array.pop unless @bgcolor_array.count == 1
            $log.debug "XXX: CHUNK end #{color_pair} , #{attrib} "
            $log.debug "XXX: CHUNK end arr #{@color_pair_array} :: #{@attrib_array} "
          when :reset   # ansi has this
            # end all previous colors
            @color_pair = $datacolor # @color_pair_array.first
            @color_pair_array = [@color_pair]
            @attrib = FFI::NCurses::A_NORMAL #@attrib_array.first
            @attrib_array = [@attrib]
            @bgcolor_array = [@bgcolor_array.first]
            @color_array = [@color_array.first]

          when String

            ## create the chunk
            $log.debug "XXX:  CHUNK     using on #{p}  : #{@color_pair} , #{@attrib} " # 2011-12-10 12:38:51

            #chunk =  [color_pair, p, attrib] 
            chunk = Chunk.new @color_pair, p, @attrib
            if block_given?
              yield chunk
            else
              res << chunk
            end
          end
        end # parse
        return res unless block_given?
      end
      def get_default_color_parser
        require 'canis/core/util/defaultcolorparser'
        @color_parser || DefaultColorParser.new
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
      # supply with a color parser, if you supplied formatted text
      def color_parser f
        if f.is_a? Hash
          self.stylesheet = f[:stylesheet]
          content_type = f[:content_type]
        else
          content_type = f
        end
        $log.debug "XXX:  color_parser setting in CP to #{f} "
        if content_type == :tmux
          @color_parser = get_default_color_parser()
        elsif content_type == :ansi
          require 'canis/core/util/ansiparser'
          @color_parser = AnsiParser.new
        else
          @color_parser = f
        end
      end
    end # class
  end
end
