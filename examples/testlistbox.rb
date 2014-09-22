# NOTE: If the listbox is empty, that could mean that you have not generated
#  ri documentation for this version of ruby. You can do so by doing:
#    rvm docs generate-ri
#    or
#    rvm docs generate
#  (This assumes you are using rvm)
#
# WARNING : IF THIS PROGRAM HANGS check the ri command
# Maybe your version of ri has different options and is going interactive.
# ruby 1.9.3's ri requires a -l option or else if becomes interactive.
# this program tests out a listbox
# This is written in the old style where we start and end ncurses and initiate a
# getch loop. It gives more control.
# The new style is to use App which does the ncurses setup and teardown, as well
# as manages keys. It also takes care of logger and includes major stuff.
# NOTE : this is the new listbox (based on Textpad version, the original
#  version has been moved to deprecated. 2014-04-08 - 18:32
require 'logger'
require 'canis'
require 'canis/core/widgets/listbox'
require 'canis/core/include/vieditable'
#require 'canis/experimental/widgets/undomanager'
class Canis::Listbox
  # vieditable includes listeditable which
  # does bring in some functions which can crash program like x and X TODO
  # also, f overrides list f mapping. TODO
  include ViEditable
end
def get_data str
        #lines = `ri -f bs #{str}`.split("\n")
  lines = `ri -f ansi #{str} 2>&1`.gsub('[m','[0m').split("\n")
end
  def my_help_text
    <<-eos

=========================================================================
## Basic Usage

Press <ENTER> on a class name on the first list, to view `ri` information
for it on the right.

Tab to right box, navigate to a method name, and press <ENTER> on a method
name, to see its details in a popup screen.
Press */* <slash> in any box to search. e.g "/String" will take you to the
first occurrence of "String". <n> will take you to the next match.

To go quickly to the first Class starting with 'S', type <f> followed by <S>.
Then press <n> to go to next match.

=========================================================================
## Vim Edit Keys

The [[list]] on left has some extra vim keys enabled such as :
>
    yy     - yank/copy current line/s
    P, p   - paste after or before
    dd     - delete current line
    o      - insert a line after this one
    C      - change content of current line
<
These are not of use here, but are demonstrative of list capabilities.

=========================================================================
## Buffers

Ordinary a [[textpad]] contains only one buffer. However, the one on the right
is extended for multiple buffers. Pressing <ENTER> on the left on several
rows opens multiple buffers on the right. Use <M-n> (Alt-N) and <M-p> to navigate.
ALternatively, <:> maps to a menu, so :n and :p may also be used.
<BACKSPACE> will also go to previous buffer, like a browser.

=========================================================================
       Press <M-n> for next help screen, or try ":n", [[index]]

    eos
  end
if $0 == __FILE__
  include Canis

  begin
  # Initialize curses
    Canis::start_ncurses  # this is initializing colors via ColorMap.setup
    path = File.join(ENV["LOGDIR"] || "./" ,"canis14.log")
    logfilename   = File.open(path, File::WRONLY|File::TRUNC|File::CREAT)
    $log = Logger.new(logfilename)
    $log.level = Logger::DEBUG

    @window = Canis::Window.root_window
    $log.debug "  WINDOW #{FFI::NCurses.LINES} "
    $catch_alt_digits = true; # emacs like alt-1..9 numeric arguments
    # Initialize few color pairs
    # Create the window to be associated with the form
    # Un post form and free the memory

    catch(:close) do
      @form = Form.new @window
      @form.help_manager.help_text = my_help_text
      #@form.bind_key(KEY_F1, 'help'){ display_app_help }

      # this is the old style of printing something directly on the window.
      # The new style is to use a header
      @form.window.printstring 0, 30, "Demo of Listbox - some vim keys", $normalcolor, BOLD
      r = 1; fc = 1;

      # this is the old style of using a label at the screen bottom, you can use the status_line

      v = "F10 quits. F1 Help.  Try j k gg G o O C dd f<char> w yy p P / . Press ENTER on Class or Method"
      var = Canis::Label.new @form, {'text' => v, "row" => FFI::NCurses.LINES-2,
        "col" => fc, "width" => 100}

      h = FFI::NCurses.LINES-3
      file = "./data/ports.txt"
      #mylist = File.open(file,'r').readlines
      mylist = `ri -l `.split("\n")
      w = 25
      #0.upto(100) { |v| mylist << "#{v} scrollable data" }
      #
      listb = Listbox.new @form, :name   => "mylist" ,
        :row  => r ,
        :col  => 1 ,
        :width => w,
        :height => h,
        :list => mylist,
        :selection_mode => :single,
        :show_selector => true,
        #row_selected_symbol "[X] "
        #row_unselected_symbol "[ ] "
        :title => " Ruby Classes "
        #title_attrib 'reverse'
      #listb.one_key_selection = false # this allows us to map keys to methods
      listb.vieditable_init_listbox
      include Io
      listb.bind_key(?r, 'get file'){ get_file("Get a file:") }
      listb.bind(:PRESS) {
        w = @form.by_name["tv"];
        #lines = `ri -f bs #{listb.current_value}`.split("\n")
        #lines = `ri -f ansi #{listb.current_value} 2>&1`.gsub('[m','[0m').split("\n")
        lines = get_data listb.current_value
        #w.set_content(lines, :ansi)
        w.add_content(lines, {:content_type => :ansi, :title => listb.current_value})
        w.buffer_last
        #w.title = listb.current_value
      }

      tv = Canis::TextPad.new @form, :row => r, :col => w+1, :height => h, :width => FFI::NCurses.COLS-w-1,
      :name => "tv", :title => "Press Enter on method"
      tv.set_content ["Press Enter on list to view ri information in this area.",
        "Press ENTER on method name to see details"]
      require 'canis/core/include/multibuffer'
      tv.extend(Canis::MultiBuffers)
      # with format 'bs' we had a '=' but now it is colored so we've lost section.
      tv.text_patterns[:section] = Regexp.new(/^= /)
      tv.bind_key(?s, "goto section") { tv.next_regex(:section) }

      # pressing ENTER on a method name will popup details for that method
      tv.bind(:PRESS) { |ev|
        w = ev.word_under_cursor.strip
        # check that user did not hit enter on empty area
        if w != ""
          #_text = `ri -f bs #{tv.title}.#{w} 2>&1`
          #_text = _text.split("\n")
          _text = get_data "#{tv.title}.#{w}"
          if _text && _text.size != 0
            view(_text, :content_type => :ansi)
          end
        end
      }


    @form.repaint
    @window.wrefresh
    Ncurses::Panel.update_panels
    while((ch = @window.getchar()) != KEY_F10 )
      @form.handle_key(ch)
      @window.wrefresh
    end
  end
rescue => ex
  $log.debug( ex) if ex
  $log.debug(ex.backtrace.join("\n")) if ex
ensure
  @window.destroy if !@window.nil?
  Canis::stop_ncurses
  p ex if ex
  p(ex.backtrace.join("\n")) if ex
end
end
