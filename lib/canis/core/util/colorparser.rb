# ----------------------------------------------------------------------------- #
#         File: colorparser.rb
#  Description: Default parse for our tmux format
#               The aim is to be able to specify parsers so different kinds
#               of formatting or documents can be used, such as ANSI formatted
#               manpages.
#       Author: jkepler http://github.com/mare-imbrium/canis/
#         Date: 07.11.11 - 13:17
#      License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
#  Last update: 2014-05-19 12:56
# ----------------------------------------------------------------------------- #
# == TODO
#    - perhaps we can compile the regexp once and reuse
# == CHANGES
#    - adding style 2014-05-19 - 12:52 
# 

module Canis
  class DefaultColorParser

    # NOTE: Experimental and minimal
    # parses the formatted string and yields either an array of color, bgcolor and attrib
    # or the text. This will be called by convert_to_chunk.
    #
    # Currently, assumes colors and attributes are correct. No error checking or fancy stuff.
    #  s="#[fg=green]hello there#[fg=yellow, bg=black, dim]"
    # @since 1.4.1  2011-11-3 experimental, can change
    # @return [nil] knows nothign about output format. 

    # 187compat 2013-03-20 - 19:33 not working in 187 so added ,1 in some cases for string
    def parse_format s  # yields attribs or text
      ## set default colors
      color   = :white
      bgcolor = :black
      attrib  = FFI::NCurses::A_NORMAL
      text    = ""

      ## split #[...]
      a       = s.split /(#\[[^\]]*\])/
        a.each { |e| 
        ## process color or attrib portion
        if e[0,2] == "#[" && e[-1,1] == "]"
          # now resetting 1:20 PM November 3, 2011 , earlier we were  carrying over
          color, bgcolor, attrib = nil, nil, nil
          style = nil
          catch(:done) do
            e = e[2..-2]
            # TODO we could atthis point check against a hash to see if this string exists, and take
            # the array from there and pass back so we don't keep splitting and parsing.
            ## first split on commas to separate fg, bg and attr
            atts = e.split /\s*,\s*/
              atts.each { |att|  
              ## next split on =
              part = att.split /\s*=\s*/
                case part[0]
                when "fg"
                  color = part[1]
                when "bg"
                  bgcolor = part[1]
                when "style"
                  style = part[1]
                when "/end", "end"
                  yield :endcolor if block_given?
                  #next
                  throw :done
                else
                  # attrib
                  attrib = part[0]
                end
            }
            # 2013-03-25 - 13:31 if numeric color specified
            color = color.to_i if color =~ /^[0-9]+$/
              bgcolor = bgcolor.to_i if bgcolor =~ /^[0-9]+$/
              yield [color,bgcolor,attrib,style] if block_given?
          end # catch
        else
          text = e
          yield text if block_given?
        end
      }
    end

  end
end
