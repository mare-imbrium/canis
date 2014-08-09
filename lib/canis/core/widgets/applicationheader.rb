# ----------------------------------------------------------------------------- #
#         File: applicationheader.rb
#  Description: Prints a header on first row, with right, left and centered text
#               NOTE: on some terminal such as xterm-256color spaces do not print
#               so you will see black or empty spaces between text.
#               This does not happen on screen and xterm-color.
#               I've done some roundabout stuff to circumvent that.
#       Author: jkepler http://github.com/mare-imbrium/canis-core/
#         Date: 
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-08-09 18:29
#
#  CHANGES:
#              For some terminals, like xterm-256color which were not printing spaces
#              I've changed to code so only text is printed where it has to with no
#              padding. These terminals remove the padding color.
# ----------------------------------------------------------------------------- #
#
require 'canis/core/widgets/rwidget'
include Canis
module Canis
  # Maintain an application header on the top of an application.
  # Application related text may be placed in the left, center or right slots.
  #
  # == Example
  # a = ApplicationHeader.new "MyApp v1.0", :text_center => "Application Name", :text_right => "module",
  #    :color => :white, :bgcolor => :blue
  #
  # # Later as user traverses a list or table, update row number on app header
  # a.text_right "Row #{n}"
  #
  class ApplicationHeader < Widget
    # text on left of header
    dsl_property :text1
    # text on left of header, after text1
    dsl_property :text2
    # text in center of header
    dsl_property :text_center
    # text on right side of header
    dsl_property :text_right

    # @param text1 String text on left of header
    def initialize form, text1, config={}, &block

      @name = "header"
      @text1 = text1
      # setting default first or else Widget will place its BW default
      @color, @bgcolor = ColorMap.get_colors_for_pair $bottomcolor
      super form, config, &block
      @color_pair = get_color $bottomcolor, @color, @bgcolor
      @window = form.window
      @editable = false
      @focusable = false
      @cols ||= Ncurses.COLS-1
      @row ||= 0
      @col ||= 0
      @repaint_required = true
      #@color_pair ||= $bottomcolor  # XXX this was forcing the color
      #pair
      @text2 ||= ""
      @text_center ||= ""
      @text_right ||= ""
    end
    # returns value of text1, i.e. text on left of header
    def getvalue
      @text1
    end

    ##
    # XXX need to move wrapping etc up and done once. 
    def repaint
      return unless @repaint_required
 
      #print_header(htext, posy = 0, posx = 0)
      att = get_attrib @attr
      len = @window.width
      len = Ncurses.COLS-0 if len == 0
      # print a bar across the screen 
      @window.attron(Ncurses.COLOR_PAIR(@color_pair) | att)
      @window.mvhline(@row, @col, 1, len)
      @window.attroff(Ncurses.COLOR_PAIR(@color_pair) | att)
      #print_header(@text1 + " %15s " % @text2 + " %20s" % @text_center , posy=0, posx=0)

      # Now print the text in the correct positions with no padding, else some terminal
      # will blacken the text out.
      print_header("#{@text1}  #{@text2}") # + " %20s" % @text_center , posy=0, posx=0)
      print_center("#{@text_center}") # + " %20s" % @text_center , posy=0, posx=0)
      print_top_right(@text_right)
      @repaint_required = false
    end
    # internal method, called by repain to print text1 and text2 on left side
    def print_header(htext, r = 0, c = 0)
      #win = @window
      #len = @window.width
      #len = Ncurses.COLS-0 if len == 0
      #
      #@form.window.printstring r, c, "%-*s" % [len, htext], @color_pair, @attr
      @form.window.printstring r, c, htext, @color_pair, @attr
    end
    # internal method, called by repaint to print text_center in the center
    def print_center(htext, r = 0, c = 0)
      win = @window
      len = win.getmaxx
      len = Ncurses.COLS-0 if len == 0 || len > Ncurses.COLS
      #
      #@form.window.printstring r, c, "%-*s" % [len, htext], @color_pair, @attr
      win.printstring r, ((len-htext.length)/2).floor, htext, @color_pair, @attr
    end
    # internal method to print text_right
    def print_top_right(htext)
      hlen = htext.length
      len = @window.getmaxx # width was not changing when resize happens
      len = Ncurses.COLS-0 if len == 0 || len > Ncurses.COLS
      $log.debug " def print_top_right(#{htext}) #{len} #{Ncurses.COLS} "
      @form.window.printstring 0, len-hlen, htext, @color_pair, @attr
    end
    ##
    ##
    # ADD HERE 
  end
end
