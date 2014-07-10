# ----------------------------------------------------------------------------- #
#         File: file.rb
#  Description: some common file related methods which can be used across
#              file manager demos, since we seems to have a lot of them :)
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 2011-11-15 - 19:54
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-07-10 14:49
# ----------------------------------------------------------------------------- #
# NOTE after calling shell_out you now need to call Window.refresh_all if you have
# pads on the screen which are getting left black

require 'canis/core/include/appmethods'
module Canis
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
      Window.refresh_all
    elsif ft.index(/zip/i)
      shell_out "tar tvf #{fp} | less"
      Window.refresh_all
    elsif ft.index(/directory/i)
      shell_out "ls -lh  #{fp} | less"
      Window.refresh_all
    else
      alert "#{fp} is not text, not paging "
      #use_on_file "als", fp # only zip or archive
    end
  end
  def file_listing path, config={}
    listing = config[:mode] || :SHORT
    ret = []
    if File.exists? path
      files = Dir.new(path).entries
      files.delete(".")
      return files if listing == :SHORT

      files.each do |f| 
        if listing == :LONG
          pf = File.join(path, f)
          if File.exists? pf
            $log.info "  File (#{f}) found "
          else
            $log.info "  File (#{f}) NOT found "
          end
          stat = File.stat(pf)
          ff = "%10s  %s  %s" % [readable_file_size(stat.size,1), date_format(stat.mtime), f]
          ret << ff
        end
      end
    end
    return ret
  end
  ## code related to long listing of files
  GIGA_SIZE = 1073741824.0
  MEGA_SIZE = 1048576.0
  KILO_SIZE = 1024.0

  # Return the file size with a readable style.
  def readable_file_size(size, precision)
    case
      #when size == 1 : "1 B"
    when size < KILO_SIZE then "%d B" % size
    when size < MEGA_SIZE then "%.#{precision}f K" % (size / KILO_SIZE)
    when size < GIGA_SIZE then "%.#{precision}f M" % (size / MEGA_SIZE)
    else "%.#{precision}f G" % (size / GIGA_SIZE)
    end
  end
  ## format date for file given stat
  def date_format t
    t.strftime "%Y/%m/%d"
  end

end # module
include Canis
