# --------------------------------------------------------------------------------- #
#         File: rmessagebox.rb
#  Description: This is a cleaner attempt at messagebox on the lines of 
#               the new tabbedpane and window.
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 03.11.11 - 22:15
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2017-03-09 23:14
#  == CHANGES
#  == TODO 
#     _ <ENTER> should result in OK being pressed if its default, ESC should result in cancel esp 2 time
#     ensure that text and message are used in isolation and not with other things
#
#     _ determine window size, but we are doing instance eval later.
#
#     _ maybe have shortcuts for some widgets field, buttons, text and label and
#       share with app and otherszz
#
#     _ stack, flow and grid
#
# --------------------------------------------------------------------------------- #

require 'canis'
require 'canis/core/include/bordertitle'

include Canis
module Canis
  extend self
  class MessageBox
    include BorderTitle
    include Canis::Utils

    attr_reader :form
    attr_reader :window
    dsl_accessor :button_type
    dsl_accessor :default_button
    #
    # a message to be printed, usually this will be the only thing supplied
    # with an OK button. This should be a short string, a label will be used
    # and input_config passed to it

    #dsl_accessor :message
    # you can also set button_orientation : :right, :left, :center
    #
    def initialize config={}, &block

      h = config.fetch(:height, nil)
      w = config.fetch(:width, nil)
      t = config.fetch(:row, nil)
      l = config.fetch(:col, nil)
      if h && w && t && l
        @window = Canis::Window.new :height => h, :width => w, :top => t, :left => l
        @graphic = @window
      end
      @form = Form.new @window

      config.each_pair { |k,v| instance_variable_set("@#{k}",v) }
      @config = config
      @row = 0
      @col = 0
      @row_offset = 1
      @col_offset = 2
      #bordertitle_init
      @color ||= :black
      @bgcolor ||= :white
      # 2014-05-31 - 11:44 adding form color 
      #   try not to set buttons color in this program, let button pick up user or form colors
      @form.color = @color
      @form.bgcolor = @bgcolor
      @maxrow = 3

      #instance_eval &block if block_given?
      yield_or_eval &block if block_given?

    end
    def item widget
      # # normalcolor gives a white on black stark title like links and elinks
      # You can also do 'acolor' to give you a sober title that does not take attention away, like mc
      # remove from existing form if set, problem with this is mnemonics -- rare situation.
      if widget.form
        f = widget.form
        f.remove_widget widget
      end
      @maxrow ||= 3
      widget.set_form @form
      widget.row ||= 0
      widget.col ||= 0
      if widget.row == 0
        widget.row = [@maxrow+1, 3].max if widget.row == 0
      else
        widget.row += @row_offset 
      end
      if widget.col === 0
        widget.col = 5 if widget.col === 0
      else
        # i don't know button_offset as yet
        widget.col += @col_offset 
      end
      # in most cases this override is okay, but what if user has set it
      # The problem is that widget and field are doing a default setting so i don't know
      # if user has set or widget has done a default setting. NOTE
      # 2014-05-31 - 12:40 CANIS BUTTONCOLOR i have commented out since it should take from form
      #   to see effect
      if false
        widget.color ||= @color    # we are overriding colors, how to avoid since widget sets it
        widget.bgcolor  ||= @bgcolor
        widget.attr = @attr if @attr # we are overriding what user has put. DARN !
      end
      @maxrow = widget.row if widget.row > @maxrow
      @suggested_h = @height || @maxrow+6
      @suggested_w ||= 0
      @suggested_w = widget.col + 15 if widget.col > @suggested_w
      # if w's given col is > width then add to suggested_w or text.length
    end
    alias :add :item
    # returns button index
    # Call this after instantiating the window
    def run
      repaint
      @form.repaint
      @window.wrefresh
      return handle_keys
    end
    def repaint
      _create_window unless @window
      acolor = get_color $reverscolor, @color, @bgcolor 
      $log.debug " MESSAGE BOX bg:#{@bgcolor} , co:#{@color} , colorpair:#{acolor}"
      @window.wbkgd(Ncurses.COLOR_PAIR(acolor)); #  does not work on xterm-256color

      #print_borders unless @suppress_borders # do this once only, unless everything changes
      #@window.print_border_mb 1,2, @height, @width, $normalcolor, FFI::NCurses::A_REVERSE
      @color_pair = get_color($datacolor, @color, @bgcolor)
      bordercolor = @border_color || @color_pair
      borderatt = @border_attrib || Ncurses::A_NORMAL
      @window.wattron(Ncurses.COLOR_PAIR(bordercolor) | (borderatt || FFI::NCurses::A_NORMAL))
      @window.print_border_mb 1,2, @height, @width, bordercolor, borderatt
      @window.wattroff(Ncurses.COLOR_PAIR(bordercolor) | (borderatt || FFI::NCurses::A_NORMAL))
      @title ||= "+-+"
      @title_color ||= $normalcolor
      title = " "+@title+" "
      # normalcolor gives a white on black stark title like links and elinks
      # You can also do 'acolor' to give you a sober title that does not take attention away, like mc
      @window.printstring(@row=1,@col=(@width-title.length)/2,title, color=@title_color)
      #print_message if @message
      create_action_buttons unless @action_buttons
    end
    # Pass a short message to be printed. 
    # This creates a label for a short message, and a field for a long one.
    # @yield field created
    # @param [String] text to display
    def message message # yield label or field being used for display for further customization
      @suggested_h = @height || 10
      message = message.gsub(/[\n\r\t]/,' ') rescue message
      message_col = 5
      @suggested_w = @width || [message.size + 8 + message_col , FFI::NCurses.COLS-2].min
      r = 3
      len = message.length
      @suggested_w = len + 8 + message_col if len < @suggested_w - 8 - message_col

      display_length = @suggested_w-8
      display_length -= message_col
      message_height = 2
      clr = @color || :white
      bgclr = @bgcolor || :black

      # trying this out. sometimes very long labels get truncated, so i give a field in wchich user
      # can use arrow key or C-a and C-e
      if message.size > display_length
        message_label = Canis::Field.new @form, {:text => message, :name=>"message_label",
          :row => r, :col => message_col, :width => display_length,  
          :bgcolor => bgclr , :color => clr, :editable => false}
      else
        message_label = Canis::Label.new @form, {:text => message, :name=>"message_label",
          :row => r, :col => message_col, :width => display_length,  
          :height => message_height, :bgcolor => bgclr , :color => clr}
      end
      @maxrow = 3
      yield message_label if block_given?
    end
    alias :message= :message

    # This is for larger messages, or messages where the size is not known.
    # A textview object is created and yielded.
    #
    def text message
      @suggested_w = @width || (FFI::NCurses.COLS * 0.80).floor
      @suggested_h = @height || (FFI::NCurses.LINES * 0.80).floor

      message_col = 3
      r = 2
      display_length = @suggested_w-4
      display_length -= message_col
      clr = @color || :white
      bgclr = @bgcolor || :black

      if message.is_a? Array
        l = longest_in_list message
        if l > @suggested_w 
          if l < FFI::NCurses.COLS
            #@suggested_w = l
            @suggested_w = FFI::NCurses.COLS-2 
          else
            @suggested_w = FFI::NCurses.COLS-2 
          end
          display_length = @suggested_w-6
        end
        # reduce width and height if you can based on array contents
      else
        message = wrap_text(message, display_length).split("\n")
      end
      # now that we have moved to textpad that +8 was causing black lines to remain after the text
      message_height = message.size #+ 8
      # reduce if possible if its not required.
      #
      r1 = (FFI::NCurses.LINES-@suggested_h)/2
      r1 = r1.floor
      w = @suggested_w
      c1 = (FFI::NCurses.COLS-w)/2
      c1 = c1.floor
      @suggested_row = r1
      @suggested_col = c1
      brow = @button_row || @suggested_h-4
      available_ht = brow - r + 1
      message_height = [message_height, available_ht].min
      # replaced 2014-04-14 - 23:51 
      message_label = Canis::TextPad.new @form, {:name=>"message_label", :text => message,
        :row => r, :col => message_col, :width => display_length, :suppress_borders => true,
        :height => message_height, :bgcolor => bgclr , :color => clr}
      #message_label.set_content message
      yield message_label if block_given?

    end
    alias :text= :text

    # similar to +text+ but to view a hash using a tree object, so one can
    #  drill down.
    # Added on 2014-08-30 - 17:39 to view an objects instance_variables and public_methods.
    def tree message
      require 'canis/core/widgets/tree'
      @suggested_w = @width || (FFI::NCurses.COLS * 0.80).floor
      @suggested_h = @height || (FFI::NCurses.LINES * 0.80).floor

      message_col = 3
      r = 2
      display_length = @suggested_w-4
      display_length -= message_col
      clr = @color || :white
      bgclr = @bgcolor || :black

      # now that we have moved to textpad that +8 was causing black lines to remain after the text
      #message_height = message.size #+ 8
      message_height = 20
      # reduce if possible if its not required.
      #
      r1 = (FFI::NCurses.LINES-@suggested_h)/2
      r1 = r1.floor
      w = @suggested_w
      c1 = (FFI::NCurses.COLS-w)/2
      c1 = c1.floor
      @suggested_row = r1
      @suggested_col = c1
      brow = @button_row || @suggested_h-4
      available_ht = brow - r + 1
      message_height = [message_height, available_ht].min
      # replaced 2014-04-14 - 23:51 
      tree = Canis::Tree.new @form, {:name=>"treedialogtree", :data => message,
        :row => r, :col => message_col, :width => display_length, :suppress_borders => true,
        :height => message_height, :bgcolor => bgclr , :color => clr}
      #message_label.set_content message
      tree.treemodel.root_visible = false
      yield tree if block_given?

    end

    # returns button index (or in some cases, whatever value was thrown
    # if user did not specify any button_type but gave his own and did throw (:close, x)
    private
    def handle_keys
      buttonindex = catch(:close) do 
        while((ch = @window.getchar()) != FFI::NCurses::KEY_F10 )
          break if ch == ?\C-q.getbyte(0) || ch == 2727 # added double esc
          begin
            # trying out repaint of window also if repaint all asked for. 12 is C-l
            if ch == 1000 or ch == 12
              repaint
            end
            @form.handle_key(ch)
            @window.wrefresh
          rescue => err
            $log.debug( err) if err
            $log.debug(err.backtrace.join("\n")) if err
            textdialog ["Error in Messagebox: #{err} ", *err.backtrace], :title => "Exception"
            @window.refresh # otherwise the window keeps showing (new FFI-ncurses issue)
            $error_message.value = ""
          ensure
          end

        end # while loop
      end # close
      $log.debug "XXX: CALLER BEING RETURNED #{buttonindex} "
      @window.destroy
      # added 2014-05-01 - 18:10 hopefully to refresh root_window.
      #Window.refresh_all
      return buttonindex 
    end
    private
    def create_action_buttons
      return unless @button_type
      @default_button = 0 if !@default_button 
      case @button_type.to_s.downcase
      when "ok"
        make_buttons ["&OK"]
      when "ok_cancel" #, "input", "list", "field_list"
        make_buttons %w[&OK &Cancel]
      when "ok_apply_cancel" #, "input", "list", "field_list"
        make_buttons %w[&OK &Apply &Cancel]
      when "yes_no"
        make_buttons %w[&Yes &No]
      when "yes_no_cancel"
        make_buttons ["&Yes", "&No", "&Cancel"]
      when "custom"
        raise "Blank list of buttons passed to custom" if @buttons.nil? or @buttons.size == 0
        make_buttons @buttons
      else
        $log.warn "No buttontype passed for creating tabbedpane. Not creating any"
        #make_buttons ["&OK"]
      end
    end
    private
    def make_buttons names
      @action_buttons = []
      $log.debug "XXX: came to NTP make buttons FORM= #{@form.name} names #{names}  "
      total = names.inject(0) {|total, item| total + item.length + 4}
      bcol = align_buttons total, @button_orientation

      # this craps out when height is zero
      brow = @row + @height-4
      brow = FFI::NCurses.LINES-2 if brow < 0
      @button_row = brow
      #color_pair = get_color($normalcolor)
      #@window.wattron(Ncurses.COLOR_PAIR(color_pair) | (@attrib || FFI::NCurses::A_NORMAL))
      #@window.mvwhline( brow-1, @col+1, Ncurses::ACS_HLINE, @width-2)
      #@window.wattroff(Ncurses.COLOR_PAIR(color_pair) | (@attrib || FFI::NCurses::A_NORMAL))
      $log.debug "XXX: putting buttons :on #{brow} , #{bcol} : #{@row} , #{@height} "
      button_ct =0
      tpp = self
      _color = @color
      _bgcolor = @bgcolor
      # 2014-05-31 - 12:50 CANIS BUTTONCOLOR not setting color since it should pick from form
      names.each_with_index do |bname, ix|
        text = bname

        button = Button.new @form do
          text text
          name bname
          row brow
          col bcol
          highlight_bgcolor $reversecolor 
          # commented off 2014-05-31 - 12:50 BUTTONCOLOR
          #color _color
          #bgcolor _bgcolor
        end
        @action_buttons << button 
        button.form = @form
        button.override_graphic  @graphic
        button.default_button(true) if (@default_button && @default_button == ix)
        index = button_ct
        tpp = self
        button.command { |form| @selected_index = index; @stop = true; 
          # ActionEvent has source event and action_command
          action =  ActionEvent.new(tpp, index, button.text)
          if @command
            @command.call(action, @args) 
          else
            # default action if you don't specify anything
            throw(:close, @selected_index)
          end
        }
        # we map the key of the button to the alphabet so user can press just the mnemonic, and not
        # just the Alt combination.
        mn = button.mnemonic
        @form.bind_key(mn.downcase) { button.fire} if mn
        button_ct += 1
        bcol += text.length+6
      end
    end
    def _create_window

      @width ||= @suggested_w || 60
      @height = @suggested_h || 10
      if @suggested_row
        @row = @suggested_row
      else
        @row = ((FFI::NCurses.LINES-@height)/2).floor
      end
      if @suggested_col
        @col = @suggested_col
      else
        w = @width
        @col = ((FFI::NCurses.COLS-w)/2).floor
      end
      @window = Canis::Window.new :height => @height, :width => @width, :top => @row, :left => @col
      @graphic = @window
      @form.window = @window
    end
    #
    # specify a code block to be fired when an action button is pressed
    # This will supply (to the code block) an ActionEvent followed by 
    # whatever args that were given. 
    # ActionEvent contains source, event, action_command which map to
    # the messagebox, selected_index (base 0) and button title.
    #
    public
    def command *args, &blk
      @command = blk
      @args = args
    end
    # returns array of widgets declared for querying
    def widgets
      @form.widgets
    end
    # returns a widget based on offset, or name (if you gave it a :name)
    # e.g. a list was declared and we wish to know the selected_indices
    def widget n
      case n
      when Integer
        @form.widgets[n]
      when String, Symbol
        @form.by_name[n] 
      else
        raise "messagebox.widget can't handle #{n.class} "
      end
    end

    # returns starting column for buttons to start painting
    # Not very correct in case of :right
    private
    def align_buttons textlen, orient=:center
      case orient
      when :left
        return @col+@col_offset
      when :right
        return (@width-textlen)-5
      else
        return (@width-textlen)/2
      end
    end
  end
end
