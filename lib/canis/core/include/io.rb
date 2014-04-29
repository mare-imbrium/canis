#*******************************************************
# Some common io routines for getting data or putting
# at some point
#  Current are:
#    * rb_gets - get a string at bottom of screen
#    * get_file 
#    * rb_getchar - get a char
#
#    * Promptmenu creation
#    requires rcommandwindow
#
#    * 
#    * rb_getstr (and those it calls) (old and for backward compat)
#      - rb_getstr is used by vieditable for edit_line and insert_line
#    * display_cmenu and create_mitem
# Changes:
# 2011-12-6 : removed many old, outdated methods.
# 2014-04-25 - 12:36 moved Promptmenu to util/promptmenu.rb
#*******************************************************#
require 'pathname'
module Canis
  module Io

    # create a 2 line window at bottom to accept user input
    # 
    def __create_footer_window h = 2 , w = Ncurses.COLS, t = Ncurses.LINES-2, l = 0
      ewin = Canis::Window.new(h, w , t, l)
    end
    # 2011-11-27 I have replaced the getting of chars with a field

    # get a string at the bottom of the screen
    #
    # @param [String] prompt - label to show
    # @param [Hash] config - :default, :width of Field, :help_text, :tab_completion
    # help_text is displayed on F1
    # tab_completion is a proc which helps to complete user input
    # @yield [Field] for overriding or customization
    # @return [String, nil] String if entered, nil if canceled
    def rb_gets(prompt, config={}) # yield field
      if config.is_a? Hash
        # okay
        #
      elsif config.is_a? Array
        # an array is supplied, and tabbing helps complete from that
        # array.
        options = config
        completion_proc = Proc.new{|str| 
          options.dup.grep Regexp.new("^#{str}");
        }
        config = {}
        config[:tab_completion] = completion_proc
      elsif config == Pathname
        # we need to return a pathname TODO and prepend dirname
        # allow user to specify startdir else take current
        completion_proc = Proc.new {|str| Dir.glob(str +"*").collect { |f| File.directory?(f) ? f+"/" : f  } }
        help_text = "Enter start of filename and tab to get completion"
        config = {}
        config[:tab_completion] = completion_proc
        config[:help_text] = help_text
      elsif config == Integer
        config = {}
        config[:datatype] = 1.class
        config[:type] = :integer
      elsif config == Float
        config = {}
        v = 0.11
        config[:datatype] = v.class
        config[:type] = :float
      elsif config == :phone

        config = {}
      end
      begin
        win = __create_footer_window
        form = Form.new win
        r = 0; c = 1;
        default = config[:default] || ""
        prompt = "#{prompt} [#{default}]:" if default.size > 0
        _max = FFI::NCurses.COLS-1-prompt.size-4
        displen = config[:width] || [config[:maxlen] || 999, _max].min
        maxlen = config[:maxlen] || _max
        field = Field.new form, :row => r, :col => c, :maxlen => maxlen, :default => default, :label => prompt,
          :width => displen
        field.datatype(config[:datatype]) if config[:datatype]
        field.type(config[:type]) if config[:type]
        bg = Ncurses.COLORS >= 236 ? 233 : :blue
        field.bgcolor = bg
        field.cursor_end if default.size > 0
        def field.default=(x); default(x);end

        # if user wishes to use the yield and say "field.history = [x,y,z] then
        # we should alredy have extended this, so lets make it permanent
        require 'canis/core/include/rhistory'
        field.extend(FieldHistory)
        field.history = config[:history]

        yield field if block_given?
        form.repaint
        win.wrefresh
        prevchar = 0
        entries = nil
        oldstr = nil # for tab completion, origal word entered by user
        while ((ch = win.getchar()) != 999)
          if ch == 10 || ch == 13 || ch == KEY_ENTER
            begin
              # validate in case ranges or other validation given
              field.on_leave
              break
            rescue FieldValidationException => err # added 2011-10-2 v1.3.1 so we can rollback
              alert err.to_s
            rescue => err
              Ncurses.beep
              break
            end
          end
          #return -1, nil if ch == ?\C-c.getbyte(0) || ch == ?\C-g.getbyte(0)
          return nil if ch == ?\C-c.getbyte(0) || ch == ?\C-g.getbyte(0)
          #if ch == ?\M-h.getbyte(0) #                            HELP KEY
          #help_text = config[:help_text] || "No help provided"
          #color = $datacolor
          #print_help(win, r, c, color, help_text)
          ## this will come over our text
          #end
          # tab completion and help_text print on F1
          # that field objects can extend, same for tab completion and gmail completion
          if ch == KEY_TAB
            if config
              str = field.text
              # tab_completion
              # if previous char was not tab, execute tab_completion_proc and push first entry
              # else push the next entry
              if prevchar == KEY_TAB
                if !entries.nil? && !entries.empty?
                  str = entries.delete_at(0)
                else
                  str = oldstr if oldstr
                  prevchar = ch = nil # so it can start again completing
                end
              else
                tabc = config[:tab_completion] unless tabc
                next unless tabc
                oldstr = str.dup
                entries = tabc.call(str).dup
                $log.debug " tab got #{entries} for str=#{str}"
                str = entries.delete_at(0) unless entries.nil? || entries.empty?
                str = str.to_s.dup
              end
              if str
                field.text = str
                field.cursor_end
                field.set_form_col # shit why are we doign this, text sets curpos to 0
              end
              form.repaint
              win.wrefresh
            end

          elsif ch == KEY_F1
            help_text = config[:help_text] || "No help provided. C-c/C-g aborts. <TAB> completion. Alt-h history. C-a/e"
            print_status_message help_text, :wait => 7
          else
            form.handle_key ch
          end
          prevchar = ch
          win.wrefresh
        end
      rescue => err
        Ncurses.beep
        textdialog [err.to_s, *err.backtrace], :title => "Exception"
        $log.error "EXC in rb_getstr #{err} "
        $log.error(err.backtrace.join("\n")) 
      ensure
        win.destroy if win
      end
      config[:history] << field.text if config[:history] && field.text
      return field.text
    end

    # get a character.
    # unlike rb_gets allows user to enter control or alt or function character too.
    # @param [String] prompt or label to show.
    # @param [Hash] configuration such as default or regexp for validation
    # @return [Fixnum] nil if canceled, or ret value of getchar which is numeric
    # If default provided, then ENTER returns the default
    def rb_getchar(prompt, config={}) # yield field
      begin
        win = __create_footer_window
        #form = Form.new win
        r = 0; c = 1;
        default = config[:default] 
        prompt = "#{prompt} [#{default}] " if default
        win.mvprintw(r, c, "%s: " % prompt);
        bg = Ncurses.COLORS >= 236 ? 236 : :blue
        color_pair = get_color($reversecolor, :white, bg)
        win.printstring r, c + prompt.size + 2, " ", color_pair

        win.wrefresh
        prevchar = 0
        entries = nil
        while ((ch = win.getchar()) != 999)
          return default.ord if default && (ch == 13 || ch == KEY_ENTER)
          return nil if ch == ?\C-c.getbyte(0) || ch == ?\C-g.getbyte(0)
          if ch == KEY_F1
            help_text = config[:help_text] || "No help provided. C-c/C-g aborts."
            print_status_message help_text, :wait => 7
            win.wrefresh # nevr had to do this with ncurses, but have to with ffi-ncurses ??
            next
          end
          if config[:regexp]
            reg = config[:regexp]
            if ch > 0 && ch < 256
              chs = ch.chr
              return ch if chs =~ reg
              alert "Wrong character. #{reg} "
            else
              alert "Wrong character. #{reg} "
            end
          else
            return ch
          end
          #form.handle_key ch
          win.wrefresh
        end
      rescue => err
        Ncurses.beep
        $log.error "EXC in rb_getstr #{err} "
        $log.error(err.backtrace.join("\n")) 
      ensure
        win.destroy if win
      end
      return nil
    end

    # This is just experimental, trying out tab_completion
    # Prompt user for a file name, allowing him to tab to complete filenames
    # @see #choose_file from rcommandwindow.rb
    # @param [String] label to print before field
    # @param [Fixnum] max length of field
    # @return [String] filename or blank if user cancelled
    def get_file prompt, config={}  #:nodoc:
      maxlen = 70
      tabc = Proc.new {|str| Dir.glob(str +"*") }
      config[:tab_completion] ||= tabc
      config[:maxlen] ||= maxlen
      #config[:default] = "test"
      #ret, str = rb_getstr(nil,0,0, prompt, maxlen, config)
      # 2014-04-25 - 12:42 removed call to deprecated method
      str = rb_gets(prompt, config)
      #$log.debug " get_file returned #{ret} , #{str} "
      str ||= ""
      return str
    end
    def clear_this win, r, c, color, len
      print_this(win, "%-*s" % [len," "], color, r, c)
    end



    ##
    # prints given text to window, in color at x and y coordinates
    # @param [Window] window to write to
    # @param [String] text to print
    # @param [int] color pair such as $datacolor or $promptcolor
    # @param [int] x  row
    # @param [int] y  col
    # @see Window#printstring
    def print_this(win, text, color, x, y)
      raise "win nil in print_this" unless win
      color=Ncurses.COLOR_PAIR(color);
      win.attron(color);
      #win.mvprintw(x, y, "%-40s" % text);
      win.mvprintw(x, y, "%s" % text);
      win.attroff(color);
      win.refresh
    end


    #
    # warn user: currently flashes and places error in log file
    # experimental, may change interface later
    # it does not say anything on screen
    # @param [String] text of error/warning to put in log
    # @since 1.1.5
    def warn string
      $log.warn string
      Ncurses.beep
    end


    # routine to get a string at bottom of window.
    # The first 3 params are no longer required since we create a window
    # of our own. 
    # @param [String] prompt - label to show
    # @param [Fixnum] maxlen - max length of input
    # @param [Hash] config - :default, :width of Field, :help_text, :tab_completion
    # help_text is displayed on F1
    # tab_completion is a proc which helps to complete user input
    # NOTE : This method is now only for **backward compatibility**
    # rb_getstr had various return codes based on whether user asked for help
    # possibly mimicking alpine, or because i could do nothing about it.
    # Now, rb_getstr handles that and only returns if the user cancels or enters
    # a string, so rb_getstr does not need to return other codes.
    # @deprecated
    def rb_getstr(nolongerused, r, c, prompt, maxlen, config={})
      config[:maxlen] = maxlen
      str = rb_gets(prompt, config)
      if str
        return 0, str
      else
        return -1, nil
      end
    end



  end # module
end # module
