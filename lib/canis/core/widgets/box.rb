# ------------------------------------------------------------ #
#         File: box.rb 
#  Description: draws a box around some group of items
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 06.11.11 - 18:22 
#  Last update: 06.11.11 - 19:53
# ------------------------------------------------------------ #
#
require 'canis'
require 'canis/core/include/bordertitle'
include Canis
#include Canis::BorderTitle

# @example
#
# At a later stage, we will integrate this with lists and tables, so it will happen automatically.
#
# @since 1.4.1    UNTESTED
module Canis
  class Box < Widget

    include BorderTitle

    # margin for placing widgets inside
    # This is not used inside here, but is used by stacks.
    # @see widgetshortcuts.rb
    dsl_accessor :margin_left, :margin_top

    def initialize form, config={}, &block

      bordertitle_init
      super
      @window = form.window if @form
      @editable = false
      @focusable = false
      #@height += 1 # for that silly -1 that happens
      @repaint_required = true
    end

    ##
    # repaint the scrollbar
    def repaint
      return unless @repaint_required
      bc = $datacolor
      bordercolor = @border_color || bc
      borderatt = @border_attrib || Ncurses::A_NORMAL
      @window.print_border row, col, height, width, bordercolor, borderatt
      #print_borders
      print_title
      @repaint_required = false
    end
    ##
    ##
    # ADD HERE 
  end
end
if __FILE__ == $PROGRAM_NAME
end
