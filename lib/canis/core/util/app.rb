=begin
  * Name: App
  * Description: Application class that wraps starting and shutting ncurses and creating a root window
    and form.
  * Author: jkepler 
  * file created 2010-09-04 22:10 
Todo: 

  * 1.5.0 : redo the constructors of these widgets
    as per stack flow improved, and make the constructor
    simpler, no need for jugglery of row col etc. let user
    specify in config.
  --------
  * License:
    Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)

=end
require 'logger'
require 'canis'
require 'canis/core/util/widgetshortcuts'

include Canis
include Canis::Utils
include Io
module Canis
   extend self
  ##
  #
  # @since 1.2.0
  # TODO - 
  # / combo
  # - popup
  # - promptmenu
  # - stack and flow should be objects in Form/App?, put in widget when creating
  # - box / rect
  # - para looks like a label that is more than one line, and calculates rows itself based on text
  # - multicontainer
  # - tabbedpane
  # / table - more work regarding vim keys, also editable
  # - margin - is left offset
  #    http://lethain.com/entry/2007/oct/15/getting-started-shoes-os-x/
  #  
  
  # 2014-04-17 - 13:15 XXX are these used. required ???
=begin
  # 2014-08-19 - 20:48 trying to remove excess convenience code
  class Widget
    def changed *args, &block
      bind :CHANGED, *args, &block
    end
    def leave *args, &block
      bind :LEAVE, *args, &block
    end
    def enter *args, &block
      bind :ENTER, *args, &block
    end
    # actually we already have command() for buttons
    def click *args, &block
      bind :PRESS, *args, &block
    end
  end
=end
  class CheckBox
    # a little dicey XXX 
    def text(*val)
      raise "FIXME this is being used Checkbox app.rb text(), otherwise delete this. 2014-08-19 - 21:01 "
      if val.empty?
        @value ? @onvalue : @offvalue
      else
        super
      end
    end
  end
  # This is the Application class which does the job of setting up the 
  # environment, and closing it at the end.
  class App
  include Canis::WidgetShortcuts
    attr_reader :config
    attr_reader :form
    attr_reader :window
    attr_writer :quit_key

    # TODO: i should be able to pass window coords here in config
    # :title
    def initialize config={}, &block
      @config = config


      widget_shortcuts_init
      @variables = {}
      # if we are creating child objects then we will not use outer form. this object will manage
      #@current_object = []  # 2014-08-29 - 17:35 unused
      @_system_commands = %w{ bind_global bind_component field_help_text }

      init_vars
      $log.debug "XXX APP CONFIG: #{@config}  " if $log.debug? 
      run &block
    end
    def init_vars
      @quit_key ||= FFI::NCurses::KEY_F10
      # actually this should be maintained inside ncurses pack, so not loaded 2 times.
      # this way if we call an app from existing program, App won't start ncurses.
      unless $ncurses_started
        init_ncurses
      end
      $lastline = Ncurses.LINES - 1
      unless $log
        logpath=ENV["CANIS_LOG_PATH"]
        $log = create_logger(logpath || "/dev/null")
      end
    end
    def logger; return $log; end
    def close
      $log.debug " INSIDE CLOSE, #{@stop_ncurses_on_close} "
      @window.destroy if @window
      $log.debug " INSIDE CLOSE, #{@stop_ncurses_on_close} "
      if @stop_ncurses_on_close
        Canis::stop_ncurses
        $log.debug " CLOSING NCURSES"
      end
      $log.debug " CLOSING APP"
    end

    # This method is called by run, and thus in most cases this is what is used.
    # +run+ calls this without a block
    # not sure, but user shuld be able to trap keystrokes if he wants
    # but do i still call handle_key if he does, or give him total control.
    # But loop is already called by framework
    def loop &block
      @form.repaint
      @window.wrefresh
      Ncurses::Panel.update_panels
      @break_key = ?\C-q.getbyte(0)
      # added this extra loop since from some places we exit using throw :close
      # amd that was in a much higher place, and was getting us right out, with
      # no chance of user canceling quit. This extra loop allows us to remain
      # added on 2011-11-24 
      while true
        catch :close do
          while((ch = @window.getchar()) != 999 )
            if ch == @break_key || ch == @quit_key
              break
            end


            # 2014-08-19 - 22:51 commented next line, too much choice. keep it simple. delete in a month FIXME
            #yield ch if block # <<<----

            # this is what the user should have control ove. earlier we would put this in
            # a try catch block so user could do what he wanted with the error. Now we
            # need to get it to him somehow, perhaps through a block or on_error event
            begin
              # execute a code block so caller program can handle keys from a hash or whatever.
              # NOTE: these keys will not appear in help
              # FIXME : ideally if its just a hash, we should allow user to give it to form
              #  or widget which it will use, or merge, and be able to print help from
              if @keyblock
                str = keycode_tos ch
                # why did we ever want to convert to a symbol. why not just pass it as is.
                #@keyblock.call(str.gsub(/-/, "_").to_sym) # not used ever
                ret = @keyblock.call(str) 
                if ret
                  @form.repaint 
                  next
                end
              end
              @form.handle_key ch
            rescue => err
              $log.debug( "app.rb handle_key rescue reached ")
              $log.debug( err.to_s) 
              $log.debug(err.backtrace.join("\n")) 
              textdialog [err.to_s, *err.backtrace], :title => "Exception"
            end
            @window.wrefresh
          end
        end # catch
        stopping = @window.fire_close_handler
        @window.wrefresh
        break if stopping.nil? || stopping
      end # while
    end
    # if calling loop separately better to call this, since it will shut off ncurses
    # and print error on screen.
    # UNUSED
    def safe_loop &block
      begin
        loop &block
      rescue => ex
        $log.debug( "APP.rb rescue reached ")
        $log.debug( ex) if ex
        $log.debug(ex.backtrace.join("\n")) if ex
      ensure
        close
        # putting it here allows it to be printed on screen, otherwise it was not showing at all.
        if ex
          puts "========== EXCEPTION =========="
          p ex 
          puts "==============================="
          puts(ex.backtrace.join("\n")) 
        end
      end
    end
    # returns a symbol of the key pressed
    # e.g. :C_c for Ctrl-C
    # :Space, :bs, :M_d etc
    # NOTE 2014-08-15  Trying with just string returned by keycode_tos
    # This should allow for simpler apps that want to handle keys perhaps taken from a config file
    #  rather than bind each key manually.
    def keypress &block
     @keyblock = block
    end
    # updates a global var with text. Calling app has to set up a Variable with that name and attach to 
    # a label so it can be printed.
    def message text
      $status_message.value = text # trying out 2011-10-9 
    end

    # used only by LiveConsole, if enables in an app, usually only during testing.
    def get_binding
      return binding()
    end
    #
    # suspends curses so you can play around on the shell
    # or in cooked mode like Vim does. Expects a block to be passed.
    # Purpose: you can print some stuff without creating a window, or 
    # just run shell commands without coming out.
    # NOTE: if you pass clear as true, then the screen will be cleared
    # and you can use puts or print to print. You may have to flush.
    # However, with clear as false, the screen will not be cleared. You
    # will have to print using printw, and if you expect user input
    # you must do a "system /bin/stty sane"
    # If you print stuff, you will have to put a getch() or system("read")
    # to pause the screen.
    def suspend clear=true
      return unless block_given?
      Ncurses.def_prog_mode
      if clear
        Ncurses.endwin 
        # NOTE: avoid false since screen remains half off
        # too many issues
      else
        system "/bin/stty sane"
      end
      yield if block_given?
      Ncurses.reset_prog_mode
      if !clear
        # Hope we don't screw your terminal up with this constantly.
        Canis::stop_ncurses
        Canis::start_ncurses  
        #@form.reset_all # not required
      end
      @form.repaint
      @window.wrefresh
      Ncurses::Panel.update_panels
    end
    def get_all_commands
      opts = @_system_commands.dup
      if respond_to? :get_commands
        opts.push(*get_commands())
      end
      opts
    end
    # bind a key to a method at global (form) level
    # Note that individual component may be overriding this.
    def bind_global
      opts = get_all_commands
      cmd = rb_gets("Select a command (<tab> for choices) : ", opts)
      if cmd.nil? || cmd == ""
        rb_puts "Aborted."
        return
      end
      key = []
      str = ""
      # the next is fine but does not allow user to enter a control or alt or function character
      # since it uses Field. It is fine if you want to force alphanum input
      ch = rb_getchar("Enter one or two keys. Finish with <ENTER>. Enter first key:")
      unless ch
        rb_puts "Aborted. <Press a key>"
        return
      end
      key << ch
      str << keycode_tos(ch)
      ch = rb_getchar  "Got #{str}. Enter second key or hit return:"
      unless ch
        rb_puts "Aborted. <Press a key>"
        return
      end
      if ch == KEY_ENTER || ch == 13
      else
        key << ch
        str << keycode_tos(ch)
      end
      if !key.empty?
        rb_puts "Binding #{cmd} to #{str}. "
        key = key[0] if key.size == 1
        #@form.bind_key(key, cmd.to_sym) # not finding it, getting called by that comp
        @form.bind_key(key){ send(cmd.to_sym) }
      end
    end
    # displays help_text associated with field. 2011-10-15 
    def field_help_text
      f = @form.get_current_field
      if f.respond_to?('help_text')
        h = f.help_text
        h = "No help text defined for this field.\nTry F1, or press '?' for key-bindings." unless h
        textdialog "#{h}", :title => "Widget Help Text"
      else
        alert "Could not get field #{f} or does not respond to helptext. Try F1 or '?'"
      end
    end
    # prompts user for a command. we need to get this back to the calling app
    # or have some block stuff TODO
    # Actually, this is naive, you would want to pass some values in like current data value
    # or lines ??
    # Also may want command completion, or help so all commands can be displayed
    # NOTE: This is gonna change very soon - 2012-01-8 
    def get_command_from_user choices=["quit","help", "suspend", "shell_output"]
      @_command_history ||= Array.new
      str = rb_gets("Cmd: ", choices) { |q| q.default = @_previous_command; q.history = @_command_history }
              @_command_history << str unless @_command_history.include? str
      # shell the command
      if str =~ /^!/
        str = str[1..-1]
        suspend(false) { 
          #system(str); 
          $log.debug "XXX STR #{str}  " if $log.debug? 

          output=`#{str}`
          system("echo ' ' ");
          $log.debug "XXX output #{output} " if $log.debug? 
          system("echo '#{output}' ");
          system("echo Press Enter to continue.");
          system("read"); 
        }
        return nil # i think
      else
        # TODO
        # here's where we can take internal commands
        #alert "[#{str}] string did not match :!"
        str = str.to_s #= str[1..-1]
        cmdline = str.split
        cmd = cmdline.shift #.to_sym
        return unless cmd # added 2011-09-11 FFI
        f = @form.get_current_field
        if respond_to?(cmd, true)
          if cmd == "close"
            throw :close # other seg faults in del_panel window.destroy executes 2x
          else
            res = send cmd, *cmdline
          end
        elsif f.respond_to?(cmd, true)
          res = f.send(cmd, *cmdline)
        else
          alert "App: #{self.class} does not respond to #{cmd} "
          ret = false
          # what is this execute_this: some kind of general routine for all apps ?
          ret = execute_this(cmd, *cmdline) if respond_to?(:execute_this, true)
          rb_puts("#{self.class} does not respond to #{cmd} ", :color_pair => $promptcolor) unless ret
          # should be able to say in red as error
        end
      end
    end
    #
    # @group methods to create widgets easily
    #
    # process arguments based on datatype, perhaps making configuration
    # of some components easier for caller avoiding too much boiler plate code
    # 
      #instance_eval &block if block_given?
      # or
      #@blk = block # for later execution using @blk.call()
      #colorlabel = Label.new @form, {'text' => "Select a color:", "row" => row, "col" => col, "color"=>"cyan", "mnemonic" => 'S'}
    alias :text :label
    
    # menu bar

    # displays a horizontal line
    # takes col (column to start from) from current stack
    # take row from app_row
    #
    # requires width to be passed in config, else defaults to 20
    # @example
    #    hline :width => 55  
    def hline config={}
      raise "I think this is unused. removed if this does not raise 2014-08-29 - 12:43 "
      row = config[:row] || @app_row
      width = config[:width] || 20
      _position config
      col = config[:col] || 1
      @color_pair = config[:color_pair] || $datacolor
      @attrib = config[:attrib] || Ncurses::A_NORMAL
      @window.attron(Ncurses.COLOR_PAIR(@color_pair) | @attrib)
      @window.mvwhline( row, col, FFI::NCurses::ACS_HLINE, width)
      @window.attron(Ncurses.COLOR_PAIR(@color_pair) | @attrib)
      @app_row += 1
    end
    

    # ADD new widget above this

    # @endgroup
    
    # @group positioning of components
    

    private
    def quit
      throw(:close)
    end
    #def help; display_app_help; end
    # i am removing above from rdialog. 2014-05-21 - 12:42 hope next
    # line works UNTESTED
    def help; @form.help_manager.display_help; end

    # Initialize curses
    def init_ncurses
      Canis::start_ncurses  # this is initializing colors via ColorMap.setup
      #$ncurses_started = true
      @stop_ncurses_on_close = true
    end

    # returns length of longest
    def longest_in_list list  #:nodoc:
      longest = list.inject(0) do |memo,word|
        memo >= word.length ? memo : word.length
      end    
      longest
    end    
    # returns longest item
    # rows = list.max_by(&:length)
    #
    def longest_in_list2 list  #:nodoc:
      longest = list.inject(list[0]) do |memo,word|
        memo.length >= word.length ? memo : word
      end    
      longest
    end    

    # if partial command entered then returns matches
    def _resolve_command opts, cmd
      return cmd if opts.include? cmd
      matches = opts.grep Regexp.new("^#{cmd}")
    end

    # This is the method that is called by all apps usually that define an App block
    def run &block
      begin

        # check if user has passed window coord in config, else root window
        @window = Canis::Window.root_window
        awin = @window
        catch(:close) do
          @form = Form.new @window
          #@form.bind_key(KEY_F1, 'help'){ display_app_help } # NOT REQUIRED NOW 2012-01-7 since form does it
          @form.bind_key([?q,?q], 'quit' ){ throw :close } if $log.debug?

          #@message = Variable.new
          #@message.value = ""
          $status_message ||= Variable.new # remember there are multiple levels of apps
          $status_message.value = ""
          #$error_message.update_command { @message.set_value($error_message.value) }
          if block
            begin
              yield_or_eval &block if block_given? 
              # how the hell does a user trap exception if the loop is hidden from him ? FIXME
              loop
            rescue => ex
              $log.debug( "APP.rb rescue reached ")
              $log.debug( ex) if ex
              $log.debug(ex.backtrace.join("\n")) if ex
            ensure
              close
              # putting it here allows it to be printed on screen, otherwise it was not showing at all.
              if ex
                puts "========== EXCEPTION =========="
                p ex 
                puts "==============================="
                puts(ex.backtrace.join("\n")) 
              end
            end
            nil
          else
            #@close_on_terminate = true
            self
          end #if block
        end # :close
      end
    end
    # Some bindings that were earlier part of App (in the run block), but now optional for an 
    #  app. I would like to move it out, so they can be mapped separately to whatever a user wants
    #  and be improved. these are very experimental and bare as yet.
    # They should also be usable outside of App.
    def app_bindings
      @form.bind_key([?\C-x, ?c], 'suspend') { suspend(false) do
        system("tput cup 26 0")
        system("tput ed")
        system("echo Enter C-d to return to application")
        system (ENV['PS1']='\s-\v\$ ')
        system(ENV['SHELL']);
      end
      }
      # this is a very rudimentary default command executer, it does not 
      # allow tab completion. App should use M-x with names of commands
      # as in appgmail
      # NOTE: This is gonna change very soon - 2012-01-8 
      @form.bind_key(?:, 'prompt') { 
        str = get_command_from_user
      }

      # this M-x stuff has to be moved out so it can be used by all. One should be able
      # to add_commands properly to this, and to C-x. I am thinking how to go about this,
      # and what function M-x actually serves.

      @form.bind_key(?\M-x, 'M-x commands'){
        # TODO previous command to be default
        opts = get_all_commands()
        @_command_history ||= Array.new
        # previous command should be in opts, otherwise it is not in this context
        cmd = rb_gets("Command: ", opts){ |q| q.default = @_previous_command; q.history = @_command_history }
        if cmd.nil? || cmd == ""
        else
          @_command_history << cmd unless @_command_history.include? cmd
          cmdline = cmd.split
          cmd = cmdline.shift
          # check if command is a substring of a larger command
          if !opts.include?(cmd)
            rcmd = _resolve_command(opts, cmd) if !opts.include?(cmd)
            if rcmd.size == 1
              cmd = rcmd.first
            elsif !rcmd.empty?
              rb_puts "Cannot resolve #{cmd}. Matches are: #{rcmd} "
            end
          end
          if respond_to?(cmd, true)
            @_previous_command = cmd
            begin
              send cmd, *cmdline
            rescue => exc
              $log.error "ERR EXC: send throwing an exception now. Duh. IMAP keeps crashing haha !! #{exc}  " if $log.debug? 
              if exc
                $log.debug( exc) 
                $log.debug(exc.backtrace.join("\n")) 
                rb_puts exc.to_s
              end
            end
          else
            rb_puts("Command [#{cmd}] not supported by #{self.class} ", :color_pair => $promptcolor)
          end
        end
      }
    end
    # process args, all widgets should call this
    def _process_args args, config, block_event, events  #:nodoc:
      raise "FIXME seems uncalled _process_args, remove it this does not come up within a month 2014-08-19 "
      args.each do |arg| 
        case arg
        when Array
          # please don't use this, keep it simple and use hash NOTE
          # we can use r,c, w, h
          row, col, width, height = arg
          config[:row] = row
          config[:col] = col
          config[:width] = width if width
          # width for most XXX ?
          config[:height] = height if height
        when Hash
          config.merge!(arg)
          if block_event 
            block_event = config.delete(:block_event){ block_event }
            raise "Invalid event. Use #{events}" unless events.include? block_event
          end
        when String
          config[:name] = arg
          config[:title] = arg # some may not have title
          #config[:text] = arg # some may not have title
        end
      end
    end # _process
  end # class
end # module 
if $0 == __FILE__
  include Canis
  #app = App.new
  #window = app.window
  #window.printstring 2, 30, "Demo of Listbox - canis", $normalcolor, 'reverse'
  #app.logger.info "beforegetch"
  #window.getch
  #app.close
  # this was the yield example, but now we've moved to instance eval
  App.new do 
    @window.printstring 0, 30, "Demo of Listbox - canis", $normalcolor, 'reverse'
    @window.printstring 1, 30, "Hit F1 to quit", $datacolor, 'normal'
    form = @form
    fname = "Search"
    r, c = 7, 30
    c += fname.length + 1
    #field1 = field( [r,c, 30], fname, :bgcolor => "cyan", :block_event => :CHANGE) do |fld|
    stack :margin_top => 2, :margin => 10 do
      lbl = label({:text => fname, :color=>'white',:bgcolor=>'red', :mnemonic=> 's'})
      field1 = field( [r,c, 30], fname, :bgcolor => "cyan",:block_event => :CHANGE) do |fld|
        message("You entered #{fld.getvalue}. To quit enter quit and tab out")
        if fld.getvalue == "quit"
          logger.info "you typed quit!" 
          throw :close
        end
      end
      #field1.set_label Label.new @form, {:text => fname, :color=>'white',:bgcolor=>'red', :mnemonic=> 's'}
      field1.set_label( lbl )
      field1.enter do 
        message "you entered this field"
      end

      stack :margin_top => 2, :margin => 0 do
        #label( [8, 30, 60],{:text => "A label", :color=>'white',:bgcolor=>'blue'} )
      end

      @bluelabel = label( [8, 30, 60],{:text => "B label", :color=>'white',:bgcolor=>'blue'} )

      stack :margin_top => 2, :margin => 0 do
        toggle :onvalue => " Toggle Down ", :offvalue => "  Untoggle   ", :mnemonic => 'T', :value => true

        toggle :onvalue => " On  ", :offvalue => " Off ", :value => true do |e|
          alert "You pressed me #{e.state}"
        end
        check :text => "Check me!", :onvalue => "Checked", :offvalue => "Unchecked", :value => true do |e|
          # this works but long and complicated
          #@bluelabel.text = e.item.getvalue ? e.item.onvalue : e.item.offvalue
          @bluelabel.text = e.item.text
        end
        radio :text => "red", :value => "RED", :color => "red", :group => :colors
        radio :text => "green", :value => "GREEN", :color => "green", :group => :colors
        flow do
          button_row = 17
          ok_button = button( [button_row,30], "OK", {:mnemonic => 'O'}) do 
            alert("About to dump data into log file!")
            message "Dumped data to log file"
          end

          # using ampersand to set mnemonic
          cancel_button = button( [button_row, 40], "&Cancel" ) do
            if confirm("Do your really want to quit?")== :YES
              #throw(:close); 
              quit
            else
              message "Quit aborted"
            end
          end # cancel
          button "Don't know"
        end
        flow :margin_top => 2 do
          button "Another"
          button "Line"
        end
        stack :margin_top => 2, :margin => 0 do
          @pbar = progress :width => 20, :bgcolor => 'white', :color => 'red'
          @pbar1 = progress :width => 20, :style => :old
        end
      end
    end # stack
    # lets make another column
    stack :margin_top => 2, :margin => 70 do
      l = label "Column 2"
      f1 = field "afield", :bgcolor => 'white', :color => 'black'
      listbox "A list", :list => ["Square", "Oval", "Rectangle", "Somethinglarge"], :choose => ["Square"]
      lb = listbox "Another", :list => ["Square", "Oval", "Rectangle", "Somethinglarge"] do |list|
        #f1.set_buffer list.text
        #f1.text list.text
        f1.text = list.text
        l.text = list.current_value.upcase
      end
      t = textarea :height => 10 do |e|
        #@bluelabel.text = e.to_s.tr("\n",' ')
        @bluelabel.text = e.text.gsub("\n"," ")
        len = e.source.get_text.length
        len = len % 20 if len > 20
        $log.debug " PBAR len of text is #{len}: #{len/20.0} "
        @pbar.fraction(len/20.0)
        @pbar1.fraction(len/20.0)
        i = ((len/20.0)*100).to_i
        @pbar.text = "completed:#{i}"
      end
      t.leave do |c|
        @bluelabel.text = c.get_text.gsub("\n"," ")
      end

    end

    # Allow user to get the keys
    keypress do |key|
      if key == :C_c
        message "You tried to cancel"
        #throw :close
        quit
      else
        #app.message "You pressed #{key}, #{char} "
        message "You pressed #{key}"
      end
    end
  end
end
