# Some methods for traversing list like widgets such as tree, listbox and maybe table
# Different components may bind different keys to these
#
module Canis
  module ListOperations

    # get a char ensure it is a char or number
    # In this state, it could accept control and other chars.
    private
    def _ask_a_char
      ch = @graphic.getch
      #message "achar is #{ch}"
      if ch < 26 || ch > 255
        @graphic.ungetch ch
        return :UNHANDLED
      end
      return ch.chr
    end
    public
    # sets the selection to the next row starting with char
    # Trying to return unhandled is having no effect right now. if only we could pop it into a
    # stack or unget it.
    def set_selection_for_char char=nil
      char = _ask_a_char unless char
      #alert "got #{char} "
      return :UNHANDLED if char == :UNHANDLED
      @oldrow = @current_index
      @last_regex = /^#{char}/
      ix = next_regex @last_regex
      #alert "next returned #{ix}"
      return unless ix
      @current_index = ix[0] 
      @search_found_ix = @current_index
      @curpos = ix[1]
      ensure_visible
      return @current_index
    end
    # Find the next row that contains given string
    # @return row and col offset of match, or nil
    # @param String to find
    def  next_regex str
      first = nil
      ## content can be string or Chunkline, so we had to write <tt>index</tt> for this.
      ## =~ does not give an error, but it does not work.
      @list.each_with_index do |line, ix|
        #col = line.index str
        # for treemodel which will give us user_object.to_s
        col = line.to_s.index str
        if col
          first ||= [ ix, col ]
          if ix > @current_index
            return [ix, col]
          end
        end
      end
      return first
    end


  end # end module
end # end module
