# ----------------------------------------------------------------------------- #
#         File: textutils.rb
#  Description: contains some common string or Array<String> utilities
#    that may be required by various parts of application.
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-05-22 - 11:11
#      License: MIT
#  Last update: 2014-05-23 12:43
# ----------------------------------------------------------------------------- #
#  textutils.rb  Copyright (C) 2012-2014 j kepler

module Canis
  module TextUtils
    # Convert an array of Strings that has help markup into tmux style
    # which can then by parsed into native format by the tmux parser
    # 'help' markup is very much like markdown, but a very restricted
    # subset.
    # Currently called only by help_manager in rwidgets.rb
    def self.help2tmux arr
      arr.each do |e|
        # double sq brackets are like wiki links, to internal documents in same location
        e.gsub! /\[\[(\S+)\]\]/, '#[style=link][\1]#[/end]'
        e.gsub! /\*\*(\w+)\*\*/, '#[style=strong]\1#[/end]'
        e.gsub! /\*([^\*]+)\*/, '#[style=em]\1#[/end]'
        e.gsub! /\|([^\|]+)\|/, '#[style=ul]\1#[/end]'
        #e.gsub! /__(\w+)__/, '#[style=em]\1#[/end]'
        #e.gsub! /_(\w+)_/, '#[style=em]\1#[/end]'
        e.gsub! /__([a-zA-Z]+)__/, '#[style=strong]\1#[/end]'
        e.gsub! /_([^_]+)_/, '#[style=em]\1#[/end]'
        e.gsub! /`([^`]+)`/, '#[style=code]\1#[/end]'
        # keys are mentioned with "<" and ">" surrounding
        e.gsub! /(\<\S+\>)/, '#[style=key]\1#[/end]'
        # headers start with "#"
        e.sub! /^###\s*(.*)$/, '#[style=h3]\1#[/end]'
        e.sub! /^## (.*)$/, '#[style=h2]\1#[/end]'
        e.sub! /^# (.*)$/, '#[style=h1]\1#[/end]'
        # line starting with "">" starts a white bold block as in vim's help. "<" ends block.
        e.sub! /^\>$/, '#[style=wb]'
        e.sub! /^\<$/, '#[/end]'
      end
      return arr
    end
    ## 
    # wraps text given max length, puts newlines in it.
    # it does not take into account existing newlines
    # Some classes have @maxlen or display_length which may be passed as the second parameter
    def self.wrap_text(txt, max )
      txt.gsub(/(.{1,#{max}})( +|$\n?)|(.{1,#{max}})/,
               "\\1\\3\n") 
    end

    # remove tabs, newlines and non-print chars from a string since these
    # can mess display
    def self.clean_string! content
      content.chomp! # don't display newline
      content.gsub!(/[\t\n]/, '  ') # don't display tab
      content.gsub!(/[^[:print:]]/, '')  # don't display non print characters
      content
    end
  end
end
