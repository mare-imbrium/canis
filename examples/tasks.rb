require 'canis/core/util/app'
#require 'canis/core/widgets/rlist'

App.new do 
def resize
  tab = @form.by_name["tasklist"]
  cols = Ncurses.COLS
  rows = Ncurses.LINES
  tab.width_pc ||= (1.0*tab.width / $orig_cols)
  tab.height_pc ||= (1.0*tab.height / $orig_rows)
  tab.height = (tab.height_pc * rows).floor
  tab.width = (tab.width_pc * cols).floor
  #$log.debug "XXX:  RESIZE h w #{tab.height} , #{tab.width} "
end
  @default_prefix = " "
  header = app_header "canis #{Canis::VERSION}", :text_center => "Task List", :text_right =>"New Improved!"

  message "Press F10 or qq to quit "

  file = "data/todo.txt"
  alist = File.open(file,'r').read.split("\n") if File.exists? file
  #flow :margin_top => 1, :item_width => 50 , :height => FFI::NCurses.LINES-2 do
  #stack :margin_top => 1, :width => :expand, :height => FFI::NCurses.LINES-4 do

    #task = field :label => "    Task:", :width => 50, :maxlen => 80, :bgcolor => :cyan, :color => :black
    #pri = field :label => "Priority:", :width => 1, :maxlen => 1, :type => :integer, 
      #:valid_range => 1..9, :bgcolor => :cyan, :color => :black , :default => "5"
    #pri.overwrite_mode = true
    # u,se voerwrite mode for this TODO and catch exception

    # modify the default file renderer
    dr = DefaultFileRenderer.new
    dr.insert_mapping /^x/, [:blue, :black]
    dr.insert_mapping /^.1/, [:white, :blue]
    dr.insert_mapping /^.2/, [:red, :blue]
    dr.insert_mapping /^.3/, [:white, :black]
    dr.insert_mapping /^.4/, [:green, :black]
    dr.insert_mapping /^.5/, [:red, :black]
    dr.insert_mapping /^.6/, [:cyan, :black]
    dr.insert_mapping /^.[7-9]/, [:magenta, :black]

    $data_modified = false
    lb = listbox :list => alist.sort, :title => "[ todos ]", :name => "tasklist", :row => 1, :height => Ncurses.LINES-4, :width => Ncurses.COLS-1
    lb.should_show_focus = false
    lb.renderer dr
    lb.bind_key(?d, "Delete Row"){ 
      if confirm("Delete #{lb.current_value} ?")
        lb.delete_at lb.current_index 
        $data_modified = true
        # TODO reposition cursor at 0. use list_data_changed ?
      end
    }
    lb.bind_key(?e, "Edit Row"){ 
      if ((value = get_string("Edit Task:", :width => 80, :default => lb.current_value, :maxlen => 80, :width => 70)) != nil)

        lb[lb.current_index]=value
        $data_modified = true
      end
    }
    lb.bind_key(?a, "Add Record"){ 

      # ADD
    task = Field.new :label => "    Task:", :width => 60, :maxlen => 80, :bgcolor => :cyan, :color => :black,
    :name => 'task'
    pri = Field.new :label => "Priority:", :width => 1, :maxlen => 1, :type => :integer, 
      :valid_range => 1..9, :bgcolor => :cyan, :color => :black , :default => "5", :name => 'pri'
    pri.overwrite_mode = true
    config = {}
    config[:width] = 80
    config[:title] =  "New Task"
    tp = MessageBox.new config do
      item task
      item pri
      button_type :ok_cancel
      default_button 0
    end
    index = tp.run
    if index == 0 # OK
      # when does this memory get released ??? XXX 
      _t = tp.form.by_name['pri'].text 
      if _t != ""
        val =  @default_prefix + tp.form.by_name['pri'].text + ". " + tp.form.by_name['task'].text 
        w = @form.by_name["tasklist"]
        _l = w.list
        _l << val
        w.list(_l.sort)
        $data_modified = true
      end
    else # CANCEL
      #return nil
    end
    }
    # decrease priority
    lb.bind_key(?-, 'decrease priority'){ 
      line = lb.current_value
      p = line[1,1].to_i
      if p < 9
        p += 1 
        line[1,1] = p.to_s
        lb[lb.current_index]=line
        lb.list(lb.list.sort)
        $data_modified = true
      end
    }
    # increase priority
    lb.bind_key(?+, 'increase priority'){ 
      line = lb.current_value
      p = line[1,1].to_i
      if p > 1
        p -= 1 
        line[1,1] = p.to_s
        lb[lb.current_index]=line
        lb.list(lb.list.sort)
        $data_modified = true
        # how to get the new row of that item and position it there. so one
        # can do consecutive increases or decreases
        # cursor on old row, but current has become zero. FIXME
        # Maybe setform_row needs to be called
      end
    }
    # mark as done
    lb.bind_key(?x, 'mark done'){ 
      line = lb.current_value
      line[0,1] = "x"
      lb[lb.current_index]=line
      lb.list(lb.list.sort)
      $data_modified = true
    }
    # flag task with a single character
    lb.bind_key(?!, 'flag'){ 
      line = lb.current_value.chomp
      value = get_string("Flag for #{line}. Enter one character.", :maxlen => 1, :width => 1)
      #if ((value = get_string("Edit Task:", :width => 80, :default => lb.current_value)) != nil)
        #lb[lb.current_index]=value
      #end
      if value ##&& value[0,1] != " "
        line[0,1] = value[0,1]
        lb[lb.current_index]=line
        lb.list(lb.list.sort)
        $data_modified = true
      end
    }
  #end # stack
  s = status_line
  @form.bind(:RESIZE) {  resize }

    keyarray = [
      ["F1" , "Help"], ["F10" , "Exit"], 
      ["F2", "Menu"], ["F4", "View"],
      ["d", "delete item"], ["e", "edit item"],
      ["a", "add item"], ["x", "close item"],
      ["+", "inc priority"], ["-", "dec priority"],

      ["M-x", "Command"], nil
    ]

    gw = get_color($reversecolor, 'green', 'black')
    @adock = dock keyarray, { :row => Ncurses.LINES-2, :footer_color_pair => $datacolor, 
      :footer_mnemonic_color_pair => gw }

  @window.confirm_close_command do
    confirm "Sure you wanna quit?", :default_button => 1
  end
  @window.close_command do
    if $data_modified
    w = @form.by_name["tasklist"]
    if confirm("Save tasks?", :default_button => 0)
      system("cp #{file} #{file}.bak")
      File.open(file, 'w') {|f| 
        w.list.each { |e|  
          f.puts(e) 
        } 
      } 
    end
    end # if modif
  end
  
end # app
