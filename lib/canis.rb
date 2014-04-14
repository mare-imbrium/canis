require "canis/version"
require 'ffi-ncurses' 
require 'canis/core/system/ncurses'
require 'canis/core/system/window'
require 'canis/core/widgets/rwidget'
# added textpad here since it is now the basis of so many others 2014-04-09 - 12:57 
require 'canis/core/widgets/textpad'
require 'canis/core/util/rdialogs'

module Canis
  # key used to select a row in multiline widgets (earlier was SPACE but conflicted with paging)
  $row_selector = 'v'.ord
  # key used to range-select rows in multiline widgets (earlier was CTRL_SPACE )
  $range_selector = 'V'.ord
  # Your code goes here...
end
