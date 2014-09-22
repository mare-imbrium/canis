require 'logger'
require 'canis'
require 'canis/core/include/appmethods.rb'
def help_text
      <<-eos
# FIELD  HELP

This is some help text for |Fields|

*Name* is non-focusable
*Line* takes numbers from 1 to 200
*Regex* takes only alpha
*Password* takes only scotty or tiger or pass or qwerty, and can be left blank

Use Alt (meta) with the highlighted character to jump to that field.
<Alt-m> goes to line, <Alt-p> to password.

Notice how the field label (for first 3 fields) becomes red when focused (as in Pine/Alpine). This uses
the event `:ENTER` and `:LEAVE` and +set_label+. The other fields use `LabeledField+. In the first 3, the
labels row and col have not been specified, so are calculated. In the last 3, label's lcol and lrow are
specified for custom placement.


>
      F10      -   Exit application  (also C-q)
      Alt-!    -   Drop to shell
      C-x c    -   Drop to shell
      C-x l    -   list of files
      C-x p    -   process list
      C-x d    -   disk usage list
      C-x s    -   Git status
      C-x w    -   Git whatchanged
      Alt-x    -   Command mode (<tab> to see commands and select)

      F3       -   View log
      F4       -   prompt for unix command and display in viewer
      F5       -   Drop to shell
<

-----------------------------------------------------------------------
      eos
end
if $0 == __FILE__

  include Canis
  include Canis::Utils

  begin
  # Initialize curses
    Canis::start_ncurses  # this is initializing colors via ColorMap.setup
    path = File.join(ENV["LOGDIR"] || "./" ,"canis14.log")
    file   = File.open(path, File::WRONLY|File::TRUNC|File::CREAT)
    $log = Logger.new(path)
    $log.level = Logger::DEBUG

    @lookfeel = :classic # :dialog # or :classic

    @window = Canis::Window.root_window
    # Initialize few color pairs
    # Create the window to be associated with the form
    # Un post form and free the memory

    catch(:close) do
      colors = Ncurses.COLORS
      $log.debug "START #{colors} colors testfield.rb --------- #{@window} "
      @form = Form.new @window
      title = (" "*30) + "Demo of Field (F10 quits, F1 help) " + Canis::VERSION
      Label.new @form, {:text => title, :row => 1, :col => 0, :color => :green, :bgcolor => :black}
      r = 3; fc = 12;
      mnemonics = %w[ n l r p]
      %w[ name line regex password].each_with_index do |w,i|
        field = Field.new @form do
          name w
          row  r
          col  fc
          width  30
          #text "abcd "
          set_label Label.new @form, {:text => w, :color=> :cyan, :mnemonic => mnemonics[i]}
        end
        r += 1
      end

      f = @form.by_name["line"]
      f.width(3).text(24).valid_range(1..200).
        maxlen(3).
        type(:integer)

      @form.by_name["name"].text( "Not focusable").
        focusable(false)

      @form.by_name["regex"].valid_regex(/^[A-Z][a-z]*/).
        text( "SYNOP").
        width(10).
        maxlen = 20

      @form.by_name["password"].text("").
        mask('*').
        color(:red).
        values(%w[scotty tiger secret pass qwerty]).
        null_allowed true

    r += 3
    l1 = Label.new @form, :name => "LabeledField", :attr => 'bold', :text => "Profile", :row => r, :col => fc
    r += 1
    f1 = LabeledField.new @form,  :name => "name1", :maxlen => 20, :width => 20, :bgcolor => :white,
      :color => :black, :text => "abc", :label => '    Name: ', :row => r, :col => fc
    r += 1
    f2 = LabeledField.new @form, :name => "email", :width => 20, :bgcolor => :white,
      :color => :blue, :text => "me@google.com", :label => '   Email: ', :row => r, :col => fc
    r += 3
    f3 = LabeledField.new @form
    f3.name("mobile").width(20).bgcolor(:white).color(:black).
      text("").label('  Mobile: ').
      row(r).col(fc).
      type(:integer)
    r += 2

    LabeledField.new(@form).
    name("landline").width(20).bgcolor(:white).color(:black).
      text("").label('Landline: ').
      row(r).col(fc).
      chars_allowed(/[\d\-]/)
      # a form level event, whenever any widget is focussed, make the label red
    #

    r += 2
      %w[ profession title department].each_with_index do |w,i|
        LabeledField.new(@form).label(w).width(20).text("").
          bgcolor(:white).color(:black).
          row(r+i).col(fc).lcol(01)
      end
      @form.bind_key(FFI::NCurses::KEY_F3,'view log') {
        require 'canis/core/util/viewer'
        Canis::Viewer.view(path || "canis14.log", :close_key => KEY_ENTER, :title => "<Enter> to close")
      }
      @form.bind_key(FFI::NCurses::KEY_F4, 'system command') {  shell_output }
      @form.bind_key(FFI::NCurses::KEY_F5, 'shell') {  suspend }
      @form.bind_key([?\C-x,?c], 'shell') {  suspend }
      @form.bind_key(?\M-!, 'shell') {  suspend }
      @form.bind_key([?\C-x,?l], 'ls -al') {  run_command "ls -al" }
      @form.bind_key([?\C-x,?p], 'ps -l') {  run_command "ps -l" }
      @form.bind_key([?\C-x,?d], 'df -h') {  run_command "df -h" }
      #@form.bind_key([?\C-x,?d], 'git diff') {  run_command "git diff --name-status" }
      @form.bind_key([?\C-x, ?s], 'git st') {  run_command "git status" }
      @form.bind_key([?\C-x,?w], 'git whatchanged') {  run_command "git whatchanged" }

      @form.help_manager.help_text = help_text
      @form.repaint
      @form.widgets.each { |ff|
        if ff.focusable?
          ff.bind(:ENTER) { |f|   f.label && f.label.bgcolor = :red if (f.respond_to? :label and f.label.respond_to?(:bgcolor))}
          ff.bind(:LEAVE) { |f|  f.label && f.label.bgcolor = 'black'   if (f.respond_to? :label and f.label.respond_to?(:bgcolor))}
        end
      }
      @window.wrefresh
      Ncurses::Panel.update_panels

      # the main loop

      while((ch = @window.getchar()) != FFI::NCurses::KEY_F10 )
        break if ch == ?\C-q.getbyte(0)
        begin
          @form.handle_key(ch)

        rescue FieldValidationException => fve
          #alert fve.to_s
          textdialog fve

          f = @form.get_current_field
          # lets restore the value
          if f.respond_to? :restore_original_value
            f.restore_original_value
            #@form.select_field @form.active_index
            @form.repaint
          end
          $error_message.value = ""
        rescue => err
          $log.error( err) if err
          $log.error(err.backtrace.join("\n")) if err
          textdialog err
          $error_message.value = ""
        end

        # this should be avoided, we should not muffle the exception and set a variable
        # However, we have been doing that
        if $error_message.get_value != ""
          if @lookfeel == :dialog
            alert($error_message, {:bgcolor => :red, 'color' => 'yellow'}) if $error_message.get_value != ""
          else
            print_error_message $error_message, {:bgcolor => :red, :color => :yellow}
          end
          $error_message.value = ""
        end

        @window.wrefresh
      end # while loop
    end # catch
  rescue => ex
  ensure
    $log.debug " -==== EXCEPTION =====-" if ex
    $log.debug( ex) if ex
    $log.debug(ex.backtrace.join("\n")) if ex
    @window.destroy if !@window.nil?
    Canis::stop_ncurses
    puts ex if ex
    puts(ex.backtrace.join("\n")) if ex
  end
end
