# #!/usr/bin/env ruby -w
# -------------------------------------------------------------------------- #
#         File: teststacklayout.rb
#  Description:
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-05-08 - 23:34
#      License: MIT
#  Last update: 2019-03-12 14:29
# -------------------------------------------------------------------------- #

if $PROGRAM_NAME == __FILE__
  require 'canis/core/util/app'
  require 'canis/core/widgets/listbox'
  require 'canis/core/widgets/table'
  require 'canis/core/include/layouts/stacklayout'
  App.new do
    $log = create_logger('stack.log')
    @form.bind_key(FFI::NCurses::KEY_F3, 'view log') do
      require 'canis/core/util/viewer'
      Canis::Viewer.view('canis14.log',
                         close_key: KEY_ENTER,
                         title: '<Enter> to close')
    end

    lb1 = Table.new @form, name: 'mylist1'
    lb1.columns = ['column']
    %w[bach beethoven mozart gorecki chopin wagner grieg holst].each do |row|
      lb1 << [row]
    end
    lb = Listbox.new @form,
                     list: %w[borodin berlioz bernstein balakirev elgar],
                     name: 'mylist'
    lb2 = Listbox.new @form,
                      list: `gem list --local`.split("\n"),
                      name: 'mylist2'

    # w = Ncurses.COLS - 1
    # h = Ncurses.LINES - 3
    # layout = StackLayout.new :height => -1, :top_margin => 1, :bottom_margin => 1, :left_margin => 1
    layout = StackLayout.new height_pc: 1.0,
      top_margin: 1,
      bottom_margin: 1,
      left_margin: 1
    layout.form = @form
    @form.layout_manager = layout
    layout.weightage lb, 7
    # layout.weightage lb1, 9

    st = status_line row: -1
  end
end
