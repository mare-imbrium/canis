# To test out the new messagebox
#  The old messagebox provided a lot of convenience methods that were complicated
#  and confusing. This one is simpler.
#  The examples here are based on the old test1.rb that will not work now
#  since the interface has been changed and simplified
#
require 'logger'
require 'canis'
require 'canis/core/widgets/rmessagebox'
#require 'canis/deprecated/widgets/rmessagebox'

if $0 == __FILE__
  # Initialize curses
  begin
    # XXX update with new color and kb
    Canis::start_ncurses  # this is initializing colors via ColorMap.setup
    $log = Logger.new((File.join(ENV['LOGDIR'] || "./" ,"canis14.log")))
    $log.level = Logger::DEBUG

#    @window = Canis::Window.root_window


    catch(:close) do
      choice = ARGV[0] && ARGV[0].to_i || 3
      $log.debug "START  MESSAGE BOX TEST #{ARGV[0]}. choice==#{choice} ---------"
      # need to pass a form, not window.
      case choice
      when 1
        require 'canis/core/widgets/listbox'
        nn = "mylist"
        l = Listbox.new  nil, :row => 2, :col => 5, :list => %w[john tim lee wong kepler edward why chad andy],
          :selection_mode => :multiple, :height => 10, :width => 20 , :selected_color => :green, :selected_bgcolor => :white, :selected_indices => [2,6], :name => nn
       #default_values %w[ lee why ]

        l.unbind_key(KEY_ENTER)
      @mb = MessageBox.new :width => 30, :height => 18 do
        title "Select a name"
        button_type :ok_cancel
        item Label.new :row => 1, :col => 1, :text => "Enter your name:"
        item l
      end
      @mb.run
      $log.debug "XXX:  #{l.selected_indices}  "
      n = @mb.widget(nn)
      $log.debug "XXXX:  #{n.selected_indices}, #{n.name}  "
      when 2
      @mb = Canis::MessageBox.new do
        title "Color selector"
        message "Select a color"
        #item Label.new :text => "Select a color", :row => 1 , :col => 2

        r = 3
        c = 2
        %w[&red &green &blue &yellow].each_with_index { |b, i|
          bu =  Button.new :name => b, :text => b, :row => r, :col => c
          bu.command { throw(:close, i) }
          item bu
          #bu.default_button(true) if i == 0
          #r += 1
          c += b.length + 5
        }
      end
      index = @mb.run
      $log.debug "XXX:  messagebox 2 ret #{index} "
      when 3
      @mb = Canis::MessageBox.new do
        title "Enter your name"
        #message "Enter your first name. You are not permitted to enter x z or q and must enter a capital first"
        message "Enter your first name. Initcaps "
        add Field.new :chars_allowed => /[^0-9]/, :valid_regex => /^[A-Z][a-z]*/, :default => "Matz", :bgcolor => :cyan
        button_type :ok_cancel
      end
      @mb.run
      $log.debug "XXX:  got #{@mb.widget(1).text} "
      when 4
      mb = MessageBox.new :title => "HTTP Configuration" , :width => 50 do
        add LabeledField.new :label => 'User', :name => "user", :width => 30, :bgcolor => :cyan
        add CheckBox.new :text => "No &frames", :onvalue => "Selected", :offvalue => "UNselected"
        add CheckBox.new :text => "Use &HTTP/1.0", :value => true
        add CheckBox.new :text => "Use &passive FTP"
        add Label.new    :text => " Language ", :attr => REVERSE
        $radio = Canis::Variable.new
        add RadioButton.new :text => "py&thon", :value => "python", :color => :blue, :variable => $radio
        add RadioButton.new :text => "rub&y", :color => :red, :variable => $radio
        button_type :ok
      end
      field = mb.widget("user")
      field.bind(:ENTER) do |f|
        listconfig = {:bgcolor => :blue, :color => :white,
                      :relative_to => field, :col => field.col + 6, :width => field.width}
        users= %w[john tim lee wong kepler edward _why chad andy]
        #index = popuplist(users, :relative_to => field, :col => field.col + 6, :width => field.width)
        index = popuplist(users, listconfig)
        field.text users[index] if index
      end
      mb.run

      when 5
        require 'canis/core/widgets/listbox'
        label = Label.new 'text' => 'File', 'mnemonic'=>'F', :row => 3, :col => 5
        field = Field.new :name => "file", :row => 3 , :col => 10, :width => 40, :set_label => label
        #flist = Dir.glob(File.join( File.expand_path("~/"), "*"))
        flist = Dir.glob("*")
        listb = Listbox.new :name => "mylist", :row => 4, :col => 3, :width => 50, :height => 10,
          :list => flist, :title => "File List", :selected_bgcolor => :white, :selected_color => :blue,
          :selection_mode => :single, :border_attrib => REVERSE
        #listb.bind(:ENTER_ROW) { field.text listb.selected_item }
        # if you find that cursor goes into listbox while typing, then
        # i've put set_form_row in listbox list_data_changed
        field.bind(:CHANGE) do |f|
          flist = Dir.glob("*"+f.getvalue+"*")
          #l.insert( 0, *flist) if flist
          listb.list flist
        end
        listb.unbind_key(KEY_ENTER)
        mb = Canis::MessageBox.new :height => 20, :width => 60 do
          title "Sample File Selector"
          add label
          add field
          add listb
          #height 20
          #width 60
          #top 5
          #left 20
          #default_button 0
          button_type :ok_cancel

        end
        mb.run
        $log.debug "MBOX :1selected #{listb}"
        $log.debug "MBOX :selected #{listb.selected_value}"
      end

    end
  rescue => ex
  ensure
    @window.destroy unless @window.nil?
    Canis::stop_ncurses
    p ex if ex
    p(ex.backtrace.join("\n")) if ex
    $log.debug( ex) if ex
    $log.debug(ex.backtrace.join("\n")) if ex
  end
end
