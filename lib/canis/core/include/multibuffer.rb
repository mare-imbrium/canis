require 'canis/core/util/promptmenu'
module Canis
  # this module makes it possible for a textview to maintain multiple buffers
  # The first buffer has been placed using set_content(lines, config). 
  # After this, additional buffers mst be supplied with add_content text, config.
  # Also, please note that after you call set_content the first time, you must call 
  # add_content so the buffer can be accessed while cycling. will try to fix this.
  # (I don't want to touch textview, would prefer not to write a decorator).

  # TODO ?? allow setting of a limit, so in some cases where we keep adding
  # programatically, the 
  # TODO: maintain cursor and line number so user can revert to same point. this will have to be
  #   updated by buffer_next and others.
  # Done: need to be able to set multiple file names. which are read in only when
  #  buffer is accessed. filename to be maintained and used as title.
  #  == CHANGE: 
  #  allow filename to be sent, rather than array. Array was very limiting since it 
  #   did not have a name to list or goto a buffer with. Also, now we can add file names that
  #   are read only if the buffer is selected.
  module MultiBuffers
    extend self

    # add content to buffers of a textview
    # @param [Array] text, or String (filename)
    # @param [Hash] options, typically :content_type => :ansi or :tmux, and :title
    def add_content text, config={}
      unless @_buffers
        bind_key(?\M-n, :buffer_next)
        bind_key(?\M-p, :buffer_prev)
        bind_key(KEY_BACKSPACE, :buffer_prev) # backspace, already hardcoded in textview !
        bind_key(?:, :buffer_menu)
      end
      @_buffers ||= []
      @_buffers_conf ||= []
      @_buffers << text
      if text.is_a? String
        config[:filename] = text
        config[:title] ||= text
      end
      @_buffers_conf << config
      @_buffer_ctr ||= 0
      $log.debug "XXX:  HELP adding text #{@_buffers.size} "
    end

    # supply an array of files to the multibuffer. These will be read
    #  as the user presses next or last etc.
    def add_files filearray, config={}
      filearray.each do |e| add_content(e, config.dup); end
    end

    # display next buffer
    def buffer_next
      buffer_update_info
      @_buffer_ctr += 1
      x = @_buffer_ctr
      l = @_buffers[x]
      if l
        populate_buffer_from_filename x
      else
        @_buffer_ctr = 0 
      end
      set_content @_buffers[@_buffer_ctr], @_buffers_conf[@_buffer_ctr]
      buffer_update_position
    end
    def populate_buffer_from_filename x
      l = @_buffers[x]
      if l
        if l.is_a? String
          if File.directory? l
            Dir.chdir(l)
            arr = Dir.entries(".")
            @_buffers[x] = arr
          else
            arr = File.open(l,"r").read.split("\n")
            @_buffers[x] = arr
          end
        end
      end
    end
    #
    # display previous buffer if any
    def buffer_prev
      buffer_update_info
      if @_buffer_ctr < 1
        buffer_last
        return
      end
      @_buffer_ctr -= 1 if @_buffer_ctr > 0
      x = @_buffer_ctr
      l = @_buffers[x]
      if l
        populate_buffer_from_filename x
        l = @_buffers[x]
        set_content l, @_buffers_conf[x]
        buffer_update_position
      end
    end
    def buffer_last
      buffer_update_info
      @_buffer_ctr = @_buffers.count - 1
      x = @_buffer_ctr
      l = @_buffers.last
      if l
        populate_buffer_from_filename x
        l = @_buffers[x]
        $log.debug "  calling set_content with #{l.class} "
        set_content l, @_buffers_conf.last
        buffer_update_position
      end
    end
    def buffer_at index
      buffer_update_info
      @_buffer_ctr = index
      l = @_buffers[index]
      if l
        populate_buffer_from_filename index
        l = @_buffers[index]
        set_content l, @_buffers_conf[index]
        buffer_update_position


      end
    end
    # close window, a bit clever, we really don't know what the CLOSE_KEY is
    def close
      @graphic.ungetch(?q.ord)
    end
    # display a menu so user can do buffer management
    # However, how can application add to these. Or disable, such as when we 
    # add buffer delete or buffer insert or edit
    def buffer_menu
      menu = PromptMenu.new self do
        item :n, :buffer_next
        item :p, :buffer_prev
        item :b, :scroll_backward
        item :f, :scroll_forward
        item :l, :list_buffers
        item :q, :close
        submenu :m, "submenu..." do
          item :p, :goto_last_position
          item :r, :scroll_right
          item :l, :scroll_left
        end
      end
      menu.display_new :title => "Buffer Menu"
    end
    # pops up a list of buffers using titles allowing the user to select
    # Based on selection, that buffer is displayed.
    def list_buffers
      arr = []
      @_buffers_conf.each_with_index do |e, i|
        t = e[:title] || "no title for #{i}"
        #$log.debug "  TITLE is #{e.title} , t is #{t} "
        arr << t
      end
      ix = popuplist arr
      buffer_at ix
    end
    def buffer_update_info
      x = @_buffer_ctr || 0
      @_buffers_conf[x][:current_index] = @current_index || 0
      @_buffers_conf[x][:curpos] = @curpos || 0
    end
    def buffer_update_position
      x = @_buffer_ctr || 0
      ci = (@_buffers_conf[x][:current_index] || 0)
      goto_line ci
      @curpos = (@_buffers_conf[x][:curpos] || 0)
    end

  end
end
