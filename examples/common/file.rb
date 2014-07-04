# ----------------------------------------------------------------------------- #
#         File: file.rb
#  Description: some common file related methods which can be used across
#              file manager demos, since we seems to have a lot of them :)
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 2011-11-15 - 19:54
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-06-30 21:40
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

end # module
include Canis
