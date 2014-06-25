# ----------------------------------------------------------------------------- #
#         File: defaultfilerenderer.rb
#  Description: Simple file renderer, colors an entire line based on some keyword.
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-06-25 - 12:57
#      License: MIT
#  Last update: 2014-06-25 12:58
# ----------------------------------------------------------------------------- #
#  defaultfilerenderer.rb  Copyright (C) 2012-2014 j kepler


  # a simple file renderer that allows setting of colors per line based on 
  # regexps passed to +insert_mapping+. See +tasks.rb+ for example usage.
  #   
  class DefaultFileRenderer < AbstractTextPadRenderer
    attr_accessor :default_colors
    attr_reader :hash

    def initialize source=nil
      @default_colors = [:white, :black, NORMAL]
      @pair = get_color($datacolor, @default_colors.first, @default_colors[1])
    end

    def color_mappings hash
      @hash = hash
    end
    # takes a regexp, and an array of color, bgcolor and attr
    def insert_mapping regex, dim
      @hash ||= {}
      @hash[regex] = dim
    end
    # matches given line with each regexp to determine color use
    # Internally used by render.
    def match_line line
      @hash.each_pair {| k , p|
        if line =~ k
          return p
        end
      }
      return @default_colors
    end
    # render given line in color configured using +insert_mapping+
    def render pad, lineno, text
      if @hash
        dim = match_line text
        fg = dim.first
        bg = dim[1] || @default_colors[1]
        if dim.size == 3
          att = dim.last
        else
          att = @default_colors.last
        end
        cp = get_color($datacolor, fg, bg)
      else
        cp = @pair
        att = @default_colors[2]
      end

      FFI::NCurses.wattron(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
      FFI::NCurses.mvwaddstr(pad, lineno, 0, text)
      FFI::NCurses.wattroff(pad,FFI::NCurses.COLOR_PAIR(cp) | att)
    end
    #
  end
