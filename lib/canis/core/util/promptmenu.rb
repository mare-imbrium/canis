# ----------------------------------------------------------------------------- #
#         File: promptmenu.rb
#  Description: a simple 'most' type menu at bottom of screen.
#               Moved from io.rb
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-04-25 - 12:32
#      License: MIT
#  Last update: 2014-04-27 00:10
# ----------------------------------------------------------------------------- #
#  promptmenu.rb  Copyright (C) 2012-2014 j kepler
#  Depends on rcommandwindow for display_menu

module Canis

  ## A *simple* way of creating menus that will appear in a single row.
  # This copies the menu at the bottom of "most" upon pressing ":".
  # hotkey is the key to invoke an item (a single digit letter)
  #
  # label is an action name
  #
  # desc is a description displayed after an item is chosen. Usually, its like:
  #+ "Folding has been enabled" or "Searches will now be case sensitive"
  #
  # action may be a Proc or a symbol which will be called if item selected
  #+ action may be another menu, so recursive menus can be built, but each
  #+ should fit in a line, its a simple system.

  CMenuItem = Struct.new( :hotkey, :label, :desc, :action )


  ## An encapsulated form of yesterday's Most Menu
  # It keeps the internals away from the user.
  # Its not really OOP in the sense that the PromptMenu is not a MenuItem. That's how it is in
  # our Menu system, and that led to a lot of painful coding (at least for me). This is quite
  # simple. A submenu contains a PromptMenu in its action object and is evaluated in a switch.
  # A recursive loop handles submenus.
  #
  # Prompting of menu options with suboptions etc.
  # A block of code or symbol or proc is executed for any leaf node
  # This allows us to define different menus for different objects on the screen, and not have to map 
  # all kinds of control keys for operations, and have the user remember them. Only one key invokes the menu
  # and the rest are ordinary characters.
  # 
  #  == Example
  #    menu = PromptMenu.new self do
  #      item :s, :goto_start
  #      item :b, :goto_bottom
  #      item :r, :scroll_backward
  #      item :l, :scroll_forward
  #      submenu :m, "submenu" do
  #        item :p, :goto_last_position
  #        item :r, :scroll_backward
  #        item :l, :scroll_forward
  #      end
  #    end
  #    menu.display_new :title => 'window title', :prompt => "Choose:"

  class PromptMenu
    include Io
    attr_reader :text
    attr_reader :options
    def initialize caller,  text="Choose:", &block
      @caller = caller
      @text = text
      @options = []
      yield_or_eval &block if block_given?
    end
    def add *menuitem
      item = nil
      case menuitem.first
      when CMenuItem
        item = menuitem.first
        @options << item
      else
        case menuitem.size
        when 4
          item = CMenuItem.new(*menuitem.flatten)
        when 2
          # if user only sends key and symbol
          menuitem[3] = menuitem[1]
          item = CMenuItem.new(*menuitem.flatten)
        when 1
          if menuitem.first.is_a? Action
            item = menuitem.first
          else
            raise ArgumentError, "Don't know how to handle #{menuitem.size} : #{menuitem} "
          end
        else
          raise ArgumentError, "Don't know how to handle #{menuitem.size} : #{menuitem} "
        end
        @options << item
      end
      return item
    end
    alias :item :add
    def create_mitem *args
      item = CMenuItem.new(*args.flatten)
    end
    # Added this, since actually it could have been like this 2011-12-22  
    def self.create_menuitem *args
      item = CMenuItem.new(*args.flatten)
    end
    # create the whole thing using a MenuTree which has minimal information.
    # It uses a hotkey and a code only. We are supposed to resolve the display text
    # and actual proc from the caller using this code.
    def menu_tree mt, pm = self
      mt.each_pair { |ch, code| 
        if code.is_a? Canis::MenuTree
          item = pm.add(ch, code.value, "") 
          current = PromptMenu.new @caller, code.value
          item.action = current
          menu_tree code, current
        else
          item = pm.add(ch, code.to_s, "", code) 
        end
      }
    end
    # 
    # To allow a more rubyesque way of defining menus and submenus
    def submenu key, label, &block
      item = CMenuItem.new(key, label)
      @options << item
      item.action = PromptMenu.new @caller, label, &block
    end
    #
    # Display prompt_menu in columns using commandwindow
    # This is an improved way of showing the "most" like menu. The earlier
    # format would only print in one row.
    #
    def display_columns config={}
      prompt = config[:prompt] || "Choose: "
      require 'canis/core/util/rcommandwindow'
      layout = { :height => 5, :width => Ncurses.COLS-0, :top => Ncurses.LINES-6, :left => 0 }
      rc = CommandWindow.new nil, :layout => layout, :box => true, :title => config[:title] || "Menu"
      w = rc.window
      r = 4
      c = 1
      color = $datacolor
      begin
        menu = @options
        $log.debug " DISP MENU "
        ret = 0
        len = 80
        while true
          h = {}
          valid = []
          labels = []
          menu.each{ |item|
            if item.respond_to? :hotkey
              hk = item.hotkey.to_s
            else
              raise ArgumentError, "Promptmenu needs hotkey or mnemonic"
            end
            # 187compat 2013-03-20 - 19:00 throws up
            labels << "%c. %s " % [ hk.getbyte(0), item.label ]
            h[hk] = item
            valid << hk
          }
          #$log.debug " valid are #{valid} "
          color = $datacolor
          #print_this(win, str, color, r, c)
          rc.display_menu labels, :indexing => :custom
          ch=w.getchar()
          rc.clear
          #$log.debug " got ch #{ch} "
          next if ch < 0 or ch > 255
          if ch == 3 || ch == ?\C-g.getbyte(0)
            clear_this w, r, c, color, len
            print_this(w, "Aborted.", color, r,c)
            break
          end
          ch = ch.chr
          index = valid.index ch
          if index.nil?
            clear_this w, r, c, color, len
            print_this(w, "Not valid. Valid are #{valid}. C-c/C-g to abort.", color, r,c)
            sleep 1
            next
          end
          #$log.debug " index is #{index} "
          item = h[ch]
          # I don;t think this even shows now, its useless
          if item.respond_to? :desc
            desc = item.desc
            #desc ||= "Could not find desc for #{ch} "
            desc ||= ""
            clear_this w, r, c, color, len
            print_this(w, desc, color, r,c)
          end
          action = item.action
          case action
            #when Array
          when PromptMenu
            # submenu
            menu = action.options
            title = rc.title
            rc.title title +" => " + action.text # set title of window to submenu
          when Proc
            #rc.destroy
            ##bottom needs to be refreshed somehow
            #FFI::NCurses.ungetch ?j
            rc.hide
            ret = action.call
            break
          when Symbol
            if @caller.respond_to?(action, true)
              rc.hide
              $log.debug "XXX:  IO caller responds to action #{action} "
              ret = @caller.send(action)
            elsif @caller.respond_to?(:execute_this, true)
              rc.hide
              ret = @caller.send(:execute_this, action)
            else
              alert "PromptMenu: unidentified action #{action} for #{@caller.class} "
              raise "PromptMenu: unidentified action #{action} for #{@caller.class} "
            end

            break
          else 
            $log.debug " Unidentified flying class #{action.class} "
            break
          end
        end # while
      ensure
        rc.destroy
        rc = nil
      end
    end
    alias :display_new :display_columns
    alias :display :display_columns

  end # class PromptMenu


end # module
