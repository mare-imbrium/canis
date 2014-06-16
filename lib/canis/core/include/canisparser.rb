# ----------------------------------------------------------------------------- #
#         File: canisparser.rb
#  Description: creates an returns instances of parser objects
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-06-11 - 12:23
#      License: MIT
#  Last update: 2014-06-16 16:56
# ----------------------------------------------------------------------------- #
#  canisparser.rb  Copyright (C) 2012-2014 j kepler
module Canis

  # Uses multiton pattern from http://blog.rubybestpractices.com/posts/gregory/059-issue-25-creational-design-patterns.html
  # to create and returns cached instances of a text parser.
  # Users will call the +[]+ method rather than the +new+ method.
  # If users wish to declare their own custom parser, then the +map+ method is to be used.
  #
  # @example
  #
  #     CanisParser[:tmux]
  #
  # To define your own parser:
  #
  #     CanisParser.map( :custom => [ 'canis/core/include/customparser', 'Canis::CustomParser' ]
  #
  # and later at some point,
  #
  #     CanisParser[:custom]
  #
  class CanisParser
    class << self
      # hash storing a filename and classname per content_type
      def content_types 
        #@content_types ||= {}
        unless @content_types
          @content_types = {}
          #map(:tmux => [ 'canis/core/util/defaultcolorparser', 'DefaultColorParser'])
          #map(:ansi => [ 'canis/core/util/ansiparser', 'AnsiParser'] )
          @content_types[:tmux] = [ 'canis/core/util/defaultcolorparser', 'DefaultColorParser']
          @content_types[:ansi] = [ 'canis/core/util/ansiparser', 'AnsiParser']
        end
        return @content_types
      end
      # hash storing a parser instance per content_type
      def instances 
        @instances ||= {}
      end
      # Used by user to define a new parser
      # map( :tmux => ['filename', 'klassname'] )
      def map(params)
        content_types.update params
      end

      # Used by user to retrieve a parser instance, creating one if not present
      # CanisParser[:tmux]
      def [](name)
        $log.debug "  [] got #{name} "
        raise "nil received by [] " unless name
        instances[name] ||= new(content_types[name])
        #instances[name] ||= create(content_types[name])
      end
      def create args
        filename = args.first
        klassname = args[1]
        $log.debug "  canisparser create got #{args} "
        require filename
        clazz = Object.const_get(klassname).new
        $log.debug "  created #{clazz.class} "
        #  clazz = 'Foo::Bar'.split('::').inject(Object) {|o,c| o.const_get c}
        return clazz
      end
    end
    ## WARNING - this creates a CanisParser class which we really can't use.
    # So we need to delegate to the color parse we created.
    # create and return a parser instance
    # Canisparser.new filename, klassname
    # Usually, *not* called by user, since this instance is not cached. Use +map+
    #  and then +[]+ instead for creating and cacheing.
    def initialize *args
      args = args.flatten
      filename = args.first
      klassname = args[1]
      $log.debug "  canisparser init got #{args} "
      raise "Canisparser init got nil" unless filename
      require filename
      clazz = Object.const_get(klassname).new
      #  clazz = 'Foo::Bar'.split('::').inject(Object) {|o,c| o.const_get c}
      #return clazz
      @clazz = clazz
    end
    # delegate call to color parser
    def parse_format s, *args, &block
      @clazz.parse_format(s, *args, &block)
    end
    # delegate all call to color parser
    def method_missing meth, *args, &block
      #$log.debug "  canisparser got method_missing for #{meth}, sending to #{@clazz.class} "
      @clazz.send( meth, *args, &block)
    end
  end
end
