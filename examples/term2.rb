require 'canis/core/util/app'
require 'canis/core/widgets/tabular'
require 'canis/core/widgets/scrollbar'

def my_help_text
  <<-eos
    term2.rb
    =========================================================================
    Basic Usage

    This example shows different ways of putting data in tabular format.

    The 2 tables on the right differ in behaviour. The first puts tabular data
    into a listbox so you get single/multiple selection. The second puts tabular
    data into a textview, so there's no selection. <space> scrolls instead of
    selects <ENTER> allows us to use the word under cursor for further actions.

    To see an example of placing tabular data in a tabular widget, see tabular.rb.
    The advantage of tabular_widget is column resizing, hiding, aligning and sorting.

    =========================================================================
    :n or Alt-n for next buffer. 'q' to quit.

  eos
end
App.new do
  header = app_header "canis #{Canis::VERSION}", text_center: 'Tabular Demo', text_right: 'New Improved!', color: :black, bgcolor: :white, attr: :bold
  message 'F10 quit, F1 Help, ? Bindings'
  # install_help_text my_help_text
  @form.help_manager.help_text = my_help_text

  flow width: FFI::NCurses.COLS, height: FFI::NCurses.LINES - 2 do
    stack margin_top: 1, width_pc: 20 do
      t = Tabular.new(%w[a b], [1, 2], [3, 4], [5, 6])
      listbox list: t.render

      t = Tabular.new %w[a b]
      t << [1, 2]
      t << [3, 4]
      t << [4, 6]
      t << [8, 6]
      t << [2, 6]
      # list_box :list => t.to_s.split("\n")
      listbox list: t.render
    end # stack

    file = File.expand_path('data/tasks.csv', __dir__)
    lines = File.open(file, 'r').readlines
    heads = %w[id sta type prio title]
    t = Tabular.new do |t|
      t.headings = heads
      lines.each { |e| t.add_row e.chomp.split '|' }
    end

    t = t.render
    wid = t[0].length + 2
    wid = 30
    stack margin_top: 1, width_pc: 80, height_pc: 100 do
      listbox list: t, title: '[ tasks ]', height_pc: 60

      r = `ls -l`
      res = r.split("\n")

      t = Tabular.new do
        #      self.headings = 'Perm', 'Gr', 'User', 'U',  'Size', 'Mon', 'Date', 'Time', 'File' # changed 2011 dts
        self.headings = 'User', 'Size', 'Mon', 'Date', 'Time', 'File'
        res.each do |e|
          cols = e.split
          next if cols.count < 6

          cols = cols[3..-1]
          cols = cols[0..5] if cols.count > 6
          add_row cols
        end
        column_width 1, 6
        align_column 1, :right
      end
      # lb =  list_box :list => t.render2
      lb = textview set_content: t.render, title: '[ls -l]', height_pc: 40
      lb.bind(:PRESS)  do |tae|
        alert "Pressed list on line #{tae.current_index}  #{tae.word_under_cursor(nil, nil, '|')}  "
      end
      Scrollbar.new @form, parent: lb
      # make a textview that is vienabled by default.
    end
  end
end
