require 'canis/core/widgets/textpad'
require 'canis/core/widgets/applicationheader'
require 'fileutils'

# A file or array viewer.
#
# CHANGES
#   - 2014-04-09 - 00:58 changed textview to textpad 
# Can be used for print_help_page
# SUGGESTIONS WELCOME.
# NOTE: since this is not a proper class / object, it is being hacked to pieces
#  We need to either make this a proper class, or else make another one with a class,
#  and use this for simple purposes only. 

module Canis
  # a data viewer for viewing some text or filecontents
  # view filename, :close_key => KEY_ENTER
  # send data in an array
  # view Array, :close_key => KEY_ENTER, :layout => [23,80,0,0] (ht, wid, top, left)
  # when passing layout reserve 4 rows for window and border. So for 2 lines of text
  # give 6 rows.
  class Viewer
    # @param filename as string or content as array
    # @yield textview object for further configuration before display
    def self.view what, config={}, &block  #:yield: textview
      case what
      when String # we have a path
        content = _get_contents(what)
      when Array
        content = what
      else
        raise ArgumentError, "Viewer: Expecting Filename or Contents (array), but got #{what.class} "
      end
      wt = 0 # top margin
      wl = 0 # left margin
      wh = Ncurses.LINES-wt # height, goes to bottom of screen
      ww = Ncurses.COLS-wl  # width, goes to right end
      layout = { :height => wh, :width => ww, :top => wt, :left => wl } 
      if config.has_key? :layout
        layout = config[:layout]
        case layout
        when Array
          #wt, wl, wh, ww = layout
          # 2014-04-27 - 11:22 changed to the same order as window, otherwise confusion and errors
          wh, ww, wt, wl = layout
          layout = { :height => wh, :width => ww, :top => wt, :left => wl } 
        when Hash
          # okay
        end
      end

      fp = config[:title] || ""
      pf = config.fetch(:print_footer, true)
      ta = config.fetch(:title_attrib, 'bold')
      fa = config.fetch(:footer_attrib, 'bold')
      wbg = config.fetch(:window_bgcolor, nil)
      b_ah = config[:app_header]
      type = config[:content_type]

      v_window = Canis::Window.new(layout)
      v_form = Canis::Form.new v_window
      v_window.name = "Viewer"
      if wbg
        v_window.wbkgd(Ncurses.COLOR_PAIR(wbg)); #  does not work on xterm-256color
      end
      # I am placing this in globals since an alert on top will refresh the lower windows and this is quite large.
      $global_windows << v_window
      colors = Ncurses.COLORS
      back = :blue
      back = 235 if colors >= 256
      blue_white = get_color($datacolor, :white, back)

      tprow = 0
      ah = nil
      if b_ah
        ah = ApplicationHeader.new v_form, "", :text_center => fp
        tprow += 1
      end

      #blue_white = Canis::Utils.get_color($datacolor, :white, 235)
      textview = TextPad.new v_form do
        name   "Viewer" 
        row  tprow
        col  0
        width ww
        height wh-tprow # earlier 2 but seems to be leaving space.
        title fp
        title_attrib ta
        print_footer pf
        footer_attrib fa
        #border_attrib :reverse
        border_color blue_white
      end
      # why multibuffers  -- since used in help
      require 'canis/core/include/multibuffer'
      textview.extend(Canis::MultiBuffers)

      t = textview
      t.bind_key(Ncurses::KEY_F5, 'maximize window '){ f = t.form.window; 
        f.resize_with([FFI::NCurses.LINES-0, Ncurses.COLS, 0,0]); 
        #f.resize_with([0,0, 0,0]); 
        t.height = Ncurses.LINES - t.row - 0
      }
      t.bind_key(Ncurses::KEY_F6, 'restore window ', layout){ |l,m, n| 
        # l was DefaultKeyHandler, m was string, n was Hash
        f = t.form.window; 
        #$log.debug "  F6 ARG is #{m}, #{n}"
        f.hide; # need to hide since earlier window was larger.
        f.resize_with(n);
        #f.resize_with([0,0, 0,0]); 
        t.height =  f.height - t.row - 0
        f.show
      }
      t.bind_key(?\C-\], "open file under cursor") { 
        eve = t.text_action_event
        file = eve.word_under_cursor.strip
        if File.exists? file
          t.add_content file
          t.buffer_last
        end
      }

=begin
      # just for fun -- seeing how we can move window around
      # these are working, but can cause a padrefresh error. we should check for bounds or something.
      #
      t.bind_key('<', 'move window left'){ f = t.form.window; c = f.left - 1; f.hide; f.mvwin(f.top, c); f.show;
        f.set_layout([f.height, f.width, f.top, c]); 
      }
      t.bind_key('>', 'move window right'){ f = t.form.window; c = f.left + 1; f.hide; f.mvwin(f.top, c); 
        f.set_layout([f.height, f.width, f.top, c]); f.show;
      }
      t.bind_key('^', 'move window up'){ f = t.form.window; c = f.top - 1 ; f.hide; f.mvwin(c, f.left); 
        f.set_layout([f.height, f.width, c, f.left]) ; f.show;
      }
      t.bind_key('V', 'move window down'){ f = t.form.window; c = f.top + 1 ; f.hide; f.mvwin(c, f.left); 
        f.set_layout([f.height, f.width, c, f.left]); f.show;
      }
=end
      items = {:header => ah}
      close_keys = [ config[:close_key] , 3 , ?q.getbyte(0), 27 , 2727 ]
      begin
        # the next can also be used to use formatted_text(text, :ansi)
        # yielding textview so you may further configure or bind keys or events
        if block_given?
          if block.arity > 0
            yield textview, items
          else
            textview.instance_eval(&block)
          end
        end
        # multibuffer requires add_co after set_co
        # We are using in help, therefore we need multibuffers.
        #textview.set_content content, :content_type => type #, :stylesheet => t.stylesheet
        # i need to do this so it is available when moving around
        # buffers
        #  but this means that pressing next will again show the same
        #  buffer.
        textview.add_content content, :content_type => type #, :stylesheet => t.stylesheet
        textview.buffer_last
      #yield textview if block_given? 
      v_form.repaint
      v_window.wrefresh
      Ncurses::Panel.update_panels
      retval = ""
      # allow closing using q and Ctrl-q in addition to any key specified
      #  user should not need to specify key, since that becomes inconsistent across usages
      #  NOTE: 2727 is no longer operational, so putting just ESC
        while((ch = v_window.getchar()) != ?\C-q.getbyte(0) )
          $log.debug "  VIEWER got key #{ch} , close key is #{config[:close_key]} "
          retval = textview.current_value() if ch == config[:close_key] 
          break if close_keys.include? ch
          # if you've asked for ENTER then i also check for 10 and 13
          retval = textview.current_value() if (ch == 10 || ch == 13) && config[:close_key] == KEY_ENTER
          break if (ch == 10 || ch == 13) && config[:close_key] == KEY_ENTER
          $log.debug "  1 VIEWER got key #{ch} "
          v_form.handle_key ch
          v_form.repaint
        end
      rescue => err
          $log.error " VIEWER ERROR #{err} "
          $log.debug(err.backtrace.join("\n"))
          alert "#{err}"
          #textdialog ["Error in viewer: #{err} ", *err.backtrace], :title => "Exception"
      ensure
        v_window.destroy if !v_window.nil?
      end
      return retval
    end
    private
    def self._get_contents fp
      raise "File #{fp} not readable"  unless File.readable? fp 
      return Dir.new(fp).entries if File.directory? fp
      case File.extname(fp)
      when '.tgz','.gz'
        cmd = "tar -ztvf #{fp}"
        content = %x[#{cmd}]
      when '.zip'
        cmd = "unzip -l #{fp}"
        content = %x[#{cmd}]
      when '.jar', '.gem'
        cmd = "tar -tvf #{fp}"
        content = %x[#{cmd}]
      when '.png', '.out','.jpg', '.gif','.pdf'
        content = "File #{fp} not displayable"
      when '.sqlite'
        cmd = "sqlite3 #{fp} 'select name from sqlite_master;'"
        content = %x[#{cmd}]
      else
        content = File.open(fp,"r").readlines
      end
    end
  end  # class

end # module
if __FILE__ == $PROGRAM_NAME
require 'canis/core/util/app'

App.new do 
  header = app_header "canis 1.2.0", :text_center => "Viewer Demo", :text_right =>"New Improved!", :color => :black, :bgcolor => :white, :attr => :bold 
  message "Press F1 to exit from here"

    Canis::Viewer.view(ARGV[0] || $0, :close_key => KEY_ENTER, :title => "Enter to close") do |t|
      # you may configure textview further here.
      #t.suppress_borders true
      #t.color = :black
      #t.bgcolor = :white
      # or
      #t.attr = :reverse
    end

end # app
end
