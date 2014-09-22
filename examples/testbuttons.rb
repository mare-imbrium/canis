# This program tests out various buttons.
## I have used both DSL and conventional constructors for each button to test out.
## Had to fix checkbox code (text and mnemonic to return self).
# Had to fix radio button code, remove raise from constructor
# 2014-04-30 - 23:46 removed variable in radiobutton to try out newly introduced
# ButtonGroup.
## -----
## -- THIS WILL NOT WORK WITH < 0.0.15. WILL REQUIRE DOWNLOADING FIXES FROM GITHUB
## OR HAVING AT LEAST 0.0.15
#
require 'logger'
require 'canis'
require 'canis/core/include/appmethods.rb'
def help_text
      <<-eos
               BUTTONS  HELP

      This is some help text for testbuttons.
      To select any button press the SPACEBAR, although ENTER will also work.
      You may also press the mnemonic or hotkey on the label..

      The toggle button toggles the kind of dialog for the Cancel button. Modern look
      and feel refers to a popup with buttons. This is like the links editor.

      Classic look and feel refers to a line at the bottom of the screen, with a y/n prompt.
      THis is like a lot of older apps, i think Pine and maybe vim.


      Alt-c/F10 -   Exit application



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
    @lookfeel = :dialog # or :classic

    @window = Canis::Window.root_window
    # Initialize few color pairs
    # Create the window to be associated with the form
    # Un post form and free the memory

    catch(:close) do
      colors = Ncurses.COLORS
      $log.debug "START #{colors} colors  #{$0} --------- #{@window} "
      @form = Form.new @window
      title = (" "*30) + "Demo of Buttons" + Canis::VERSION
      Label.new @form, {'text' => title, :row => 0, :col => 0, :color => 'green', :bgcolor => 'black'}
      r = 1; fc = 12;
        r += 1
        row = 5
        col = 3

      _mess = "Message Comes Here"
      message_label = Canis::Label.new @form, {text: _mess,
        :name=>"message_label",:row => Ncurses.LINES-1, :col => 1, :width => 60,
        :height => 2, :color => :cyan}

      $results = Variable.new
      $results.value = "A variable"

      row += 1
      checkbutton = CheckBox.new(@form).
        variable($results).
        onvalue("Selected bold   ").
        offvalue("UNselected bold").
        width(18).
        text("Bold attribute ").
        mnemonic('B').
        row(row).
        col(col)
      row += 1
      # trying to do without thse stupid variables.
      #@cb_rev = Variable.new false # related to checkbox reverse
      #cbb = @cb_rev
      checkbutton1 = CheckBox.new @form do
        #variable cbb # $cb_rev
        #value = true
        onvalue "Selected reverse   "
        offvalue "UNselected reverse"
        text "Reverse attribute "
        width 18
        row row
        col col
        mnemonic 'R'
      end
      row += 1
      togglebutton = ToggleButton.new(@form).
        value( true).
        onvalue( " Toggle Down ").
        offvalue("  Untoggle   ").
        row(row).
        col(col).
        mnemonic('T')
        #underline 0
      togglebutton.command do
        if togglebutton.value
          message_label.text "Modern look and feel for dialogs"
        else
          message_label.text "Classic look and feel for dialogs"
        end
      end

      @form.bind(:ENTER) { |f|   f.label && f.label.bgcolor = 'red' if f.respond_to? :label}
      @form.bind(:LEAVE) { |f|  f.label && f.label.bgcolor = 'black'   if f.respond_to? :label}

      row += 1
      colorlabel = Label.new @form, {'text' => "Select a color:", "row" => row, "col" => col,
        "color"=>"cyan", "mnemonic" => 'S'}
      #$radio = Variable.new
      #$radio.update_command(colorlabel) {|tv, label|  label.color tv.value; }
#
      #$radio.update_command() {|tv|  @form.widgets.each { |e| next unless e.is_a? Widget;
        #e.bgcolor tv.value };  }

      # whenever updated set colorlabel and messagelabel to bold
      $results.update_command(colorlabel,checkbutton) {|tv, label, cb|
        attrs =  cb.value ? 'bold' : 'normal'; label.attr(attrs); message_label.attr(attrs)}


      checkbutton1.command do
        attrs =  checkbutton1.value ? 'reverse' : 'normal'; colorlabel.attr(attrs); message_label.attr(attrs)
      end
      row += 1
      dlen = 10
      # if we try conventional style then constructor throws exception since @variable must be set
      radio1 = RadioButton.new(@form).
        #variable($radio).
        text("red").
        value("red").
        color("red").
        width(dlen).  # helps when right aligning
        row(row).
        col(col)

      radio11 = RadioButton.new @form do
        #variable $radio
        text "c&yan"
        value "cyan"
        color "cyan"
        width dlen  # helps when right aligning
        row row
        col col+24
      end

      row += 1
      radio2 = RadioButton.new @form do
        #variable $radio
        text  "&green"
        value  "green"
        color "green"
        width dlen  # helps when right aligning
        row row
        col col
      end
      radio22 = RadioButton.new @form do
        #variable $radio
        text "magenta"
        value "magenta"
        color "magenta"
        width dlen  # helps when right aligning
        row row
        col col+24
      end
      #$radio.update_command(colorlabel) {|tv, label|  label.color tv.value; }
#
      #$radio.update_command() {|tv|  @form.widgets.each { |e| next unless e.is_a? Widget;
        #e.bgcolor tv.value };  }
      colorlabel.label_for radio1

      group = ButtonGroup.new
      [radio1, radio2, radio11, radio22].each { |r|
        group.add r
      }
      group.command(colorlabel) {|tv, label|  label.color tv.value; }
#
      group.command() {|tv|  @form.widgets.each { |e| next unless e.is_a? Widget;
        e.bgcolor tv.value };  }

      # instead of using frozen, I will use a PropertyVeto
      # to disallow changes to color itself
      veto = lambda { |e, name|
        if e.property_name == 'color'
          if e.newvalue != name
            raise PropertyVetoException.new("Cannot change this at all!", e)
          end
        elsif e.property_name == 'bgcolor'
            raise PropertyVetoException.new("Cannot change this!", e)
        end
      }
      [radio1, radio2, radio11, radio22].each { |r|
        r.bind(:PROPERTY_CHANGE) do |e| veto.call(e, r.text) end
      }

      require 'canis/core/widgets/statusline'
      @status_line = Canis::StatusLine.new @form, :row => Ncurses.LINES-2
      @status_line.command {
        "F1 Help | F2 Menu | F3 View | F4 Shell | F5 Sh | %20s" % [message_label.text]
      }
      row += 1 #2
      ## DSL style of construction
      ok_button = Button.new @form do
        text "OK"
        name "OK"
        row row
        col col
        #attr 'reverse'
        #highlight_background "white"
        #highlight_foreground "blue"
        mnemonic 'O'
      end
      ok_button.command() { |eve|
        alert("Hope you enjoyed this demo - Press the Cancel button to quit", {'title' => "Hello", :bgcolor => :blue , :color => :white})
      }

      ## conventional style of construction
      # using ampersand to set mnemonic
      cancel_button = Button.new(@form).
        text("&Cancel").
        name("Cancel").
        row(row).
        col(col + 10)
        #attr 'reverse'
        #highlight_background "white"
        #highlight_foreground "blue"
        #surround_chars ['{ ',' }']  ## change the surround chars
      cancel_button.command { |aeve|
        #if @lookfeel == :dialog
        if togglebutton.value == true
          ret = confirm("Do your really want to quit?")
        else
          ret = rb_confirm("Do your really want to quit?")
        end
        if ret
          throw(:close);
        else
          message_label.text = "Quit aborted"
        end
      }
      #col += 22
      @form.repaint
      @window.wrefresh
      Ncurses::Panel.update_panels

      # the main loop

      while((ch = @window.getchar()) != FFI::NCurses::KEY_F10 )
        break if ch == ?\C-q.getbyte(0)
        begin
          @form.handle_key(ch)

        rescue FieldValidationException => fve
          alert fve.to_s

          f = @form.get_current_field
          # lets restore the value
          if f.respond_to? :restore_original_value
            f.restore_original_value
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
    $log.debug " -==== EXCEPTION =====-"
    $log.debug( ex) if ex
    $log.debug(ex.backtrace.join("\n")) if ex
    @window.destroy if !@window.nil?
    Canis::stop_ncurses
    puts ex if ex
    puts(ex.backtrace.join("\n")) if ex
  end
end
