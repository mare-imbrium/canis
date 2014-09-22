require 'canis/core/util/app'
require 'canis/core/widgets/listfooter'
require 'canis/core/util/promptmenu'

App.new do
  # TODO: combine this with widget menu
  def app_menu
      menu = PromptMenu.new self do
        item :e, :edit
        item :o, :open_new
        item :d, :delete_row
        item :u, :undo_delete
        #item :y, :yank
        #item :p, :paste
        item :/, :search
        item :w, :write
      end
      menu.display_new :title => "Menu"
  end
  # to execute when app_menu is invoked
  # very tricky , this depends on the keys that have been mapped
  # Here we are pushing the mapped key to trigger a method.
  # FIXME NOTE these have stopped working since I think i now clear keys
  #  after a key is processed, so unget will not work.
  #  Use +handle_key+ instead of +ungetch+, although that won't work if multiple
  #   keys involved.
  def execute_this *cmd
    cmd = cmd[0][0] # extract first letter of command
    cmdi = cmd.getbyte(0)
    tw = @form.by_name["tab"]
    case cmd
    when 'e','o','p'
      #@window.ungetch cmdi
      tw.handle_key cmdi
    when 'd'
      tw.delete_row
    when 'y','d'
      # won't work FIXME
      tw.handle_key cmdi
      #tw.handle_key cmdi
      @window.ungetch cmdi
      #@window.ungetch cmdi
    when 'u'
      tw.undo_delete
      #tw.handle_key cmd.upcase.getbyte(0)
      #@window.ungetch cmd.upcase.getbyte(0)
    when 's'
      tw.handle_key ?\/.getbyte(0)
      #@window.ungetch ?\/.getbyte(0)
    when 'w'
      # this depends too much on mappings which can change
      #@window.ungetch ?\C-s.getbyte(0)
      tw = @form.by_name["tab"]
      tw.save_as(nil)
    end
  end
def help_text
    <<-eos
         Help for Tables
         ---------------

         Keys that can be used on header

    <ENTER>     - sort given field (press on header)

         Keys that can be used on data rows

    <v>         - select a row
    <V>         - range select
    <u>         - unselect all (conflicts with vim keys!!)
    <a>         - select all
    <*>         - invert selection

    </>         - <slash> for searching,
                  <n> to continue searching

    Keys specific to this example

    <e>         - edit current row
    <dd>        - delete current row or <num> rows
    <o>         - insert a row after current one
    <U>         - undo delete

         Motion keys

    Usual for [[list]] and [[textpad]] such as :
    j, k, h, l
    w and b for (next/prev) column
    C-d and C-b
    gg and G

    [[table]]  |   [[index]]
    eos
end
def edit_row tw
  row = tw.current_value
  h   = tw.columns
  ret = _edit h, row, " Edit "
  if ret
    tw[tw.current_index] = row
  end
end
def insert_row tw
  h   = tw.columns
  row = []
  h.each { |e| row << "" }
  ret = _edit h, row, "Insert"
  loc = tw.current_index
  # don't insert above header
  loc = 1 if loc == 0
  if ret
    tw.insert loc, row
  end
end

# making a generic edit messagebox - quick dirty
def _edit h, row, title
  _l = longest_in_list h
  _w = _l.size
  config = { :width => 70, :title => title }
  bw = get_color $datacolor, :black, :white
  mb = MessageBox.new config do
    h.each_with_index { |f, i|
      add LabeledField.new :label => "%*s:" % [_w, f], :text => row[i].chomp, :name => i.to_s,
        :bgcolor => :cyan,
        :width => 50,
        :label_color_pair => bw
    }
    button_type :ok_cancel
  end
  index = mb.run
  return nil if index != 0
  h.each_with_index { |e, i|
    f = mb.widget(i.to_s)
    row[i] = f.text
  }
  row
end
# delete current row
# ideally one should include listeditable to get events also
def delete_row tw=nil
  tw ||= @form.by_name["tab"]
  @undo_buffer = tw.current_value
  tw.delete_at tw.current_index
end
# very minimal undo, just for a demo
# Keeps pasting undo buffer back. @see listeditable.rb
def undo_delete tw=nil
  return unless @undo_buffer
  tw ||= @form.by_name["tab"]
  tw.insert tw.current_index, @undo_buffer
end
def resize
  tab = @form.by_name["tab"]
  cols = Ncurses.COLS
  rows = Ncurses.LINES
  tab.width_pc ||= (1.0*tab.width / $orig_cols)
  tab.height_pc ||= (1.0*tab.height / $orig_rows)
  tab.height = (tab.height_pc * rows).floor
  tab.width = (tab.width_pc * cols).floor
end

=begin

lf = Canis::ListFooter.new :attrib => BOLD
lf.command(lf){ |comp, lf|
  f = lf[0]
  if comp.current_index == 0
    f.attrib = REVERSE
    " Header "
  else
    f.attrib = BOLD
  "#{comp.current_index} of #{comp.size} "
  end
}
lf.command_right(){ |comp|
  " [#{comp.size} tasks]"
}
=end
  header = app_header "canis #{Canis::VERSION}", :text_center => "Table Demo", :text_right =>": menu",
      :color => :black, :bgcolor => :green #, :attr => :bold
  message "Press F10 to exit, F1 for help, : for menu"
  @form.help_manager.help_text = help_text()
  $orig_cols = Ncurses.COLS
  $orig_rows = Ncurses.LINES

  h = %w[ Id Title Priority Status]
  file = File.expand_path("../data/table.txt", __FILE__)

  flow :margin_top => 1, :height => FFI::NCurses.LINES-2 do
    tw = table :print_footer => true, :name => "tab"
    tw.filename(file, :delimiter => '|', :columns => h)
    #tw.columns h
    #tw.text arr
    tw.column_align 0, :right
    tw.model_row 1
    #tw.list_footer lf
    tw.estimate_column_widths
    #tw.selection_mode :single
    # set_content goes to textpads text which overwrites @list
    #tw.set_content arr
    tw.bind_key([?d,?d], 'delete row') { delete_row tw }
    tw.bind_key(?U, 'undo delete') { undo_delete tw }
    tw.bind_key(?e, 'edit row') {  edit_row tw }
    tw.bind_key(?o, 'insert row') {  insert_row tw }
    tw.create_default_sorter

  end # stack
  status_line :row => FFI::NCurses.LINES-1
  @form.bind_key(?:, 'menu') {  app_menu }
  @form.bind(:RESIZE) {  resize }
end # app
