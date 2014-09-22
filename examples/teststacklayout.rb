# #!/usr/bin/env ruby -w
# ----------------------------------------------------------------------------- #
#         File: teststacklayout.rb
#  Description:
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-05-08 - 23:34
#      License: MIT
#  Last update: 2014-05-28 22:09
# ----------------------------------------------------------------------------- #

if __FILE__ == $PROGRAM_NAME
  require 'canis/core/util/app'
  require 'canis/core/widgets/listbox'
  require 'canis/core/include/layouts/stacklayout'
  App.new do


      @form.bind_key(FFI::NCurses::KEY_F3,'view log') {
        require 'canis/core/util/viewer'
        Canis::Viewer.view("canis14.log", :close_key => KEY_ENTER, :title => "<Enter> to close")
      }
    # if i add form here, it will repaint them first, and have no dimensions
    lb = Listbox.new @form, :list => ["borodin","berlioz","bernstein","balakirev", "elgar"] , :name => "mylist"
    lb1 = Listbox.new @form, :list => ["bach","beethoven","mozart","gorecki", "chopin","wagner","grieg","holst"] , :name => "mylist1"

    lb2 = Listbox.new @form, :list => `gem list --local`.split("\n") , :name => "mylist2"
=begin

    alist = %w[ ruby perl python java jruby macruby rubinius rails rack sinatra pylons django cakephp grails]
    str = "Hello, people of Earth.\nI am HAL, a textbox.\nUse arrow keys, j/k/h/l/gg/G/C-a/C-e/C-n/C-p\n"
    str << alist.join("\n")
    tv = TextPad.new @form, :name => "text", :text => str.split("\n")
=end

    w = Ncurses.COLS-1
    h = Ncurses.LINES-3
    #layout = StackLayout.new :height => -1, :top_margin => 1, :bottom_margin => 1, :left_margin => 1
    layout = StackLayout.new :height_pc => 1.0, :top_margin => 1, :bottom_margin => 1, :left_margin => 1
    layout.form = @form
    @form.layout_manager = layout
    layout.weightage lb, 7
    #layout.weightage lb1, 9
    #$status_message.value =" Flow: #{@r.components[0].orientation} | Stack #{@r.components[1].orientation}. Use Ctrl-Space to change "


    st = status_line :row => -1
  end # app
end # if
