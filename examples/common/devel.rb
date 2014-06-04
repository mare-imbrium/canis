# ----------------------------------------------------------------------------- #
#         File: devel.rb
#  Description: Some routines for development time
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-06-02 - 20:26
#      License: MIT
#  Last update: 2014-06-04 01:55
# ----------------------------------------------------------------------------- #
#  devel.rb  Copyright (C) 2012-2014 j kepler
require 'canis/core/include/appmethods'
require 'canis/core/util/rcommandwindow'
module Canis
  def devel_bindings form
    #alert "executing devel_bindings "
    form.bind_key(FFI::NCurses::KEY_F3,'view log') { 
      view("canis14.log", :close_key => 'q', :title => "<q> to close")
    }
    form.bind_key([?\\,?\\,?l],'view log') { 
      view("canis14.log", :close_key => 'q', :title => "<q> to close")
    }
    form.bind_key([?\\,?\\,?x],'view current') { 
      # this should open file with code coloring.
      code_browse $0
    }
    form.bind_key([?\\,?\\,?c],'run command') { 
      shell_output
    }
    form.bind_key([?\\,?\\,?o],'choose file') { 
      choose_file_and_view
    }
  end
  # a quick dirty code formatter,
  # TODO : parse it at least like a help file, with a content_type :code or :ruby
  # TODO : provide key 'gf' to open other files under cursor
  # @param [String] file name to browse
  def code_browse path
      dr = DefaultFileRenderer.new
      dr.insert_mapping /^\s*## /, [:red, :black]
      dr.insert_mapping /^\s*#/, [:blue, :black]
      dr.insert_mapping /^\s*(class|module)/, [:cyan, :black, BOLD]
      dr.insert_mapping /^\s*(def|function)/, [:yellow, :black, FFI::NCurses::A_BOLD]
      dr.insert_mapping /^\s*(require|load)/, [:green, :black]
      dr.insert_mapping /^\s*(end|if |elsif|else|begin|rescue|ensure|include|extend|while|unless|case |when )/, [:magenta, :black]
      view(path, :close_key => 'q', :title => $0) do |t|
        t.renderer  dr
        t.bind_key([?\\,?\\,?o],'choose file') { 
          # currently opens a new window each time, should use same textview
          #choose_file_and_view
          str = choose_file "**/*"
          if str and str != ""
            # isnpt there a faster way like add_file ? FIXME
            # next does not take care of title
            t.add_content(File.open(str).read.split("\n"))
            t.buffer_last
            #t.title = str
          else
            alert "nothing chosen"
          end
        }
      end
  end
  # this should be available to view also.
  def choose_file_and_view glob=nil, startdir="."
    glob ||= "**/*.rb"
    str = choose_file  glob, :title => "Select a file", 
      :directory => startdir,
      :help_text => "Enter pattern, use UP DOWN to traverse, Backspace to delete, ENTER to select. Esc-Esc to quit"
    if str and str != ""
      code_browse str
    end
  end
=begin
  def file_edit fp #=@current_list.filepath
    #$log.debug " edit #{fp}"
    editor = ENV['EDITOR'] || 'vi'
    vimp = %x[which #{editor}].chomp
    shell_out "#{vimp} #{fp}"
    Window.refresh_all
  end

  # TODO we need to move these to some common file so differnt programs and demos
  # can use them on pressing space or enter.
  def file_page fp #=@current_list.filepath
    unless File.exists? fp
      pwd = %x[pwd]
      alert "No such file. My pwd is #{pwd} "
      return
    end
    ft=%x[file #{fp}]
    if ft.index("text")
      pager = ENV['PAGER'] || 'less'
      vimp = %x[which #{pager}].chomp
      shell_out "#{vimp} #{fp}"
    elsif ft.index(/zip/i)
      shell_out "tar tvf #{fp} | less"
    elsif ft.index(/directory/i)
      shell_out "ls -lh  #{fp} | less"
    else
      alert "#{fp} is not text, not paging "
      #use_on_file "als", fp # only zip or archive
    end
  end
=end

end # module
include Canis
