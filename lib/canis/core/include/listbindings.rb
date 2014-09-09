# ----------------------------------------------------------------------------- #
#         File: listbindings.rb
#  Description: bindings for multi-row widgets such as listbox, table, 
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 2011-12-11 - 12:58
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-09-03 17:50
# ----------------------------------------------------------------------------- #
#
module Canis
  # 
  #  bindings for multi-row widgets such as listbox, table, 
  # 
  module ListBindings
    extend self
    def bindings
      $log.debug "YYYY:  INSIDE LISTBINDING FOR #{self.class} "
      bind_key(Ncurses::KEY_LEFT, 'cursor backward'){ cursor_backward } if respond_to? :cursor_backward
      bind_key(Ncurses::KEY_RIGHT, 'cursor_forward'){ cursor_forward } if respond_to? :cursor_forward
      # very irritating when user pressed up arrow, commented off 2012-01-4  can be made optional
      bind_key(Ncurses::KEY_UP, 'previous row'){ ret = up;  } #get_window.ungetch(KEY_BTAB) if ret == :NO_PREVIOUS_ROW }
      # the next was irritating if user wanted to add a row ! 2011-10-10 
      #bind_key(Ncurses::KEY_DOWN){ ret = down ; get_window.ungetch(KEY_TAB) if ret == :NO_NEXT_ROW }
      bind_key(Ncurses::KEY_DOWN, 'next row'){ ret = down ; }
      bind_key(279, 'goto_start'){ goto_start } 
      bind_key(277, 'goto end'){ goto_end } 
      bind_key(338, 'scroll forward'){ scroll_forward() } 
      bind_key(339, 'scroll backward'){ scroll_backward() } 

      # this allows us to set on a component basis, or global basis
      # Motivation was mainly for textarea which needs emacs keys
      kmap = $key_map_type || :both
      if kmap == :emacs || kmap == :both
        bind_key(?\C-v, 'scroll forward'){ scroll_forward }
        # clashes with M-v for toggle one key selection, i guess you can set it as you like
        bind_key(?\M-v, 'scroll backward'){ scroll_backward }
        bind_key(?\C-s, 'ask search'){ ask_search() }
        bind_key(?\C-n, 'next row'){ down() }
        bind_key(?\C-p, 'previous row'){ down() }
        bind_key(?\M->, 'goto bottom'){ goto_end() }
        bind_key(?\M-<, 'goto top'){ goto_start() }
        bind_key([?\C-x, ?>], :scroll_right)
        bind_key([?\C-x, ?<], :scroll_left)
      end
      if kmap == :vim || kmap == :both
        # some of these will not have effect in textarea such as j k, gg and G, search
        bind_key(?j, 'next row'){ down() }
        bind_key(?k, 'previous row'){ up() }
        bind_key(?w, 'forward_word'){ forward_word }
        bind_key(?b, 'backward_word'){ backward_word }
        bind_key(?W, 'forward WORD'){ forward_regex :WORD }
        bind_key(?B, 'backward WORD'){ backward_regex :WORD }
        bind_key(?\C-d, 'scroll forward'){ scroll_forward() }
        bind_key(32, 'scroll forward'){ scroll_forward() } unless $row_selector == 32
        bind_key(0, 'scroll backward'){ scroll_backward() } unless $range_selector == 0
        bind_key(?\C-b, 'scroll backward'){ scroll_backward() }
        bind_key(?\C-e, "Scroll Window Down"){ scroll_window_down } 
        bind_key(?\C-y, "Scroll Window Up"){ scroll_window_up } 
        bind_key([?g,?g], 'goto start'){ goto_start } # mapping double keys like vim
        bind_key(?G, 'goto end'){ goto_end() }

        # textpad has removed this since it messes with bookmarks which are on single-quote
        bind_key([?',?'], 'goto last position'){ goto_last_position } # vim , goto last row position (not column)
        bind_key(?L, :bottom_of_window)
        bind_key(?M, :middle_of_window)
        bind_key(?H, :top_of_window)

        bind_key(?/, :ask_search)
        bind_key(?n, :find_more)
        bind_key(?h, 'cursor backward'){ cursor_backward }  if respond_to? :cursor_backward
        bind_key(?l, 'cursor forward'){ cursor_forward } if respond_to? :cursor_forward
        bind_key(?$, :cursor_eol)
      end
      bind_key(?\C-a, 'start of line'){ cursor_bol } if respond_to? :cursor_bol
      bind_key(?\C-e, 'end of line'){ cursor_eol } if respond_to? :cursor_eol
      bind_key(?\M-l, :scroll_right)
      bind_key(?\M-h, :scroll_left)
      bind_key(KEY_ENTER, :fire_action_event)

      # save as and edit_external are only in tv and textarea
      # save_as can be given to list's also and tables
      # put them someplace so the code can be shared.
      bind_key([?\C-x, ?\C-s], :saveas)
      bind_key([?\C-x, ?e], :edit_external)
      
    end # def
    # adding here so that textpad can also use. Earlier in textarea only
    # Test out with textarea too TODO 
    # 2014-09-03 - 12:49 
    def saveas name=nil, config={}
      unless name
        name = rb_gets "File to save as: "
        return if name.nil? || name == ""
      end
      overwrite_if_exists = config[:overwrite_if_exists] || false
      unless overwrite_if_exists
        exists = File.exists? name
        if exists # need to prompt
          return unless rb_confirm("Overwrite existing file? ")
        end
      end
      # if it has been set do not prompt. or ask only if value is :ask
      # But this should only be if there is someformatting provided, that is there 
      # is a @document
      l = @list
      # the check for document is to see if it is some old widget like textarea that is calling this.
      if @document
        if config.key? :save_with_formatting
          save_with_formatting = config[:save_with_formatting] 
        else
          save_with_formatting = rb_confirm("Save with formatting?")
        end
        if save_with_formatting
          l = @list
        else
          l = @document.native_text().map do |w| w.to_s ; end
        end
      end
      #l = getvalue
      File.open(name, "w"){ |f|
        l.each { |line| f.puts line }
        #l.each { |line| f.write line.gsub(/\r/,"\n") }
      }
      rb_puts "#{name} written."
    end
    # save content of textpad overwriting if name exists
    def saveas! name=nil, config={}
      config[:overwrite_if_exists] = true
      saveas name, config
    end

    # Edit the content of the textpad using external editor defaulting to EDITOR.
    # copied from textarea, modified for textpad and document, needs to be tested TODO
    # This should not be allowed as a default, some objects may not want to allow it.
    # It should be enabled, or programmer should bind it to a key
    def edit_external
      require 'canis/core/include/appmethods'
      require 'tempfile'
      f = Tempfile.new("canis")
      l = self.text
      l.each { |line| f.puts line }
      fp = f.path
      f.flush

      editor = ENV['EDITOR'] || 'vi'
      vimp = %x[which #{editor}].chomp
      ret = shell_out "#{vimp} #{fp}"
      if ret
        lines = File.open(f,'r').readlines
        if @document
          @document.text = lines
          @document.parse_required
          self.text(@document)
          # next line works
          #self.text(lines, :content_type => :tmux)
        else
          set_content(lines)
        end
      end
    end
  end
end
include Canis::ListBindings
