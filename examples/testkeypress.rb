# demo to test keypresses
# press any key and see the value that ncurses or our routines catch. 
# Press alt and control combinations and Function keys
# Ideally each key should return only one value. Sometimes, some TERM setting
# or terminal emulator may not give correct values or may give different values
# from what we are expecting.
# Exit using 'q'.
# # see window.rb for keycodes related to shift+F C_LEFT C_RIGHT etc.
require 'logger'
require 'canis'
#require 'canis/core/widgets/rtextview'
if $0 == __FILE__
  include Canis
  include Canis::Utils

  begin
  # Initialize curses
    Canis::start_ncurses  # this is initializing colors via ColorMap.setup
    $log = Logger.new((File.join(ENV["LOGDIR"] || "./" ,"canis14.log")))

    $log.level = Logger::DEBUG

    @window = Canis::Window.root_window

    catch(:close) do
      colors = Ncurses.COLORS
      $log.debug "START #{colors} colors  ---------"
      @form = Form.new @window
      r = 1; c = 1;
      w = Ncurses.COLS - c
      h = Ncurses.LINES - 4

      # please use a hash to pass these values, avoid this old style
      # i want to move away from it as it comlpicates code
        texta = TextPad.new @form do
          name   "mytext" 
          row  r
          col  c
          width w
          height h
          #editable false
          focusable false
          title "[ Keypresses ]"
          #title_attrib (Ncurses::A_REVERSE | Ncurses::A_BOLD)
          title_attrib (Ncurses::A_BOLD)
        end
      help = "q to quit. Check keys. F1..10, C-a..z, Alt a-zA-Z0-9, C-left,rt, Sh-F5..10 .: #{$0}"
      help1 = "Press in quick succession: 1) M-[, w     and (2)  M-[, M-w.        (3)  M-Sh-O, w."  
      Canis::Label.new @form, {'text' => help, "row" => r+h+1, "col" => 2, "color" => "yellow"}
      Canis::Label.new @form, {'text' => help1, "row" => r+h+2, "col" => 2, "color" => "green"}
      texta.text = ["Press any key, Function, control, alt etc to see ","if it works.",
        "See window.rb for keycodes if something is not being trapped properly"]

      @form.repaint
      @window.wrefresh
      Ncurses::Panel.update_panels
      while((ch = @window.getchar()) != 999 )
        str = keycode_tos ch if ch.is_a? Fixnum
        $log.debug  "#{ch} got (#{str})"
        texta << "#{ch} got (#{str})"
        texta.goto_end
        texta.repaint
        @form.repaint
        @window.wrefresh
        #break if ch == ?\q.getbyte(0)
        break if ch == "q"
      end
    end
  rescue => ex
  ensure
    @window.destroy if !@window.nil?
    Canis::stop_ncurses
    p ex if ex
    p(ex.backtrace.join("\n")) if ex
    $log.debug( ex) if ex
    $log.debug(ex.backtrace.join("\n")) if ex
  end
end
