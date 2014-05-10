# ----------------------------------------------------------------------------- #
#         File: testsplitlayout.rb 
#  Description: 
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-05-09 - 20:24
#      License: MIT
#  Last update: 2014-05-10 19:15
# ----------------------------------------------------------------------------- #
# testsplitlayout.rb   Copyright (C) 2012-2014 j kepler

if __FILE__ == $PROGRAM_NAME
  require 'canis/core/util/app'
  require 'canis/core/widgets/listbox'
  require 'canis/core/include/layouts/splitlayout'
  App.new do

    # if i add form here, it will repaint them first, and have no dimensions
    lb = Listbox.new @form, :list => ["borodin","berlioz","bernstein","balakirev", "elgar"] , :name => "mylist"
    lb1 = Listbox.new @form, :list => ["bach","beethoven","mozart","gorecki", "chopin","wagner","grieg","holst"] , :name => "mylist1"


    alist = %w[ ruby perl python java jruby macruby rubinius rails rack sinatra pylons django cakephp grails] 
    str = "Hello, people of Earth.\nI am HAL, a textbox.\nUse arrow keys, j/k/h/l/gg/G/C-a/C-e/C-n/C-p\n"
    str << alist.join("\n")
    tv = TextPad.new @form, :name => "text", :text => str.split("\n")
    lb3 = Listbox.new @form, :list => alist , :name => "mylist3"
    lb2 = Listbox.new @form, :list => `gem list --local`.split("\n") , :name => "mylist2"

    w = Ncurses.COLS-1
    h = Ncurses.LINES-3
    #layout = StackLayout.new :height => -1, :top_margin => 1, :bottom_margin => 1, :left_margin => 1

       layout = SplitLayout.new :height => -1, :top_margin => 1, :bottom_margin => 1, :left_margin => 1
       @form.layout_manager = layout
       x,y = layout.vsplit( 0.30, 0.70)
       raise "X" unless x
       raise "Y" unless y
       ##x = arr.first
       #y = arr[1]
       $log.debug "XY:  #{x} , #{y}  "
       x.component = lb
       y1, y2 = y.split( 0.40, 0.60 )
       #y1.component = lb1
       y2.component = lb2
       y11,y12,y13 = y1.vsplit( 0.3, 0.3, 0.4)
       #y11,y12 = y1.vsplit( 0.4, 0.6)
       y11.component = lb1
       y12.component = tv
       y13.component = lb3

    st = status_line :row => -1
  end # app
end # if 
