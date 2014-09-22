require 'canis/core/util/app'
require 'canis/core/util/rcommandwindow'
require 'fileutils'
require 'pathname'
require 'canis/core/include/defaultfilerenderer'
require_relative './common/devel.rb'

# this will go into top namespace so will conflict with other apps!
def testnumberedmenu
  list1 =  %w{ ruby perl python erlang rake java lisp scheme chicken }
  list1[0] = %w{ ruby ruby1.9 ruby1.8.x jruby rubinius ROR }
  list1[5] = %w{ java groovy grails }
  str = numbered_menu list1, { :title => "Languages: ", :prompt => "Select :" }
  $log.debug "17 We got #{str.class} "
  message "We got #{str} "
end
def testdisplay_list
  # scrollable filterable list
  text = Dir.glob "*.rb"
  $log.debug "DDD got #{text.size} "
  str = display_list text, :title => "Select a file"
  #$log.debug "23 We got #{str} :  #{str.class} , #{str.list[str.current_index]}  "
  $log.debug "23 We got #{str} "
  #file = str.list[str.current_index]
  file = str
  #message "We got #{str.list[str.current_index]} "
  show file if file
end
def testdisplay_text
  #str = display_text_interactive File.read($0), :title => "#{$0}"
  str = display_text $0, :title => "#{$0}"
end
def testdir
  # this behaves like vim's file selector, it fills in values
  str = rb_gets("File?  ", Pathname)  do |q|
    #q.completion_proc = Proc.new {|str| Dir.glob(str +"*").collect { |f| File.directory?(f) ? f+"/" : f  } }
    q.help_text = "Enter start of filename and tab to get completion"
  end
  message "We got #{str} "
  show str
end
# if components have some commands, can we find a way of passing the command to them
# method_missing gave a stack overflow.
def execute_this(meth, *args)
  alert " #{meth} not found ! "
  $log.debug "app email got #{meth}  " if $log.debug?
  cc = @form.get_current_field
  [cc].each do |c|
    if c.respond_to?(meth, true)
      c.send(meth, *args)
      return true
    end
  end
  false
end

App.new do
  @startdir ||= File.expand_path("..")
  def show file
    w = @form.by_name["tv"]
    if File.directory? file
      lines = Dir.entries(file)
      w.text lines
      w.title "[ #{file} ]"
    elsif File.exists? file
      lines = File.open(file,'r').readlines
      w.text lines
      w.title "[ #{file} ]"
    end
  end
  def testchoosedir
    # list filters as you type
    $log.debug "called CHOOSE " if $log.debug?
    str = choose_file  :title => "Select a file",
      :recursive => true,
      :dirs => true,
      :directory => @startdir,
      :help_text => "Enter pattern, use UP DOWN to traverse, Backspace to delete, ENTER to select. Esc-Esc to quit"
    if str
      message "We got #{str} "
      show str
    end
  end
  def testchoosefile
    # list filters as you type a pattern
    glob = "**/*.rb"
    str = choose_file  glob, :title => "Select a file",
      :directory => @startdir,
      :help_text => "Enter pattern, use UP DOWN to traverse, Backspace to delete, ENTER to select. Esc-Esc to quit"
    if str and str != ""
      message "We got #{str} "
      show str
    end
  end
  ht = 24
  borderattrib = :reverse
  @header = app_header "canis #{Canis::VERSION}", :text_center => "rCommandline Test",
    :text_right =>"Press :", :color => :white, :bgcolor => 236
  message "Press F10 (or qq) to exit, F1 Help, : for Menu  "



    # commands that can be mapped to or executed using M-x
    # however, commands of components aren't yet accessible.
    def get_commands
      %w{ testchoosedir testchoosefile testnumberedmenu testdisplay_list testdisplay_text testdir }
    end
    def help_text
      <<-eos
               rCommandLine HELP

      These are some features for either getting filenames from user
      at the bottom of the window like vim and others do, or filtering
      from a list (like ControlP plugin). Or seeing a file at bottom
      of screen for a quick preview.

      :        -   Command mode
      F1       -   Help
      F10      -   Quit application
      qq       -   Quit application
      =        -   file selection (interface like Ctrl-P, very minimal)

      Some commands for using bottom of screen as vim and emacs do.
      These may be selected by pressing ':'

      testchoosedir       - filter directory list as you type
                            '>' to step into a dir, '<' to go up.
      testchoosefile       - filter file list as you type
                             ENTER to select, C-c or Esc-Esc to quit
      testdir          - vim style, tabbing completes matching files
      testnumberedmenu - use menu indexes to select options
      testdisplaylist  - display a list at bottom of screen
                         Press <ENTER> to select, arrow keys to traverse,
                         and characters to filter list.
      testdisplaytext  - display text at bottom (current file contents)
                         Press <ENTER> when done.

      The file/dir selection options are very minimally functional. Improvements
      and thorough testing are required. I've only tested them out gingerly.

      testchoosedir and file were earlier like Emacs/memacs with TAB completion
      but have now moved to the much faster and friendlier ControlP plugin like
      'filter as you type' format.

      -----------------------------------------------------------------------
      :n or Alt-n for general help.
      eos
    end

    #install_help_text help_text

    def app_menu
      @curdir ||= Dir.pwd
      Dir.chdir(@curdir) if Dir.pwd != @curdir
      require 'canis/core/util/promptmenu'
      menu = PromptMenu.new self do
        item :c, :testchoosedir
        item :f, :testchoosefile
        item :d, :testdir
        item :n, :testnumberedmenu
        item :l, :testdisplay_list
        item :t, :testdisplay_text
      end
      menu.display_new :title => "Menu"
    end
  @form.bind_key(?:, "App Menu") { app_menu; }
  @form.bind_key(?=, "Choose File") {
      @curdir ||= Dir.pwd
      Dir.chdir(@curdir) if Dir.pwd != @curdir
    #testdisplay_list;
    testchoosefile;
  }

  stack :margin_top => 1, :margin_left => 0, :width => :expand , :height => FFI::NCurses.LINES-2 do
    tv = textview :height_pc => 100, :width_pc => 100, :name => "tv", :suppress_borders => true
    tv.renderer ruby_renderer
  end # stack

  sl = status_line :row => Ncurses.LINES-1
  testdisplay_list
end # app
