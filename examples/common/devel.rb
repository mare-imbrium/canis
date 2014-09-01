# ----------------------------------------------------------------------------- #
#         File: devel.rb
#  Description: Some routines for development time
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-06-02 - 20:26
#      License: MIT
#  Last update: 2014-08-30 17:50
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
  # for the current field, display the instance variables and their values
  #  as well as the public methods.
  # (We can do this in a tree format too)
  def view_properties field=@form.get_current_field
    alert "Nil field" unless field
    return unless field
    text = ["Instance Variables"]
    text << "------------------"
    #iv = field.instance_variables.map do |v| v.to_s; end
    field.instance_variables.each do |v|
      val = field.instance_variable_get(v)
      klass = val.class
      if val.is_a? Array 
        val = val.size
      elsif val.is_a? Hash
        val = val.keys
      end
      case val
      when String, Fixnum, Integer, TrueClass, FalseClass, NilClass, Array, Hash, Symbol
        ;
      else
        val = "Not shown"
      end
      text << "%20s  %10s  %s" % [v, klass, val]
    end
    text << " "
    text << "Public Methods"
    text << "--------------"
    pm = field.public_methods(false).map do |v| v.to_s; end
    text +=  pm
    text << " "
    text << "Inherited Methods"
    text << "-----------------"
    pm = field.public_methods(true) - field.public_methods(false)
    pm = pm.map do |v| v.to_s; end
    text +=  pm

    #$log.debug "  view_properties #{s.size} , #{s} "
    textdialog text, :title => "Properties"
  end

  # place instance_vars of current or given object into a hash
  #  and view in a treedialog.
  def view_properties_as_tree field=@form.get_current_field
    alert "Nil field" unless field
    return unless field
    text = []
    tree = {}
    #iv = field.instance_variables.map do |v| v.to_s; end
    field.instance_variables.each do |v|
      val = field.instance_variable_get(v)
      klass = val.class
      if val.is_a? Array 
        #tree[v.to_s] = val
        text << { v.to_s => val }
        val = val.size
      elsif val.is_a? Hash
        #tree[v.to_s] = val
        text << { v.to_s => val }
        if val.size <= 5
          val = val.keys
        else
          val = val.keys.size.to_s + " [" + val.keys.first(5).join(", ") + " ...]"
        end
      end
      case val
      when String, Fixnum, Integer, TrueClass, FalseClass, NilClass, Array, Hash, Symbol
        ;
      else
        val = "Not shown"
      end
      text << "%-20s  %10s  %s" % [v, klass, val]
    end
    tree["Instance Variables"] = text
    pm = field.public_methods(false).map do |v| v.to_s; end
    tree["Public Methods"] = pm
    pm = field.public_methods(true) - field.public_methods(false)
    pm = pm.map do |v| v.to_s; end
    tree["Inherited Methods"] = pm

    #$log.debug "  view_properties #{s.size} , #{s} "
    treedialog tree, :title => "Properties"
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
    #DirectoryRenderer.new obj
    LongDirectoryRenderer.new obj
  end

  # the issue with a generic directory renderer is that it does not have 
  # the full path, the dir name that is.
  # FIXME: this expects text to be only a filename, but what about long listings.
  #  In long listings the left_margin char will print at start whereas the filename
  #   comes later in last slot of array
  class DirectoryRenderer < ListRenderer
    attr_accessor :hash
    attr_accessor :prefix
    # specify if long, short or full listing
    attr_accessor :mode
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
      klass = get_category fullname
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
  class LongDirectoryRenderer < ListRenderer
    attr_accessor :hash
    attr_accessor :prefix
    # specify if long, short or full listing
    attr_accessor :mode
    attr_accessor :formatter
    def initialize obj
      super
      @hash = {}
      @prefix = {}
      @default_formatter = Formatter.new
      @formatter = nil
      create_mapping
    end
    def format_message(fname, stat, prefix=nil)
      (@formatter || @default_formatter).call(fname, stat, prefix)
    end
    # Set date-time format.
    #
    # +datetime_format+:: A string suitable for passing to +strftime+.
    def datetime_format=(datetime_format)
      @default_formatter.datetime_format = datetime_format
    end

    # Returns the date format being used.  See #datetime_format=
    def datetime_format
      @default_formatter.datetime_format
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
    # recieves the full path and returns a symbol for category
    def get_category text
      #text = File.join(@path, t)
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

    # long directory renderer
    # text is only the file name without path
    def render pad, lineno, text
      fullname = File.join(@path, text)
      klass = get_category fullname
      $log.info "fullname is #{fullname}, #{klass} "
      # some links throw up an error of no such file
      _stat = File.stat(fullname) rescue File.lstat(fullname)
      @fg = @hash[klass][0]
      bg = @hash[klass][1]
      @bg = bg #if bg
      bg = @hash[klass][2] 
      @attr = bg # if bg 
      prefix = @prefix[klass] || " "
      #@left_margin_text = prefix
      ftext = format_message( text, _stat, prefix)

      super pad, lineno, ftext
    end
    class Formatter
      #Format = "%s, [%s#%d] %5s -- %s: %s\n"
      Format = "%10s  %s  %s%s" 
        # % [readable_file_size(stat.size,1), date_format(stat.mtime), f]

      attr_accessor :datetime_format

      def initialize
        @datetime_format = nil
      end

      def call(fname, stat, prefix=nil)
        #Format % [severity[0..0], format_datetime(time), $$, severity, progname,
                  #msg2str(msg)]
        Format % [stat.size, format_datetime(stat.mtime), prefix, fname]
      end

      private

      def format_datetime(time)
        if @datetime_format.nil?
          #time.strftime("%Y-%m-%dT%H:%M:%S") << "%06d " % time.usec
          time.strftime("%Y-%m-%d %H:%M")
        else
          time.strftime(@datetime_format)
        end
      end

    end # class Formatter

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
