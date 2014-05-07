# ----------------------------------------------------------------------------- #
#         File: listbindings.rb
#  Description: bindings for multi-row widgets such as listbox, table, 
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 2011-12-11 - 12:58
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-05-07 12:33
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
        ## added 2013-03-04 - 17:52 
        bind_key(?w, 'forward_word'){ forward_word }
        bind_key(?b, 'backward_word'){ backward_word }
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
      end
      bind_key(?\C-a, 'start of line'){ cursor_bol } if respond_to? :cursor_bol
      bind_key(?\C-e, 'end of line'){ cursor_eol } if respond_to? :cursor_eol
      bind_key(?\M-l, :scroll_right)
      bind_key(?\M-h, :scroll_left)

      # save as and edit_external are only in tv and textarea
      # save_as can be given to list's also and tables
      # put them someplace so the code can be shared.
      bind_key([?\C-x, ?\C-s], :saveas)
      bind_key([?\C-x, ?e], :edit_external)
      
    end # def
  end
end
include Canis::ListBindings
