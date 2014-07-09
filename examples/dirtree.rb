require 'canis/core/util/app'
require 'fileutils'
require 'canis/core/widgets/tree/treemodel'
#require 'canis/common/file'
require './common/file'
require './common/devel'

def _directories wd
  $log.debug " directories got :#{wd}: "
  wd ||= ""
  return [] if wd == ""
  d = Dir.new(wd)
  ent = d.entries.reject{|e| !File.directory? File.join(wd,e)}
  $log.debug " directories got XXX: #{ent} "
  ent.delete(".");ent.delete("..")
  return ent
end
#$log = create_logger "canis.log"
App.new do 
  def help_text
    <<-eos

=========================================================================
## Basic Usage

### Left Window

   <ENTER>    expand/collapse directories
   v          select and list a directory in other window

  See also [tree]

### Right Window

  <ENTER>    enter a directory
  <ENTER>    open a file in 'EDITOR'
  v          page a file using 'PAGER'

  See also [list]

[index]
      eos
  end
  # print the dir list on the right listbox upon pressing ENTER or row_selector (v)
  # separated here so it can be called from two places.
  def lister node
    path = File.join(*node.user_object_path)
    populate path
  end

  def populate path
    ll = @form.by_name["ll"]
    return unless ll
    if File.exists? path
      files = Dir.new(path).entries
      files.delete(".")
      ll.clear_selection
      ll.list files 
      ll.title path
      #TODO show all details in filelist
      @current_path = path
      return path
    end
  end
  header = app_header "canis #{Canis::VERSION}", :text_center => "Dorado", :text_right =>"Directory Lister" , :color => :white, :bgcolor => 242 #, :attr =>  Ncurses::A_BLINK
  message "Press Enter to expand/collapse, v to view in lister. <F1> Help"
  @form.help_manager.help_text = help_text()

  pwd = Dir.getwd
  entries = _directories pwd
  patharray = pwd.split("/")
  # we have an array of path, to add recursively, one below the other
  nodes = []
  nodes <<  TreeNode.new(patharray.shift)
  patharray.each do |e| 
    nodes <<  nodes.last.add(e)
  end
  last = nodes.last
  nodes.last.add entries
  model = DefaultTreeModel.new nodes.first
  model.root_visible = false
     


  ht = FFI::NCurses.LINES - 2
  borderattrib = :normal
  flow :margin_top => 1, :margin_left => 0, :width => :expand, :height => ht do
    @t = tree :data => model, :width_pc => 30, :border_attrib => borderattrib
    rend = @t.renderer # just test method out.
    rend.row_selected_attr = BOLD
    @t.bind :TREE_WILL_EXPAND_EVENT do |node|
      path = File.join(*node.user_object_path)
      dirs = _directories path
      ch = node.children
      ch.each do |e| 
        o = e.user_object
        if dirs.include? o
          dirs.delete o
        else
          # delete this child since its no longer present TODO
        end
      end
      #message " #{node} will expand: #{path}, #{dirs} "
      node.add dirs
      lister node
    end
    @t.bind :TREE_WILL_COLLAPSE_EVENT do |node|
      # FIXME do if ony not already showing on other side
      lister node
    end
    @t.bind :TREE_SELECTION_EVENT do |ev|
      if ev.state == :SELECTED
        node = ev.node
        lister node
      end
    end # select
    #$def_bg_color = :blue
    @form.bgcolor = :blue
    @t.expand_node last # 
    @t.mark_parents_expanded last # make parents visible
    @l = listbox :width_pc => 70, :border_attrib => borderattrib, :selection_mode => :single, :name => 'll',
      :left_margin => 1
    @l.renderer directory_renderer(@l)
    @l.renderer().row_focussed_attr = REVERSE

    @l.bind :LIST_SELECTION_EVENT  do |ev|
      message ev.source.current_value #selected_value
      _f = File.join(@current_path, ev.source.current_value)
      file_page   _f if ev.type == :INSERT
      #TODO when selects drill down
      #TODO when selecting, sync tree with this
    end
    # on pressing enter, we edit the file using vi or EDITOR
    @l.bind :PRESS  do |ev|
      _f = File.join(@current_path, ev.source.current_value)
      if File.directory? _f
        populate _f
      else
        file_edit _f if File.exists? _f
      end
    end
  end
  status_line :row => FFI::NCurses.LINES - 1
end # app
