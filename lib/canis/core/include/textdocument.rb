# ----------------------------------------------------------------------------- #
#         File: textdocument.rb
#  Description: Abstracts complex text preprocessing and rendering from TextPad
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-06-25 - 12:52
#      License: MIT
#  Last update: 2014-09-03 17:55
# ----------------------------------------------------------------------------- #
#  textdocument.rb  Copyright (C) 2012-2014 j kepler

module Canis
  # In an attempt to keep TextPad simple, and move complexity of complex content out of it,
  #  I am trying to move specialized processing and rendering to a Document class which manages the same.
  #  I would also like to keep content, and content_type etc together. This should percolate to multibuffers
  #  to.
  #  An application may create a TextDocument object and pass it to TextPad using the +text+ method.
  #  Or an app may send in a hash, which +text+ uses to create this object.
  class TextDocument
    attr_accessor :content_type
    attr_accessor :stylesheet
    # +hash+ of options passed in constructor including content_type and stylesheet
    attr_accessor :options
    # +text+ is the original Array<String> which contains markup of some sort
    #  which source will retrieve. Changes happen to this (row added, deleted, changed)
    attr_accessor :text

    # returns the native or transformed format of original content. +text+ gets transformed into
    #  native text. The renderer knows how to display native_text.
    # NOTE: native_text is currently Chunklines - chunks of text with information of color
    def native_text
      unless @native_text
        preprocess_text @text
      end
      return @native_text
    end
    # specify a renderer if you do not want the DefaultRenderer to be installed.
    attr_accessor :renderer
    # the source object using this document
    attr_reader :source

    def initialize hash
      @parse_required = true
      @options = hash
      @content_type = hash[:content_type]
      @stylesheet = hash[:stylesheet]
      @text = hash[:text]
      $log.debug "  TEXTDOCUMENT created with #{@content_type} , #{@stylesheet} "
      raise "textdoc recieves nil content_type in constructor" unless @content_type
    end
    # declare that transformation of entire content is required. Currently called by fire_dimension_changed event
    #  of textpad. NOTE: not called from event, now called in text()
    def parse_required
      @parse_required = true
    end
    # set the object that is using this textdocument (typically TextPad).
    # This allows us to bind to events such as adding or deleting a row, or modification of data.
    def source=(sou)
      @source = sou
      if @renderer
        @source.renderer = @renderer
      end
      @source.bind :ROW_CHANGED  do | o, ix|  parse_line ix ; end
      @source.bind :DIMENSION_CHANGED do | o, _meth|  parse_required() ; end
      @source.title = self.title() if self.title()
    end
    # if there is a content_type specfied but nothing to handle the content
    #  then we create a default handler.
    def create_default_content_type_handler
      raise "source is nil in textdocument" unless @source
      require 'canis/core/include/colorparser'
      # cp will take the content+type from self and select actual parser
      cp = Chunks::ColorParser.new @source
      @content_type_handler = cp
    end
    # called by textpad to do any parsing or conversion on data since a textdocument by default
    # does some transformation on the content
    def preprocess_text data
      parse_formatted_text data
    end
    # transform a given line number from original content to internal format.
    # Called by textpad when a line changes (update)
    def parse_line(lineno)
      @native_text[lineno] = @content_type_handler.parse_line( @list[lineno]) 
    end
    # This is now to be called at start when text is set,
    # and whenever there is a data modification.
    # This updates @native_text
    # @param [Array<String>] original content sent in by user
    #     which may contain markup
    # @param [Hash] config containing
    #    content_type
    #    stylesheet
    # @return [Chunklines] content in array of chunks.
    def parse_formatted_text(formatted_text, config=nil)
      return unless @parse_required

      unless @content_type_handler
        create_default_content_type_handler
      end
      @parse_required = false
      @native_text = @content_type_handler.parse_text formatted_text
    end
    # returns title of document
    def title
      return @options[:title]
    end
    # set title of document (to be displayed by textpad)
    def title=(t)
      @options[:title] = t
    end
  end
end # mod
