# ----------------------------------------------------------------------------- #
#         File: devel.rb
#  Description: Some routines for development time
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-06-02 - 20:26
#      License: MIT
#  Last update: 2014-07-05 20:48
# ----------------------------------------------------------------------------- #
#  devel.rb  Copyright (C) 2012-2014 j kepler
require 'canis/core/include/appmethods'
require 'canis/core/util/rcommandwindow'
module Canis
  module Devel
  def devel_bindings
    form = @form
    raise "Form not set in Canis::Devel" unless form
    #alert "executing devel_bindings "
    form.bind_key(FFI::NCurses::KEY_F3,'view log') { 
      view("canis14.log", :close_key => 'q', :title => "<q> to close")
    }
    form.bind_key([?\\,?\\,?l],'view log') { 
      view("canis14.log", :close_key => 'q', :title => "<q> to close")
    }
    form.bind_key([?\\,?\\,?x],'view current') { 
      code_browse $0
    }
    form.bind_key([?\\,?\\,?c],'run command') { 
      shell_output
    }
    form.bind_key([?\\,?\\,?o],'choose file') { 
      choose_file_and_view
    }
    form.bind_key([?\\,?g,?f],'change global fore color') { 
      ret = get_string "Enter a foreground color (number)", :default => "255"
      if ret
        $def_fg_color = ret.to_i
        form.repaint_all_widgets
      end
    }
    form.bind_key([?\\,?g,?b],'change global bg color') { 
      ret = get_string "Enter a background color (number)", :default => "0"
      if ret
        $def_bg_color = ret.to_i
        form.repaint_all_widgets
      end
    }
    form.bind_key([?\\,?f,?f],'change forms fore color') { 
    }
    form.bind_key([?\\,?f,?b],'change forms bg color') { 
    }
  end
  # a quick dirty code formatter,
  # TODO : parse it at least like a help file, with a content_type :code or :ruby
  # TODO : provide key 'gf' to open other files under cursor
  # @param [String] file name to browse
  def code_browse path
      dr = ruby_renderer
      view(path, :close_key => 'q', :title => $0) do |t|
        t.renderer  dr
        t.bind_key([?\\,?\\,?o],'choose file') { 
          str = choose_file "**/*"
          if str and str != ""
            t.add_content str
            t.buffer_last
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
  def ruby_renderer
    require 'canis/core/include/defaultfilerenderer'
      dr = DefaultFileRenderer.new
      dr.insert_mapping /^\s*## /, [:red, :black]
      dr.insert_mapping /^\s*#/, [:blue, :black]
      dr.insert_mapping /^\s*(class|module)/, [:cyan, :black, BOLD]
      dr.insert_mapping /^\s*(def|function)/, [:yellow, :black, FFI::NCurses::A_BOLD]
      dr.insert_mapping /^\s*(require|load)/, [:green, :black]
      dr.insert_mapping /^\s*(end|if |elsif|else|begin|rescue|ensure|include|extend|while|unless|case |when )/, [:magenta, :black]
      return dr
  end
  def directory_renderer obj
    DirectoryRenderer.new obj
  end

  # the issue with a generic directory renderer is that it does not have 
  # the full path, the dir name that is.
  class DirectoryRenderer < ListRenderer
    attr_accessor :hash
    attr_accessor :prefix
    def initialize obj
      super
      @hash = {}
      @prefix = {}
      create_mapping
    end
    def pre_render
      super
      # hack to get path
      @path = @source.title
    end
    def create_mapping
      @hash[:dir] = [:white, nil, BOLD]
      @hash[:file] = [:white, nil, nil]
      @hash[:link] = [:red, nil, nil]
      @hash[:executable] = [:red, nil, BOLD]
      @hash[:text] = [:magenta, nil, nil]
      @hash[:zip] = [:cyan, nil, nil]
      @hash[:other] = [:blue, nil, nil]
      ##
      @prefix[:dir] = "/"
      @prefix[:link] = "@"
      @prefix[:executable] = "*"
    end
    def get_category t
      text = File.join(@path, t)
      if File.directory? text
        return :dir
      elsif File.executable? text
        return :executable
      elsif File.symlink? text
        return :link
      elsif File.exists? text
        if text =~ /\.txt$/
          return :text
        elsif text =~ /\.zip$/ or text =~ /gz$/ 
          return :zip
        else
          return :file
        end
      else
        return :other
      end
    end

    def render pad, lineno, text
      klass = get_category text
      @fg = @hash[klass][0]
      bg = @hash[klass][1]
      @bg = bg #if bg
      bg = @hash[klass][2] 
      @attr = bg # if bg 
      prefix = @prefix[klass] || " "
      @left_margin_text = prefix

      
      super
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
end # module
include Canis::Devel
