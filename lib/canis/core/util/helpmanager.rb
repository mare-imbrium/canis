# ----------------------------------------------------------------------------- #
#         File: helpmanager.rb
#  Description: manages display of help text and hyperlinking with other files in doc dir.
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-07-08 - 20:59
#      License: MIT
#  Last update: 2014-07-08 21:07
# ----------------------------------------------------------------------------- #
#  helpmanager.rb  Copyright (C) 2012-2014 j kepler
#  TODO
#   - the method display_help is huge and a mess. That part needs to be a class.
module Canis
  CANIS_DOCPATH = File.dirname(File.dirname(__FILE__)) + "/docs/"

  # manages the help file of an application and the inbuilt help the application provides
  #  for the widgets.
  class HelpManager  # {{{
    def initialize form, config={}, &block
      @form = form
       #super
       #instance_eval &block if block_given?
    end
    def help_text text=nil
      if text
        @help_text = text
      end
      return @help_text
    end
    # Assign help text to variable
    # @param [String] help text is a string with newlines, or an Array. Will be split if String.
    #     May use markup for help files which is a very limited subset of markdown.
    def help_text=(text); help_text(text); end

    # Displays help provided by program. If no program is specified, then default help
    # is displayed. If help was provided, then default help is also displayed on next page
    # after program's help
    def display_help
      require 'canis/core/util/textutils'
      filename = CANIS_DOCPATH + "index.txt"
      stylesheet = CANIS_DOCPATH + "style_help.yml"
      # defarr contains default help
      if File.exists?(filename)
        defarr = File.open(filename,'r').read.split("\n")
        # convert help file into styles for use by tmux
        # quick dirty converter for the moment
        defarr = Canis::TextUtils::help2tmux defarr
      else
        arr = []
        arr << "  Could not find help file for application "
        arr << "    "
        arr << "Most applications provide the following keys, unless overriden:"
        arr << "    "
        arr << "    F10         -  exit application "
        arr << "    C-q         -  exit application "
        arr << "    ? (or M-?)  -  current widget key bindings  "
        arr << "    "
        arr << "    Alt-x       -  select commands  "
        arr << "    : (or M-:)  -  select commands  "
        arr << "    "
        defarr = arr
      end
      defhelp = true
      if @help_text
        defhelp = false
        arr = @help_text
        arr = arr.split("\n") if arr.is_a? String
        arr = Canis::TextUtils::help2tmux arr # FIXME can this happen automatically if it is help format
      else
        arr = defarr
      end
      #w = arr.max_by(&:length).length
      h = FFI::NCurses.LINES - 4
      w = FFI::NCurses.COLS - 10
      wbkgd = get_color($reversecolor, :black, :cyan)

      require 'canis/core/util/viewer'
      # this was the old layout that centered with a border, but was a slight bit confusing since the bg was the same
      # as the lower window.
      _layout = [h, w, 2, 4]
      sh = Ncurses.LINES-1
      sc = Ncurses.COLS-0
      # this is the new layout that is much like bline's command list. no border, a thick app header on top
      #  and no side margin
      #  Suppressing border means that title will not be updated on app_header, we have to do so FIXME
      _layout = [ h, sc, sh - h, 0]
      doc = TextDocument.new :text => arr, :content_type => :tmux, :stylesheet => stylesheet
      Canis::Viewer.view(doc, :layout => _layout, :close_key => KEY_F10, :title => "[ Help ]", :print_footer => true,
                        :app_header => true ) do |t, items|
        # would have liked it to be 'md' or :help
        #t.content_type = :tmux
        #t.stylesheet   = stylesheet
        t.suppress_borders = true
        t.print_footer = false
        t.bgcolor = :black
        t.bgcolor = 16
        t.color = :white
        ah = items[:header]
        t.bind(:PROPERTY_CHANGE) { |eve|
          # title is not a property, so we check if text has changed and then look for title.
          if eve.property_name == :text
            #$log.debug "  PROP NAME IS #{eve.property_name} , title is #{t.title} "
            ah.text_center = t.title
          end
        }
        #t.text_patterns[:link] = Regexp.new(/\[[^\]]\]/)
        t.text_patterns[:link] = Regexp.new(/\[\w+\]/)
        t.bind_key(KEY_TAB, "goto link") { t.next_regex(:link) }
        # FIXME bgcolor add only works if numberm not symbol
        t.bind_key(?a, "increment bgcolor") { t.bgcolor += 1 ; t.bgcolor = 1 if t.bgcolor > 256; 
                                      $log.debug " HELP BGCOLOR is #{t.bgcolor} ";
                                      t.clear_pad; t.render_all }
        t.bind(:PRESS){|eve| 
          link = nil
          s = eve.word_under_cursor
          if is_link?(t, s)
            link = get_link(t, s)
          end
          #alert "word under cursor is #{eve.word_under_cursor}, link is #{link}"
          if link
            arr = read_help_file link
            if arr
              doc = TextDocument.new :text => arr, :content_type => :tmux, :stylesheet => stylesheet, :title => link
              #t.add_content arr, :title => link
              t.add_content doc
              #items[:header].text_center = "[#{link}]" 
              t.buffer_last
            else
              alert "No help file for #{link}"
            end
          else
          end
        }

        # help was provided, so default help is provided in second buffer
        unless defhelp
          doc = TextDocument.new :text => defarr, :content_type => :tmux, :stylesheet => stylesheet, :title => " General Help "
          #t.add_content defarr, :title => ' General Help ', :stylesheet => stylesheet, :content_type => :tmux
          t.add_content doc
        end
      end
    end
    def is_link? t, s
      s.index(t.text_patterns[:link]) >= 0
    end
    def get_link t, s
      s.match(t.text_patterns[:link])[0].gsub!(/[\[\]]/,"")
    end
    def read_help_file link
      filename = CANIS_DOCPATH + "#{link}.txt"
      defarr = nil
      # defarr contains default help
      if File.exists?(filename)
        defarr = File.open(filename,'r').read.split("\n")
        # convert help file into styles for use by tmux
        # quick dirty converter for the moment
        defarr = Canis::TextUtils::help2tmux defarr
      end
    end
  end # class }}}
end
