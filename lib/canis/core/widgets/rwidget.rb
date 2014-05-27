=begin
  * Name: rwidget: base class and then basic widgets like field, button and label
  * Description   
    Some simple light widgets for creating ncurses applications. No reliance on ncurses
    forms and fields.
        I expect to pass through this world but once. Any good therefore that I can do, 
        or any kindness or ablities that I can show to any fellow creature, let me do it now. 
        Let me not defer it or neglect it, for I shall not pass this way again.  
  * Author: jkepler (ABCD)
  * Date: 2008-11-19 12:49 
  * License: Same as Ruby's License (http://www.ruby-lang.org/LICENSE.txt)
  * Last update: 2014-05-27 16:47

  == CHANGES
  * 2011-10-2 Added PropertyVetoException to rollback changes to property
  * 2011-10-2 Returning self from dsl_accessor and dsl_property for chaining
  * 2011-10-2 removing clutter of buffering, a lot of junk code removed too.
  * 2014-04-23 major cleanup. removal of text_variable.
  == TODO 


=end
require 'logger'
require 'canis/core/system/colormap'
#require 'canis/core/include/orderedhash'
require 'canis/core/include/rinputdataevent' # for FIELD 2010-09-11 12:31 
require 'canis/core/include/io'
require 'canis/core/system/keydefs'

# 2013-03-21 - 187compat removed ||
BOLD = FFI::NCurses::A_BOLD
REVERSE = FFI::NCurses::A_REVERSE
UNDERLINE = FFI::NCurses::A_UNDERLINE
NORMAL = FFI::NCurses::A_NORMAL
CANIS_DOCPATH = File.dirname(File.dirname(__FILE__)) + "/docs/"

class Object # yeild eval {{{
# thanks to terminal-table for this method
  def yield_or_eval &block
    return unless block
    if block.arity > 0 
      yield self
    else
      self.instance_eval(&block)
    end 
  end
end
# 2009-10-04 14:13 added RK after suggestion on http://www.ruby-forum.com/topic/196618#856703
# these are for 1.8 compatibility
unless "a"[0] == "a"
  class Fixnum
    def ord
      self
    end
    ## mostly for control and meta characters
    def getbyte(n)
      self
    end
  end unless "a"[0] == "a"
  # 2013-03-21 - 187compat
  class String
    ## mostly for control and meta characters
    def getbyte(n)
      self[n]
    end
  end
end # }}}
class Module  # dsl_accessor {{{
## others may not want this, sets config, so there's a duplicate hash
  # also creates a attr_writer so you can use =.
  #  2011-10-2 V1.3.1 Now returning self, so i can chain calls
  def dsl_accessor(*symbols)
    symbols.each { |sym|
      class_eval %{
        def #{sym}(*val)
          if val.empty?
            @#{sym}
          else
            @#{sym} = val.size == 1 ? val[0] : val
            self # 2011-10-2 
          end
        end
      # can the next bypass validations
    attr_writer sym 
      }
    }
  end
  # Besides creating getters and setters,  this also fires property change handler
  # if the value changes, and after the object has been painted once.
  #  2011-10-2 V1.3.1 Now returning self, so i can chain calls
  def dsl_property(*symbols)
    symbols.each { |sym|
      class_eval %{
        def #{sym}(*val)
          if val.empty?
            @#{sym}
          else
            oldvalue = @#{sym}
            tmp = val.size == 1 ? val[0] : val
            newvalue = tmp
            if oldvalue.nil? || @_object_created.nil?
               @#{sym} = tmp
            end
            return(self) if oldvalue.nil? || @_object_created.nil?

            if oldvalue != newvalue
              # trying to reduce calls to fire, when object is being created
               begin
                 @property_changed = true
                 fire_property_change("#{sym}", oldvalue, newvalue) if !oldvalue.nil?
                 @#{sym} = tmp
                 @config["#{sym}"]=@#{sym}
               rescue PropertyVetoException
                  $log.warn "PropertyVetoException for #{sym}:" + oldvalue.to_s + "->  "+ newvalue.to_s
               end
            end # if old
            self
          end # if val
        end # def
    #attr_writer sym
        def #{sym}=val
           #{sym}(val)
        end
      }
    }
  end
  # divert an = call to the dsl_property or accessor call.
  #  This is required if I am bypassing dsl_property for some extra processing as in color and bgcolor
  #  but need the rest of it.
  def dsl_writer(*symbols)
    symbols.each { |sym|
      class_eval %{
        def #{sym}=(val)
           #{sym}(val)
        end
      }
    }
  end

end # }}}


module Canis
  extend self
  include ColorMap
    class FieldValidationException < RuntimeError
    end

    # The property change is not acceptable, undo it. e.g. test2.rb
    # @param [String] text message
    # @param [Event] PropertyChangeEvent object
    # @since 1.4.0
    class PropertyVetoException < RuntimeError
      def initialize(string, event)
        @string = string
        @event = event
        super(string)
      end
      attr_reader :string, :event
    end

    module Utils   # --- {{{
      ## this is the numeric argument used to repeat and action by repeatm()
      $multiplier = 0

      # 2010-03-04 18:01 
      ## this may come in handy for methods to know whether they are inside a batch action or not
      # e.g. a single call of foo() may set a var, a repeated call of foo() may append to var
      $inside_multiplier_action = true


      # convenience func to get int value of a key
      # added 2014-05-05
      # instead of ?\C-a.getbyte(0)
      # use key(?\C-a)
      # or key(?a) or key(?\M-x)
      def key ch
        ch.getbyte(0)
      end
      # returns a string representation of a given int keycode
      # @param [Fixnum] keycode read by window
      #    In some case, such as Meta/Alt codes, the window reads two ints, but still we are using the param
      #    as the value returned by ?\M-a.getbyte(0) and such, which is typically 128 + key
      # @return [String] a string representation which is what is to be used when binding a key to an
      #     action or Proc. This is close to what vimrc recognizes such as <CR> <C-a> a-zA-z0-9 <SPACE>
      #     Hopefully it should be identical to what vim recognizes in the map command.
      #     If the key is not known to this program it returns "UNKNOWN:key" which means this program
      #     needs to take care of that combination. FIXME some numbers are missing in between.
      # NOTE do we really need to cache everything ? Only the computed ones should be cached ?
      def key_tos ch # -- {{{
        x = $key_cache[ch]
        return x if x
        chr = case ch
              when 10,13 , KEY_ENTER
                "<CR>"
              when 9 
                "<TAB>"
              when 0 
                "<C-@>"
              when 27
                "<ESC>"
              when 31
                "<C-/>"
              when 1..30
                x= ch + 96
                "<C-#{x.chr}>"
              when 32 
                "<SPACE>"
              when 41
                "<M-CR>"
              when 33..126
                ch.chr
              when 127,263 
                "<BACKSPACE>"
              when 128..154
                x = ch - 128
                #"<M-C-#{x.chr}>"
                xx = key_tos(x).gsub(/[<>]/,"")
                "<M-#{xx}>"
              when 160..255
                x = ch - 128
                xx = key_tos(x).gsub(/[<>]/,"")
                "<M-#{xx}>"
              when 255
                "<M-BACKSPACE>"
              when 2727
                "<ESC-ESC>"
              else

                chs =  FFI::NCurses::keyname(ch) 
                # remove those ugly brackets around function keys
                if chs && chs[-1]==')'
                  chs = chs.gsub(/[()]/,'')
                end
                if chs
                  chs = chs.gsub("KEY_","")
                  "<#{chs}>"
                else
                  "UNKNOWN:#{ch}"
                end
              end
        $key_cache[ch] = chr
        return chr
      end # --- }}}
      # only for a short while till we weed it out.
      alias :keycode_tos :key_tos
      # needs to move to a keystroke class
      # please use these only for printing or debugging, not comparing
      # I could soon return symbols instead 2010-09-07 14:14 
      # @deprecated
      # Please move to window.key_tos
      def ORIGkeycode_tos keycode # {{{
        $log.warn "XXX:  keycode_tos please move to window.key_tos"
        case keycode
        when 33..126
          return keycode.chr
        when ?\C-a.getbyte(0) .. ?\C-z.getbyte(0)
          return "C-" + (keycode + ?a.getbyte(0) -1).chr 
        when ?\M-A.getbyte(0)..?\M-z.getbyte(0)
          return "M-"+ (keycode - 128).chr
        when ?\M-\C-A.getbyte(0)..?\M-\C-Z.getbyte(0)
          return "M-C-"+ (keycode - 32).chr
        when ?\M-0.getbyte(0)..?\M-9.getbyte(0)
          return "M-"+ (keycode-?\M-0.getbyte(0)).to_s
        when 32
          return "space" # changed to lowercase so consistent
        when 27
          return "esc" # changed to lowercase so consistent
        when ?\C-].getbyte(0)
          return "C-]"
        when 258
          return "down"
        when 259
          return "up"
        when 260
          return "left"
        when 261
          return "right"
        when FFI::NCurses::KEY_F1..FFI::NCurses::KEY_F12
          return "F"+ (keycode-264).to_s
        when 330
          return "delete"
        when 127
          return "bs"
        when 353
          return "btab"
        when 481
          return "M-S-tab"
        when 393..402
          return "M-F"+ (keycode-392).to_s
        when 0
          return "C-space" 
        when 160
          return "M-space" # at least on OSX Leopard now (don't remember this working on PPC)
        when C_LEFT
          return "C-left"
        when C_RIGHT
          return "C-right"
        when S_F9
          return "S_F9"
        else
          others=[?\M--,?\M-+,?\M-=,?\M-',?\M-",?\M-;,?\M-:,?\M-\,, ?\M-.,?\M-<,?\M->,?\M-?,?\M-/,?\M-!]
          others.collect! {|x| x.getbyte(0)  }  ## added 2009-10-04 14:25 for 1.9
          s_others=%w[M-- M-+ M-= M-' M-"   M-;   M-:   M-, M-. M-< M-> M-? M-/ M-!]
          if others.include? keycode
            index = others.index keycode
            return s_others[index]
          end
          # all else failed
          return keycode.to_s
        end
      end # }}}

      # if passed a string in second or third param, will create a color 
      # and return, else it will return default color
      # Use this in order to create a color pair with the colors
      # provided, however, if user has not provided, use supplied
      # default.
      # @param [Fixnum] color_pair created by ncurses
      # @param [Symbol] color name such as white black cyan magenta red green yellow
      # @param [Symbol] bgcolor name such as white black cyan magenta red green yellow
      # @example get_color $promptcolor, :white, :cyan
      def get_color default=$datacolor, color=@color, bgcolor=@bgcolor
        return default if color.nil? || bgcolor.nil?
        #raise ArgumentError, "Color not valid: #{color}: #{ColorMap.colors} " if !ColorMap.is_color? color
        #raise ArgumentError, "Bgolor not valid: #{bgcolor} : #{ColorMap.colors} " if !ColorMap.is_color? bgcolor
        acolor = ColorMap.get_color(color, bgcolor)
        return acolor
      end
      #
      # convert a string to integer attribute
      # FIXME: what if user wishes to OR two attribs, this will give error
      # @param [String] e.g. reverse bold normal underline
      #     if a Fixnum is passed, it is returned as is assuming to be 
      #     an attrib
      def get_attrib str
        return FFI::NCurses::A_NORMAL unless str
        # next line allows us to do a one time conversion and keep the value
        #  in the same variable
        if str.is_a? Fixnum
          if [
            FFI::NCurses::A_BOLD,
            FFI::NCurses::A_REVERSE,    
            FFI::NCurses::A_NORMAL,
            FFI::NCurses::A_UNDERLINE,
            FFI::NCurses::A_STANDOUT,    
            FFI::NCurses::A_DIM,    
            FFI::NCurses::A_BOLD | FFI::NCurses::A_REVERSE,    
            FFI::NCurses::A_BOLD | FFI::NCurses::A_UNDERLINE,    
            FFI::NCurses::A_REVERSE | FFI::NCurses::A_UNDERLINE,    
            FFI::NCurses::A_BLINK
          ].include? str
          return str
          else
            raise ArgumentError, "get_attrib got a wrong value: #{str} "
          end
        end


        att = nil
        str = str.downcase.to_sym if str.is_a? String
        case str #.to_s.downcase
        when :bold
          att = FFI::NCurses::A_BOLD
        when :reverse
          att = FFI::NCurses::A_REVERSE    
        when :normal
          att = FFI::NCurses::A_NORMAL
        when :underline
          att = FFI::NCurses::A_UNDERLINE
        when :standout
          att = FFI::NCurses::A_STANDOUT
        when :bold_reverse
          att = FFI::NCurses::A_BOLD | FFI::NCurses::A_REVERSE
        when :bold_underline
          att = FFI::NCurses::A_BOLD | FFI::NCurses::A_UNDERLINE
        when :dim
          att = FFI::NCurses::A_DIM    
        when :blink
          att = FFI::NCurses::A_BLINK    # unlikely to work
        else
          att = FFI::NCurses::A_NORMAL
        end
        return att
      end

      ## repeats the given action based on how value of universal numerica argument
      ##+ set using the C-u key. Or in vim-mode using numeric keys
      def repeatm
        $inside_multiplier_action = true
        _multiplier = ( ($multiplier.nil? || $multiplier == 0) ? 1 : $multiplier )
        _multiplier.times { yield }
        $multiplier = 0
        $inside_multiplier_action = false
      end
      # this is the bindkey that has been working all along. now i am trying a new approach
      # that does not use a hash inside but keeps on key. so it can be manip easily be user
      def ORIGbind_key keycode, *args, &blk # -- {{{
        #$log.debug " #{@name} bind_key received #{keycode} "
        @_key_map ||= {}
        #
        # added on 2011-12-4 so we can pass a description for a key and print it
        # The first argument may be a string, it will not be removed
        # so existing programs will remain as is.
        @key_label ||= {}
        if args[0].is_a?(String) || args[0].is_a?(Symbol)
          @key_label[keycode] = args[0] 
        else
          @key_label[keycode] = :unknown
        end

        if !block_given?
          blk = args.pop
          raise "If block not passed, last arg should be a method symbol" if !blk.is_a? Symbol
          #$log.debug " #{@name} bind_key received a symbol #{blk} "
        end
        case keycode
        when String
          # single assignment
          keycode = keycode.getbyte(0) #if keycode.class==String ##    1.9 2009-10-05 19:40 
          #$log.debug " #{name} Widg String called bind_key BIND #{keycode}, #{keycode_tos(keycode)}  "
          #$log.debug " assigning #{keycode}  " if $log.debug? 
          @_key_map[keycode] = blk
        when Array
          # double assignment
          # for starters lets try with 2 keys only
          raise "A one key array will not work. Pass without array" if keycode.size == 1
          a0 = keycode[0]
          a0 = keycode[0].getbyte(0) if keycode[0].class == String
          a1 = keycode[1]
          a1 = keycode[1].getbyte(0) if keycode[1].class == String
          @_key_map[a0] ||= OrderedHash.new
          #$log.debug " assigning #{keycode} , A0 #{a0} , A1 #{a1} " if $log.debug? 
          @_key_map[a0][a1] = blk
          #$log.debug " XX assigning #{keycode} to  _key_map " if $log.debug? 
        else
          #$log.debug " assigning #{keycode} to  _key_map " if $log.debug? 
          @_key_map[keycode] = blk
        end
        @_key_args ||= {}
        @_key_args[keycode] = args

      end # --- }}}

      ##
      # A new attempt at a flat hash 2014-05-06 - 00:16 
      # bind an action to a key, required if you create a button which has a hotkey
      # or a field to be focussed on a key, or any other user defined action based on key
      # e.g. bind_key ?\C-x, object, block 
      # added 2009-01-06 19:13 since widgets need to handle keys properly
      #  2010-02-24 12:43 trying to take in multiple key bindings, TODO unbind
      #  TODO add symbol so easy to map from config file or mapping file
      #
      #  Ideally i want to also allow a regex and array/range to be used as a key 
      #  However, then how do i do multiple assignments which use an array.
      #
      #  Currently the only difference is that there is no hash inside the value,
      #  key can be an int, or array of ints (for multiple keycode like qq or gg).
      def bind_key keycode, *args, &blk
        #$log.debug " #{@name} bind_key received #{keycode} "
        @_key_map ||= {}
        #
        # added on 2011-12-4 so we can pass a description for a key and print it
        # The first argument may be a string, it will not be removed
        # so existing programs will remain as is.
        @key_label ||= {}
        if args[0].is_a?(String) || args[0].is_a?(Symbol)
          @key_label[keycode] = args[0] 
        else
          @key_label[keycode] = :unknown
        end

        if !block_given?
          blk = args.pop
          raise "If block not passed, last arg should be a method symbol" if !blk.is_a? Symbol
          #$log.debug " #{@name} bind_key received a symbol #{blk} "
        end
        case keycode
        when String
          # single assignment
          keycode = keycode.getbyte(0) #if keycode.class==String ##    1.9 2009-10-05 19:40 
          #@_key_map[keycode] = blk
        when Array
          # double assignment
          # this means that all these keys have to be pressed in succession for this block, like "gg" or "C-x C-c"
          raise "A one key array will not work. Pass without array" if keycode.size == 1
          ee = []
          keycode.each do |e| 
            e = e.getbyte(0) if e.is_a? String
            ee << e
          end
          bind_composite_mapping ee, args, &blk
          return self
          #@_key_map[a0] ||= OrderedHash.new
          #@_key_map[a0][a1] = blk
          #$log.debug " XX assigning #{keycode} to  _key_map " if $log.debug? 
        else
          #$log.debug " assigning #{keycode} to  _key_map " if $log.debug? 
        end
        @_key_map[keycode] = blk
        @_key_args ||= {}
        @_key_args[keycode] = args
        self
      end
=begin
# this allows us to play a bit with the map, and allocate one action to another key
#      get_action_map()[KEY_ENTER] = get_action(32)
#      But we will hold on this unless absolutely necessary. 2014-05-12 - 22:36 CANIS.
      def get_action keycode
        @_key_map[keycode]
      end
      def get_action_map 
        @_key_map
      end
=end
      class MapNode
        attr_accessor :action
        attr_accessor :map
        def initialize arg=nil
          @map = Hash.new {|hash, key| hash[key] = MapNode.new }
        end
        def put key, value
          @map[key].action = value
        end
        # fetch / get returns a node, or nil. if node, then use node.action
        def fetch key, deft=nil
          @map.fetch(key, deft)
        end
      end

      def bind_composite_mapping key, *args, &action
        @_key_composite_map ||= Hash.new {|hash, key| hash[key] = MapNode.new }
        if key.is_a? String
          n = @_key_composite_map[key]
          n.action = action
        else
          mp = @_key_composite_map
          n = nil
          key.each do |e|
            n = mp[e]
            mp = n.map
          end
          n.action = action
        end
        val = @_key_composite_map.fetch(key[0], nil)
        $log.debug " composite contains #{key} : #{val} "
      end
      def check_composite_mapping key, window
        $log.debug  "inside check with #{key} "
        return nil if !@_key_composite_map
        return nil if !@_key_composite_map.key? key
        $log.debug "  composite has #{key} "

        # we have a match and need to loop
        mp = @_key_composite_map
        n = nil
        actions = []
        unconsumed = []
        e = key
        while true

          # we traverse each key and get action of final.
          # However, if at any level there is a failure, we need to go back to previous action
          # and push the other keys back so they can be again processed.
          if e.nil? or e == -1
            #puts "e is nil TODO "
            # TODO
            $log.debug "  -1  push #{unconsumed} " 
            unconsumed.each {|e| window.ungetch(e)}
            return actions.last 
          else
            $log.debug  " in loop with #{e} "
            unconsumed << e
            n = mp.fetch(e, nil)
            $log.debug  " got node #{n} with #{e} "
            # instead of just nil, we need to go back up, but since not recursive ...
            #return nil unless n
            $log.debug  "push #{unconsumed} " unless n
            unconsumed.each {|e| window.ungetch(e)} unless n
            return actions.last unless n
            mp = n.map
            # there are no more keys, only an action
            if mp.nil? or mp.empty?
              #puts "mp is nil or empty"
              return n.action
            end
            # we could have consumed keys at this point
            actions << n.action if n.action
            unconsumed.clear if n.action
            #e = window.getchar
            Ncurses::wtimeout(window.get_window, 500) # will wait a second on wgetch so we can get gg and qq
            e = window.getch
            Ncurses::nowtimeout(window.get_window, true)
            # e can return -1 if timedout
            $log.debug "  getch got #{e}"
          end
        end
      end

        def xxxbind_composite_mapping keycode, *args, &blk
          @_key_composite_map ||= {}
          str = ""
          keycode.each do |e| 
            s = key_tos(e)
            str << s
          end
          $log.debug "  composite map #{keycode} bound as #{str} "
          @_key_composite_map[str] = blk
        end

        # define a key with sub-keys to which commands are attached.
        # e.g. to attach commands to C-x a , C-x b, C-x x etc.
        #
        # == Example
        #
        # We create a map named :csmap and attach various commands to it
        # on different keys. At this point, there is no main key that triggers it.
        # Any key can be made the prefix command later. In this case, C-s was bound
        # to the map. This is more organized that creating separate maps for
        # C-s r, C-s s etc which then cannot be changed or customized by user.
        #
        #    @form.define_prefix_command :csmap, :scope => self
        #    @form.define_key(:csmap, "r", 'refresh', :refresh )
        #    @form.define_key(:csmap, "s", 'specification') { specification }
        #    @form.bind_key ?\C-s, :csmap
        #
        def define_prefix_command _name, config={} #_mapvar=nil, _prompt=nil
          $rb_prefix_map ||= {}
          _name = _name.to_sym unless _name.is_a? Symbol
          $rb_prefix_map[_name] ||= {}
          scope = config[:scope] || self
          $rb_prefix_map[_name][:scope] = scope


          # create a variable by name _name
          # create a method by same name to use
          # Don;t let this happen more than once
          instance_eval %{
        def #{_name.to_s} *args
          #$log.debug "XXX:  came inside #{_name} "
           h = $rb_prefix_map["#{_name}".to_sym]
           raise "No prefix_map named #{_name}, #{$rb_prefix_map.keys} " unless h
           ch = @window.getchar
           if ch
            if ch == KEY_F1
              text =  ["Options are: "]
              h.keys.each { |e| c = keycode_tos(e); text << c + " " + @descriptions[e]  }
              textdialog text, :title => "#{_name} key bindings"
              return
            end
              res =  h[ch]
              if res.is_a? Proc
                res.call
              elsif res.is_a? Symbol
                 scope = h[:scope]
                 scope.send(res)
              elsif res.nil?
                Ncurses.beep
                 return :UNHANDLED
              end
           else
                 :UNHANDLED
           end
        end
          }
          return _name
        end

        # Define a key for a prefix command.
        # @see +define_prefix_command+
        #
        # == Example: 
        #
        #    @form.define_key(:csmap, "s", 'specification') { specification }
        #    @form.define_key(:csmap, "r", 'refresh', :refresh )
        #
        # @param _symbol prefix command symbol (already created using +define_prefix_command+
        # @param keycode key within the prefix command for given block or action
        # @param args arguments to be passed to block. The first is a description.
        #             The second may be a symbol for a method to be executed (if block not given).
        # @param block action to be executed on pressing keycode
        def define_key _symbol, _keycode, *args, &blk
          #_symbol = @symbol
          h = $rb_prefix_map[_symbol]
          raise ArgumentError, "No such keymap #{_symbol} defined. Use define_prefix_command." unless h
          _keycode = _keycode[0].getbyte(0) if _keycode[0].class == String
          arg = args.shift
          if arg.is_a? String
            desc = arg
            arg = args.shift
          elsif arg.is_a? Symbol
            # its a symbol
            desc = arg.to_s
          elsif arg.nil?
            desc = "unknown"
          else
            raise ArgumentError, "Don't know how to handle #{arg.class} in PrefixManager"
          end
          # 2013-03-20 - 18:45 187compat gave error in 187 cannot convert string to int
          #@descriptions ||= []
          @descriptions ||= {}
          @descriptions[_keycode] = desc

          if !block_given?
            blk = arg
          end
          h[_keycode] = blk
        end
        # Display key bindings for current widget and form in dialog
        def print_key_bindings *args
          f  = get_current_field
          #labels = [@key_label, f.key_label]
          #labels = [@key_label]
          #labels << f.key_label if f.key_label
          labels = []
          labels << (f.key_label || {}) #if f.key_label
          labels << @key_label
          arr = []
          if get_current_field.help_text 
            arr << get_current_field.help_text 
          end
          labels.each_with_index { |h, i|  
            case i
            when 0
              arr << "  ===  Current widget bindings ==="
            when 1
              arr << "  === Form bindings ==="
            end

            h.each_pair { |name, val| 
              if name.is_a? Fixnum
                name = keycode_tos name
              elsif name.is_a? String
                name = keycode_tos(name.getbyte(0))
              elsif name.is_a? Array
                s = []
                name.each { |e|
                  s << keycode_tos(e.getbyte(0))
                }
                name = s
              else
                #$log.debug "XXX: KEY #{name} #{name.class} "
              end
              arr << " %-30s %s" % [name ,val]
              $log.debug "KEY: #{name} : #{val} "
            }
          }
          textdialog arr, :title => "Key Bindings"
        end
        def bind_keys keycodes, *args, &blk
          keycodes.each { |k| bind_key k, *args, &blk }
        end



        # This the new one which does not use orderedhash, it uses an array for multiple assignments
        # and falls back to a single assignment if multiple fails.
        # e.g. process_key ch, self
        # returns UNHANDLED if no block for it
        # after form handles basic keys, it gives unhandled key to current field, if current field returns
        # unhandled, then it checks this map.
        # added 2009-01-06 19:13 since widgets need to handle keys properly
        # added 2009-01-18 12:58 returns ret val of blk.call
        # so that if block does not handle, the key can still be handled
        # e.g. table last row, last col does not handle, so it will auto go to next field
        #  2010-02-24 13:45 handles 2 key combinations, copied from Form, must be identical in logic
        #  except maybe for window pointer. TODO not tested
        def _process_key keycode, object, window
          return :UNHANDLED if @_key_map.nil?
          chr = nil
          ch = keycode
          if ch > 0 and ch < 256
            chr = ch.chr
          end
          blk = @_key_map[keycode]
          # i am scrappaing this since i am once again complicating too much
=begin
          # if blk then we found an exact match which supercedes any ranges, arrays and regexes
          unless blk
            @_key_map.each_pair do |k,p|
              $log.debug "KKK:  processing key #{ch}  #{chr} "
              if (k == ch || k == chr)
                $log.debug "KKK:  checking match == #{k}: #{ch}  #{chr} "
                # compare both int key and chr
                $log.debug "KKK:  found match 1 #{ch}  #{chr} "
                #p.call(self, ch)
                #return 0
                blk = p
                break
              elsif k.respond_to? :include?
                $log.debug "KKK:  checking match include #{k}: #{ch}  #{chr} "
                # this bombs if its a String and we check for include of a ch.
                if !k.is_a?( String ) && (k.include?( ch ) || k.include?(chr))
                  $log.debug "KKK:  found match include #{ch}  #{chr} "
                  #p.call(self, ch)
                  #return 0
                  blk = p
                  break
                end
              elsif k.is_a? Regexp
                if k.match(chr)
                  $log.debug "KKK:  found match regex #{ch}  #{chr} "
                  #p.call(self, ch)
                  #return 0
                  blk = p
                  break
                end
              end
            end
          end
=end
          # blk either has a proc or is nil
          # we still need to check for a complex map.  if none, then execute simple map.
          ret = check_composite_mapping(ch, window)
          $log.debug "  composite returned #{ret} for #{ch} "
          if !ret
            return execute_mapping(blk, ch, object) if blk
          end
          return execute_mapping(ret, ch, object) if ret
          return :UNHANDLED
        end

    def execute_mapping blk, keycode, object

      if blk.is_a? Symbol
        if respond_to? blk
          return send(blk, *@_key_args[keycode])
        else
          ## 2013-03-05 - 19:50 why the hell is there an alert here, nowhere else
          alert "This ( #{self.class} ) does not respond to #{blk.to_s} [PROCESS-KEY]"
          # added 2013-03-05 - 19:50 so called can know
          return :UNHANDLED 
        end
      else
        $log.debug "rwidget BLOCK called _process_key #{keycode} " if $log.debug? 
        return blk.call object,  *@_key_args[keycode]
      end
    end

      # e.g. process_key ch, self
      # returns UNHANDLED if no block for it
      # after form handles basic keys, it gives unhandled key to current field, if current field returns
      # unhandled, then it checks this map.
      # added 2009-01-06 19:13 since widgets need to handle keys properly
      # added 2009-01-18 12:58 returns ret val of blk.call
      # so that if block does not handle, the key can still be handled
      # e.g. table last row, last col does not handle, so it will auto go to next field
      #  2010-02-24 13:45 handles 2 key combinations, copied from Form, must be identical in logic
      #  except maybe for window pointer. TODO not tested
      def ORIG_process_key keycode, object, window
        return :UNHANDLED if @_key_map.nil?
        blk = @_key_map[keycode]
        $log.debug "XXX:  _process key keycode #{keycode} #{blk.class}, #{self.class} "
        return :UNHANDLED if blk.nil?
        if blk.is_a? OrderedHash 
          #Ncurses::nodelay(window.get_window, bf = false)
          # if you set nodelay in ncurses.rb then this will not
          # wait for second key press, so you then must either make it blocking
          # here, or set a wtimeout here.
          #
          # This is since i have removed timeout globally since resize was happeing
          # after a keypress. maybe we can revert to timeout and not worry about resize so much
          Ncurses::wtimeout(window.get_window, 500) # will wait a second on wgetch so we can get gg and qq
          ch = window.getch
          # we should not reset here, resetting should happen in getch itself so it is consistent
          #Ncurses::nowtimeout(window.get_window, true)

          $log.debug " process_key: got #{keycode} , #{ch} "
          # next line ignores function keys etc. C-x F1, thus commented 255 2012-01-11 
          if ch < 0 #|| ch > 255
            return nil
          end
          #yn = ch.chr
          blk1 = blk[ch]
          # FIXME we are only returning the second key, what if form
          # has mapped first and second combo. We should unget keycode and ch. 2011-12-23 
          # check this out first.
          window.ungetch(ch) if blk1.nil? # trying  2011-09-27 
          return :UNHANDLED if blk1.nil? # changed nil to unhandled 2011-09-27 
          $log.debug " process_key: found block for #{keycode} , #{ch} "
          blk = blk1
        end
        if blk.is_a? Symbol
          if respond_to? blk
            return send(blk, *@_key_args[keycode])
          else
            ## 2013-03-05 - 19:50 why the hell is there an alert here, nowhere else
            alert "This ( #{self.class} ) does not respond to #{blk.to_s} [PROCESS-KEY]"
            # added 2013-03-05 - 19:50 so called can know
            return :UNHANDLED 
          end
        else
          $log.debug "rwidget BLOCK called _process_key " if $log.debug? 
          return blk.call object,  *@_key_args[keycode]
        end
        #0
      end
      # view a file or array of strings
      def view what, config={}, &block # :yields: textview for further configuration
        require 'canis/core/util/viewer'
        Canis::Viewer.view what, config, &block
      end
    end # module  }}}

    module EventHandler # {{{
      # widgets may register their events prior to calling super
      # 2014-04-17 - 20:54 Earlier they were writing directly to a data structure after +super+.
      #
      def register_events eves
        @_events ||= []
        case eves
        when Array
          @_events.push(*eves)
        when Symbol
          @_events << eves
        else
          raise ArgumentError "register_events: Don't know how to handle #{eves.class}"
        end
      end
      ##
      # bind an event to a block, optional args will also be passed when calling
      def bind event, *xargs, &blk
        #$log.debug "#{self} called EventHandler BIND #{event}, args:#{xargs} "
        if @_events
          $log.warn "bind: #{self.class} does not support this event: #{event}. #{@_events} " if !event? event
          #raise ArgumentError, "#{self.class} does not support this event: #{event}. #{@_events} " if !event? event
        else
          # it can come here if bind in initial block, since widgets add to @_event after calling super
          # maybe we can change that.
          $log.warn "BIND #{self.class} (#{event})  XXXXX no events defined in @_events. Please do so to avoid bugs and debugging. This will become a fatal error soon."
        end
        @handler ||= {}
        @event_args ||= {}
        @handler[event] ||= []
        @handler[event] << blk
        @event_args[event] ||= []
        @event_args[event] << xargs
      end
      alias :add_binding :bind   # temporary, needs a proper name to point out that we are adding

      # NOTE: Do we have a way of removing bindings
      # # TODO check if event is valid. Classes need to define what valid event names are

      ##
      # Fire all bindings for given event
      # e.g. fire_handler :ENTER, self
      # The first parameter passed to the calling block is either self, or some action event
      # The second and beyond are any objects you passed when using `bind` or `command`.
      # Exceptions are caught here itself, or else they prevent objects from updating, usually the error is 
      # in the block sent in by application, not our error.
      # TODO: if an object throws a subclass of VetoException we should not catch it and throw it back for 
      # caller to catch and take care of, such as prevent LEAVE or update etc.
      def fire_handler event, object
        $log.debug "inside def fire_handler evt:#{event}, o: #{object.class}"
        if !@handler.nil?
          if @_events
            raise ArgumentError, "fire_handler: #{self.class} does not support this event: #{event}. #{@_events} " if !event? event
          else
            $log.debug "bIND #{self.class}  XXXXX TEMPO no events defined in @_events "
          end
          ablk = @handler[event]
          if !ablk.nil?
            aeve = @event_args[event]
            ablk.each_with_index do |blk, ix|
              #$log.debug "#{self} called EventHandler firehander #{@name}, #{event}, obj: #{object},args: #{aeve[ix]}"
              $log.debug "#{self} called EventHandler firehander #{@name}, #{event}"
              begin
                blk.call object,  *aeve[ix]
              rescue FieldValidationException => fve
                # added 2011-09-26 1.3.0 so a user raised exception on LEAVE
                # keeps cursor in same field.
                raise fve
              rescue PropertyVetoException => pve
                # added 2011-09-26 1.3.0 so a user raised exception on LEAVE
                # keeps cursor in same field.
                raise pve
              rescue => ex
                ## some don't have name
                #$log.error "======= Error ERROR in block event #{self}: #{name}, #{event}"
                $log.error "======= Error ERROR in block event #{self}:  #{event}"
                $log.error ex
                $log.error(ex.backtrace.join("\n")) 
                #$error_message = "#{ex}" # changed 2010  
                $error_message.value = "#{ex.to_s}"
                Ncurses.beep
              end
            end
          else
            # there is no block for this key/event
            # we must behave exactly as processkey
            # NOTE this is too risky since then buttons and radio buttons
            # that don't have any command don;t update,so removing 2011-12-2 
            #return :UNHANDLED
            return :NO_BLOCK
          end # if
        else
          # there is no handler
          # I've done this since list traps ENTER but rarely uses it.
          # For buttons default, we'd like to trap ENTER even when focus is elsewhere
          # we must behave exactly as processkey
          # NOTE this is too risky since then buttons and radio buttons
          # that don't have any command don;t update,so removing 2011-12-2 
          #return :UNHANDLED
          # If caller wants, can return UNHANDLED such as list and ENTER.
          return :NO_BLOCK
        end # if
      end
      ## added on 2009-01-08 00:33 
      # goes with dsl_property
      # Need to inform listeners - done 2010-02-25 23:09 
      # Can throw a FieldValidationException or PropertyVetoException
      def fire_property_change text, oldvalue, newvalue
        return if oldvalue.nil? || @_object_created.nil? # added 2010-09-16 so if called by methods it is still effective
        $log.debug " FPC #{self}: #{text} #{oldvalue}, #{newvalue}"
        if @pce.nil?
          @pce = PropertyChangeEvent.new(self, text, oldvalue, newvalue)
        else
          @pce.set( self, text, oldvalue, newvalue)
        end
        fire_handler :PROPERTY_CHANGE, @pce
        @repaint_required = true # this was a hack and shoudl go, someone wanted to set this so it would repaint (viewport line 99 fire_prop
        repaint_all(true) # for repainting borders, headers etc 2011-09-28 V1.3.1 
      end

      # returns boolean depending on whether this widget has registered the given event
      def event? eve
        @_events.include? eve
      end

      # returns event list for this widget
      def event_list
        @_events
      end

    end # module eventh }}}

    module ConfigSetup # {{{
      # private
      # options passed in the constructor call the relevant methods declared in dsl_accessor or dsl_property
      def variable_set var, val
        send("#{var}", val) #rescue send("#{var}=", val) 
      end
      def config_setup aconfig
        @config = aconfig
        # this creates a problem in 1.9.2 since variable_set sets @config 2010-08-22 19:05 RK
        #@config.each_pair { |k,v| variable_set(k,v) }
        keys = @config.keys
        keys.each do |e| 
          variable_set(e, @config[e])
        end
      end
    end # module config }}}
    
    ##
    # Basic widget class superclass. Anything embedded in a form should
    # extend this, if it wants to be repainted or wants focus. Otherwise.
    # form will be unaware of it.
  
 
  class Widget   # {{{
    require 'canis/core/include/action'          # added 2012-01-3 for add_action
    include EventHandler
    include ConfigSetup
    include Canis::Utils
    include Io # added 2010-03-06 13:05 
    # common interface for text related to a field, label, textview, button etc
    dsl_property :text
    dsl_property :width, :height

    # foreground and background colors when focussed. Currently used with buttons and field
    # Form checks and repaints on entry if these are set.
    dsl_property :highlight_foreground, :highlight_background  # FIXME use color_pair

    # FIXME is enabled used? is menu using it
    #dsl_accessor :focusable, :enabled # boolean
    # This means someone can change label to focusable ! there should be someting like CAN_TAKE_FOCUS
    dsl_property :row, :col            # location of object
    #dsl_property :color, :bgcolor      # normal foreground and background
    dsl_writer :color, :bgcolor      # normal foreground and background
    # moved to a method which calculates color 2011-11-12 
    #dsl_property :color_pair           # instead of colors give just color_pair
    dsl_property :attr                 # attribute bold, normal, reverse
    dsl_accessor :name                 # name to refr to or recall object by_name
    attr_accessor :id #, :zorder
    attr_accessor :curpos              # cursor position inside object - column, not row.
    attr_reader  :config             # can be used for popping user objects too
    attr_accessor  :form              # made accessor 2008-11-27 22:32 so menu can set
    attr_accessor :state              # normal, selected, highlighted
    attr_reader  :row_offset, :col_offset # where should the cursor be placed to start with
    dsl_property :visible # boolean     # 2008-12-09 11:29 
    #attr_accessor :modified          # boolean, value modified or not (moved from field 2009-01-18 00:14 )
    dsl_accessor :help_text          # added 2009-01-22 17:41 can be used for status/tooltips


    attr_accessor  :_object_created   # 2010-09-16 12:12 to prevent needless property change firing when object being set
    
    attr_accessor :parent_component  # added 2010-01-12 23:28 BUFFERED - to bubble up

    # sometimes inside a container there's no way of knowing if an individual comp is in focus
    # other than to explicitly set it and inquire . 2010-09-02 14:47 @since 1.1.5
    # NOTE state takes care of this and is set by form. boolean
    attr_accessor :focussed  # is this widget in focus, so they may paint differently

    # height percent and width percent used in stacks and flows.
    dsl_accessor :height_pc, :width_pc # tryin out in stacks and flows 2011-11-23 

    # descriptions for each key set in _key_map
    attr_reader :key_label
    attr_reader :handler                       # event handler

    def initialize aform, aconfig={}, &block
      # I am trying to avoid passing the nil when you don't want to give a form.
      # I hope this does not create new issues 2011-11-20 
      if aform.is_a? Hash
        # presumable there's nothing coming in in hash, or else we will have to merge
        aconfig = aform
        @form = nil
      else
        #raise "got a #{aform.class} "
        @form = aform
      end
      @row_offset ||= 0
      @col_offset ||= 0
      #@ext_row_offset = @ext_col_offset = 0 # 2010-02-07 20:18  # removed on 2011-09-29 
      @state = :NORMAL
      #@attr = nil    # 2011-11-5 i could be removing what's been entered since super is called

      @handler = nil # we can avoid firing if nil
      #@event_args = {} # 2014-04-22 - 18:47 declared in bind_key
      # These are standard events for most widgets which will be fired by 
      # Form. In the case of CHANGED, form fires if it's editable property is set, so
      # it does not apply to all widgets.
      register_events( [:ENTER, :LEAVE, :CHANGED, :PROPERTY_CHANGE])

      config_setup aconfig # @config.each_pair { |k,v| variable_set(k,v) }
      #instance_eval &block if block_given?
      if block_given?
        if block.arity > 0
          yield self
        else
          self.instance_eval(&block)
        end
      end
      # 2010-09-20 13:12 moved down, so it does not create problems with other who want to set their
      # own default
      #@bgcolor ||=  "black" # 0
      #@color ||= "white" # $datacolor
      set_form(@form) if @form
    end
    def init_vars
      # just in case anyone does a super. Not putting anything here
      # since i don't want anyone accidentally overriding
    end
    # this is supposed to be a duplicate of what dsl_property generates for cases when
    #  we need to customise the get portion but not copy the set part. just call this.
    def property_set sym, val
      oldvalue = instance_variable_get "@#{sym}"
      tmp = val.size == 1 ? val[0] : val
      newvalue = tmp
      if oldvalue.nil? || @_object_created.nil?
        #@#{sym} = tmp
        instance_variable_set "@#{sym}", tmp
      end
      return(self) if oldvalue.nil? || @_object_created.nil?

      if oldvalue != newvalue
        # trying to reduce calls to fire, when object is being created
        begin
          @property_changed = true
          fire_property_change("#{sym}", oldvalue, newvalue) if !oldvalue.nil?
          #@#{sym} = tmp
          instance_variable_set "@#{sym}", tmp
          #@config["#{sym}"]=@#{sym}
        rescue PropertyVetoException
          $log.warn "PropertyVetoException for #{sym}:" + oldvalue.to_s + "->  "+ newvalue.to_s
        end
      end # if old
      self
    end 
    # returns widgets color, or if not set then app default
    # Ideally would have returned form's color, but it seems that form does not have color any longer.
    def color( *val )
      if val.empty?
        return @color if @color
        return @form.color if @form
        return $def_fg_color
      else
        @color_pair = nil
        return property_set :color, val
      end
    end
    # returns widgets bgcolor, or form's color. This ensures that all widgets use form's color
    #  unless user has overriden the color.
    # This is to be used whenever a widget is rendering to check the color at this moment.
    def bgcolor( *val )
      if val.empty?
        return @bgcolor if @bgcolor
        return @form.bgcolor if @form
        return $def_bg_color
      else
        @color_pair = nil
        return property_set :bgcolor, val
      end
    end


    # modified
    ##
    # typically read will be overridden to check if value changed from what it was on enter.
    # getter and setter for modified (added 2009-01-18 12:31 )
    def modified?
      @modified
    end
    def set_modified tf=true
      @modified = tf
      @form.modified = true if tf
    end
    alias :modified :set_modified

    ## got left out by mistake 2008-11-26 20:20 
    def on_enter
      @state = :HIGHLIGHTED    # duplicating since often these are inside containers
      @focussed = true
      if @handler && @handler.has_key?(:ENTER)
        fire_handler :ENTER, self
      end
    end
    ## got left out by mistake 2008-11-26 20:20 
    def on_leave
      @state = :NORMAL    # duplicating since often these are inside containers
      @focussed = false
      if @handler && @handler.has_key?(:LEAVE)
        fire_handler :LEAVE, self
      end
    end
    ## 
    # @return row and col of a widget where painting data actually starts
    # row and col is where a widget starts. offsets usually take into account borders.
    # the offsets typically are where the cursor should be positioned inside, upon on_enter.
    def rowcol
    # $log.debug "widgte rowcol : #{@row+@row_offset}, #{@col+@col_offset}"
      return @row+@row_offset, @col+@col_offset
    end
    ## return the value of the widget.
    #  In cases where selection is possible, should return selected value/s
    def getvalue
      #@text_variable && @text_variable.value || @text
      @text
    end
    ##
    # Am making a separate method since often value for print differs from actual value
    def getvalue_for_paint
      getvalue
    end
    ##
    # default repaint method. Called by form for all widgets.
    #  widget does not have display_length.
    def repaint
        r,c = rowcol
        @bgcolor ||= $def_bg_color # moved down 2011-11-5 
        @color   ||= $def_fg_color
        $log.debug("widget repaint : r:#{r} c:#{c} col:#{@color}" )
        value = getvalue_for_paint
        len = @width || value.length
        acolor = @color_pair || get_color($datacolor, @color, @bgcolor)
        @graphic.printstring r, c, "%-*s" % [len, value], acolor, @attr
        # next line should be in same color but only have @att so we can change att is nec
        #@form.window.mvchgat(y=r, x=c, max=len, Ncurses::A_NORMAL, @bgcolor, nil)
    end

    def destroy
      $log.debug "DESTROY : widget #{@name} "
      panel = @window.panel
      Ncurses::Panel.del_panel(panel.pointer) if !panel.nil?   
      @window.delwin if !@window.nil?
    end
    # in those cases where we create widget without a form, and later give it to 
    # some other program which sets the form. Dirty, we should perhaps create widgets
    # without forms, and add explicitly. 
    def set_form form
      raise "Form is nil in set_form" if form.nil?
      @form = form
      @id = form.add_widget(self) if !form.nil? and form.respond_to? :add_widget
      # 2009-10-29 15:04 use form.window, unless buffer created
      # should not use form.window so explicitly everywhere.
      # added 2009-12-27 20:05 BUFFERED in case child object needs a form.
      # We don;t wish to overwrite the graphic object
      if @graphic.nil?
        #$log.debug " setting graphic to form window for #{self.class}, #{form} "
        @graphic = form.window unless form.nil? # use screen for writing, not buffer
      end
      # execute those actions delayed due to absence of form -- used internally 
      # mostly by buttons and labels to bind hotkey to form
      fire_handler(:FORM_ATTACHED, self) if event? :FORM_ATTACHED
    end
    
    # puts cursor on correct row.
    def set_form_row
    #  @form.row = @row + 1 + @winrow
      #@form.row = @row + 1 
      r, c = rowcol
      $log.warn " empty set_form_row in widget #{self} r = #{r} , c = #{c}  "
      #raise "trying to set 0, maybe called repaint before container has set value" if row <= 0
      setrowcol row, nil
    end
    # set cursor on correct column, widget
    # Ideally, this should be overriden, as it is not likely to be correct.
    # NOTE: this is okay for some widgets but NOT for containers
    # that will call their own components SFR and SFC
    def set_form_col col1=@curpos
      @curpos = col1 || 0 # 2010-01-14 21:02 
      #@form.col = @col + @col_offset + @curpos
      c = @col + @col_offset + @curpos
      $log.warn " #{@name} empty set_form_col #{c}, curpos #{@curpos}  , #{@col} + #{@col_offset} #{@form} "
      setrowcol nil, c
    end
    def hide
      @visible = false
    end
    def show
      @visible = true
    end
    def remove
      @form.remove_widget(self)
    end
    # is this required can we remove
    def move row, col
      @row = row
      @col = col
    end
    ##
    # moves focus to this field
    # we must look into running on_leave of previous field
    def focus
      return if !@focusable
      if @form.validate_field != -1
        @form.select_field @id
      end
    end
    # set or unset focusable (boolean). Whether a widget can get keyboard focus.
    def focusable(*val)
      return @focusable if val.empty?
      oldv = @focusable
      @focusable = val[0]

      return self if oldv.nil? || @_object_created.nil?
      # once the form has been painted then any changes will trigger update of focusables.
      @form.update_focusables if @form
      # actually i should only set the forms focusable_modified flag rather than call this. FIXME
      self
    end

    # is this widget accessible from keyboard or not.
    def focusable?
      @focusable
    end
    ##
    # remove a binding that you don't want
    def unbind_key keycode
      @_key_args.delete keycode unless @_key_args.nil?
      @_key_map.delete keycode unless @_key_map.nil?
    end

    # e.g. process_key ch, self
    # returns UNHANDLED if no block for it
    # after form handles basic keys, it gives unhandled key to current field, if current field returns
    # unhandled, then it checks this map.
    def process_key keycode, object
      return _process_key keycode, object, @graphic
    end
    ## 
    # to be added at end of handle_key of widgets so instlalled actions can be checked
    def handle_key(ch)
      ret = process_key ch, self
      return :UNHANDLED if ret == :UNHANDLED
      0
    end



    # to give simple access to other components, (eg, parent) to tell a comp to either
    # paint its data, or to paint all - borders, headers, footers due to a big change (ht/width)
    def repaint_required(tf=true)
      @repaint_required = tf
    end
    def repaint_all(tf=true)
      @repaint_all = tf
      @repaint_required = tf
    end

     ## 
     # When an enclosing component creates a pad (buffer) and the child component
     #+ should write onto the same pad, then the enclosing component should override
     #+ the default graphic of child. This applies mainly to editor components in
     #+ listboxes and tables. 
     # @param graphic graphic object to use for writing contents
     # @see prepare_editor in rlistbox.
     # added 2010-01-05 15:25 
     def override_graphic gr
       @graphic = gr
     end

     ## passing a cursor up and adding col and row offsets
     ## Added 2010-01-13 13:27 I am checking this out.
     ## I would rather pass the value down and store it than do this recursive call
     ##+ for each cursor display
     # @see Form#setrowcol
     def setformrowcol r, c
           @form.row = r unless r.nil?
           @form.col = c unless c.nil?
           # this is stupid, going through this route i was losing windows top and left
           # And this could get repeated if there are mult objects. 
        if !@parent_component.nil? and @parent_component != self
           r+= @parent_component.form.window.top unless  r.nil?
           c+= @parent_component.form.window.left unless c.nil?
           $log.debug " (#{@name}) calling parents setformrowcol #{r}, #{c} pa: #{@parent_component.name} self: #{name}, #{self.class}, poff #{@parent_component.row_offset}, #{@parent_component.col_offset}, top:#{@form.window.left} left:#{@form.window.left} "
           @parent_component.setformrowcol r, c
        else
           # no more parents, now set form
           $log.debug " name NO MORE parents setting #{r}, #{c}    in #{@form} "
           @form.setrowcol r, c
        end
     end
     ## widget: i am putting one extra level of indirection so i can switch here
     # between form#setrowcol and setformrowcol, since i am not convinced either
     # are giving the accurate result. i am not sure what the issue is.
     def setrowcol r, c
         # 2010-02-07 21:32 is this where i should add ext_offsets
        #$log.debug " #{@name}  w.setrowcol #{r} + #{@ext_row_offset}, #{c} + #{@ext_col_offset}  "
        # commented off 2010-02-15 18:22 
        #r += @ext_row_offset unless r.nil?
        #c += @ext_col_offset unless c.nil?
        if @form
          @form.setrowcol r, c
        #elsif @parent_component
        else
          raise "Parent component not defined for #{self}, #{self.class} " unless @parent_component
          @parent_component.setrowcol r, c
        end
        #setformrowcol r,c 
     end

     # returns array of events defined for this object
     # @deprecated, should be in eventhandler
     #def event_list
       #return @_events if defined? @_events
       #nil
     #end

     # 2011-11-12 trying to make color setting a bit sane
     # You may set as a color_pair using get_color which gives a fixnum
     # or you may give 2 color symbols so i can update color, bgcolor and colorpair in one shot
     # if one of them is nil, i just use the existing value
     def color_pair(*val)
       if val.empty?
         return @color_pair
       end

       oldvalue = @color_pair
       case val.size
       when 1
         raise ArgumentError, "Expecting fixnum for color_pair." unless val[0].is_a? Fixnum
         @color_pair = val[0]
         @color, @bgcolor = ColorMap.get_colors_for_pair @color_pair
       when 2
         @color = val.first if val.first
         @bgcolor = val.last if val.last
         @color_pair = get_color $datacolor, @color, @bgcolor
       end
       if oldvalue != @color_pair
         fire_property_change(:color_pair, oldvalue, @color_pair)
         @property_changed = true
         repaint_all true
       end
       self
     end
     # a general method for all widgets to override with their favorite or most meaninful event
     # Ideally this is where the block in the constructor should land up.
     # @since 1.5.0    2011-11-21 
     def command *args, &block
       if event? :PRESS
         bind :PRESS, *args, &block
       else
         bind :CHANGED, *args, &block
       end
     end
     # return an object of actionmanager class, creating if required
     # Widgets and apps may add_action and show_menu using the same
     def action_manager
       require 'canis/core/include/actionmanager'
       @action_manager ||= ActionManager.new
     end
     #
    ## ADD HERE WIDGET
  end #  }}}

  ##
  #
  # TODO: we don't have an event for when form is entered and exited.
  class Form # {{{
    include EventHandler
    include Canis::Utils
    
    # array of widgets
    attr_reader :widgets
    
    # related window used for printing
    attr_accessor :window
    
    # cursor row and col
    attr_accessor :row, :col
    # color and bgcolor for all widget, widgets that don't have color specified will inherit from form
    # If not mentioned, then global defaults will be taken
    attr_writer :color, :bgcolor
    attr_accessor :attr
    
    # has the form been modified
    attr_accessor :modified

    # index of active widget
    attr_accessor :active_index
     
    # hash containing widgets by name for retrieval
    # Useful if one widget refers to second before second created.
    #     lb = @form.by_name["listb"]
    attr_reader :by_name   

    # associated menubar
    attr_reader :menu_bar

    # this influences whether navigation will return to first component after last or not
    # Default is :CYCLICAL which cycles between first and last. In some cases, where a form
    # or container exists inside a form with buttons or tabs, you may not want cyclical traversal.
    attr_accessor :navigation_policy  # :CYCLICAL will cycle around. Needed to move to other tabs

    # name given to form for debugging
    attr_accessor :name 

    # signify that the layout manager must calculate each widgets dimensions again since 
    # typically the window has been resized.
    attr_accessor :resize_required
    # class that lays out objects (calculates row, col, width and height)
    attr_accessor :layout_manager

    def initialize win, &block
      @window = win
      # added 2014-05-01 - 20:43 so that a window can update its form, during overlapping forms.
      @window.form = self if win
      @widgets = []
      @by_name = {}
      @active_index = -1
      @row = @col = -1
      @modified = false
      @resize_required = true
      @focusable = true
      # when widgets are added, add them here if focusable so traversal is easier. However,
      #  if user changes this during the app, we need to update this somehow. FIXME
      @focusables = [] # added 2014-04-24 - 12:28 to make traversal easier
      @navigation_policy ||= :CYCLICAL
      # 2014-04-24 - 17:42 NO MORE ENTER LEAVE at FORM LEVEL
      #register_events([:ENTER, :LEAVE, :RESIZE])
      register_events(:RESIZE)
      instance_eval &block if block_given?
      @_firsttime = true; # added on 2010-01-02 19:21 to prevent scrolling crash ! 
      @name ||= ""

      # related to emacs kill ring concept for copy-paste

      $kill_ring ||= [] # 2010-03-09 22:42 so textarea and others can copy and paste emacs EMACS
      $kill_ring_pointer = 0 # needs to be incremented with each append, moved with yank-pop
      $append_next_kill = false
      $kill_last_pop_size = 0 # size of last pop which has to be cleared

      $last_key = 0 # last key pressed @since 1.1.5 (not used yet)
      $current_key = 0 # curr key pressed @since 1.1.5 (so some containers can behave based on whether
                    # user tabbed in, or backtabbed in (rmultisplit)

      # for storing error message
      $error_message ||= Variable.new ""

      # what kind of key-bindings do you want, :vim or :emacs
      $key_map_type ||= :vim ## :emacs or :vim, keys to be defined accordingly. TODO

      bind_key(KEY_F1, 'help') { hm = help_manager(); hm.display_help }
    end
    ##
    # set this menubar as the form's menu bar.
    # also bind the toggle_key for popping up.
    # Should this not be at application level ?
    def set_menu_bar mb
      @menu_bar = mb
      add_widget mb
      mb.toggle_key ||= Ncurses.KEY_F2
      if !mb.toggle_key.nil?
        ch = mb.toggle_key
        bind_key(ch, 'Menu Bar') do |_form| 
          if !@menu_bar.nil?
            @menu_bar.toggle
            @menu_bar.handle_keys
          end
        end
      end
    end
    ##
    # Add given widget to widget list and returns an incremental id.
    # Adding to widgets, results in it being painted, and focussed.
    # removing a widget and adding can give the same ID's, however at this point we are not 
    # really using ID. But need to use an incremental int in future. (internal use)
    def add_widget widget
      # this help to access widget by a name
      if widget.respond_to? :name and !widget.name.nil?
        @by_name[widget.name] = widget
      end

      @widgets << widget
      @focusable_modified = true

      return @widgets.length-1
    end
    alias :add :add_widget

    # remove a widget
    # (internal use)
   def remove_widget widget
     if widget.respond_to? :name and !widget.name.nil?
       @by_name.delete(widget.name)
     end
     @focusable_modified = true
     @widgets.delete widget
   end

   # sets a flag that focusables should be updated
   # called whenever a widgets changes its focusable property
   def update_focusables
     $log.debug "XXX:  inside update focusables"
     @focusable_modified = true
   end

   private
   # does the actual job of updating the focusables array
   def _update_focusables  #:nodoc:
     @focusable_modified = false
     @focusables = @widgets.select { |w| w.focusable? }
   end

   public
     
   # form repaint,calls repaint on each widget which will repaint it only if it has been modified since last call.
   # called after each keypress.
    def repaint
      $log.debug " form repaint:#{self}, #{@name} , r #{@row} c #{@col} " if $log.debug? 
      if @resize_required && @layout_manager
        @layout_manager.form = self unless @layout_manager.form
        @layout_manager.do_layout
        @resize_required = false
      end
      @widgets.each do |f|
        next if f.visible == false # added 2008-12-09 12:17 
        #$log.debug "XXX: FORM CALLING REPAINT OF WIDGET #{f} IN LOOP"
        #raise "Row or col nil #{f.row} #{f.col} for #{f}, #{f.name} " if f.row.nil? || f.col.nil?
        f.repaint
        f._object_created = true # added 2010-09-16 13:02 now prop handlers can be fired
      end
      
      _update_focusables if @focusable_modified
      #  this can bomb if someone sets row. We need a better way!
      if @row == -1 and @_firsttime == true
   
        select_first_field
        @_firsttime = false
      end
       setpos 
       # XXX this creates a problem if window is a pad
       # although this does show cursor movement etc.
       ### @window.wrefresh
       if @window.window_type == :WINDOW
         #$log.debug " formrepaint #{@name} calling window.wrefresh #{@window} "
         @window.wrefresh
         Ncurses::Panel.update_panels ## added 2010-11-05 00:30 to see if clears the stdscr problems
       else
         $log.warn " XXX formrepaint #{@name} no refresh called  2011-09-19  #{@window} "
       end
    end
    ## 
    # move cursor to where the fields row and col are
    # private
    def setpos r=@row, c=@col
      #$log.debug "setpos : (#{self.name}) #{r} #{c} XXX"
      ## adding just in case things are going out of bounds of a parent and no cursor to be shown
      return if r.nil? or c.nil?  # added 2009-12-29 23:28 BUFFERED
      return if r<0 or c<0  # added 2010-01-02 18:49 stack too deep coming if goes above screen
      @window.wmove r,c
    end
    # @return [Widget, nil] current field, nil if no focusable field
    def get_current_field
      select_next_field if @active_index == -1
      return nil if @active_index.nil?   # for forms that have no focusable field 2009-01-08 12:22 
      @widgets[@active_index]
    end
    # take focus to first focussable field
    # we shoud not send to select_next. have a separate method to avoid bugs.
    # but check current_field, in case called from anotehr field TODO FIXME
    def select_first_field
      # this results in on_leave of last field being executed when form starts.
      #@active_index = -1 # FIXME HACK
      #select_next_field
      ix =  @focusables.first
      return unless ix # no focussable field

      # if the user is on a field other than current then fire on_leave
      if @active_index.nil? || @active_index < 0
      elsif @active_index != ix
        f = @widgets[@active_index]
        begin
          #$log.debug " select first field, calling on_leave of #{f} #{@active_index} "
          on_leave f
        rescue => err
         $log.error " Caught EXCEPTION select_first_field on_leave #{err}"
         Ncurses.beep
         #$error_message = "#{err}"
         $error_message.value = "#{err}"
         return
        end
      end
      select_field ix
    end

    # take focus to last field on form
    def select_last_field
      @active_index = nil 
      select_prev_field
    end


    ## do not override
    # form's trigger, fired when any widget loses focus
    #  This wont get called in editor components in tables, since  they are formless 
    def on_leave f
      return if f.nil? || !f.focusable # added focusable, else label was firing
      f.state = :NORMAL
      # on leaving update text_variable if defined. Should happen on modified only
      # should this not be f.text_var ... f.buffer ?  2008-11-25 18:58 
      #f.text_variable.value = f.buffer if !f.text_variable.nil? # 2008-12-20 23:36 
      f.on_leave if f.respond_to? :on_leave
      # 2014-04-24 - 17:42 NO MORE ENTER LEAVE at FORM LEVEL
      #fire_handler :LEAVE, f 
      ## to test XXX in combo boxes the box may not be editable by be modified by selection.
      if f.respond_to? :editable and f.modified?
        $log.debug " Form about to fire CHANGED for #{f} "
        f.fire_handler(:CHANGED, f) 
      end
    end
    # form calls on_enter of each object.
    # However, if a multicomponent calls on_enter of a widget, this code will
    # not be triggered. The highlighted part
    def on_enter f
      return if f.nil? || !f.focusable # added focusable, else label was firing 2010-09

      f.state = :HIGHLIGHTED
      # If the widget has a color defined for focussed, set repaint
      #  otherwise it will not be repainted unless user edits !
      if f.highlight_background || f.highlight_foreground
        f.repaint_required true
      end

      f.modified false
      #f.set_modified false
      f.on_enter if f.respond_to? :on_enter
      # 2014-04-24 - 17:42 NO MORE ENTER LEAVE at FORM LEVEL
      #fire_handler :ENTER, f 
    end

    ##
    # puts focus on the given field/widget index
    # @param index of field in @widgets (or can be a Widget too)
    # XXX if called externally will not run a on_leave of previous field
    def select_field ix0
      if ix0.is_a? Widget
        ix0 = @widgets.index(ix0)
      end
      return if @widgets.nil? or @widgets.empty?
     #$log.debug "inside select_field :  #{ix0} ai #{@active_index}" 
      f = @widgets[ix0]
      return if !f.focusable?
      if f.focusable?
        @active_index = ix0
        @row, @col = f.rowcol
        #$log.debug " WMOVE insdie sele nxt field : ROW #{@row} COL #{@col} " 
        on_enter f
        @window.wmove @row, @col # added RK FFI 2011-09-7 = setpos

        f.set_form_row # added 2011-10-5 so when embedded in another form it can get the cursor
        f.set_form_col # this can wreak havoc in containers, unless overridden

        # next line in field changes cursor position after setting form_col
        # resulting in a bug.  2011-11-25 
        # maybe it is in containers or tabbed panes and multi-containers
        # where previous objects col is still shown. we cannot do this after 
        # setformcol
        #f.curpos = 0 # why was this, okay is it because of prev obj's cursor ?
        repaint
        @window.refresh
      else
        $log.debug "inside select field ENABLED FALSE :   act #{@active_index} ix0 #{ix0}" 
      end
    end
    ##
    # run validate_field on a field, usually whatevers current
    # before transferring control
    # We should try to automate this so developer does not have to remember to call it.
    # # @param field object
    # @return [0, -1] for success or failure
    # NOTE : catches exception and sets $error_message, check if -1
    def validate_field f=@widgets[@active_index]
      begin
        on_leave f
      rescue => err
        $log.error "form: validate_field caught EXCEPTION #{err}"
        $log.error(err.backtrace.join("\n")) 
#        $error_message = "#{err}" # changed 2010  
        $error_message.value = "#{err}"
        Ncurses.beep
        return -1
      end
      return 0
    end
    # put focus on next field
    # will cycle by default, unless navigation policy not :CYCLICAL
    # in which case returns :NO_NEXT_FIELD.
    # FIXME: in the beginning it comes in as -1 and does an on_leave of last field
    def select_next_field
      return :UNHANDLED if @widgets.nil? || @widgets.empty?
      #$log.debug "insdie sele nxt field :  #{@active_index} WL:#{@widgets.length}" 
      if @active_index.nil?  || @active_index == -1 # needs to be tested out A LOT
        # what is this silly hack for still here 2014-04-24 - 13:04  DELETE FIXME
        @active_index = -1 
      else
        f = @widgets[@active_index]
        begin
          on_leave f
        rescue FieldValidationException => err # added 2011-10-2 v1.3.1 so we can rollback
          $log.error "select_next_field: caught EXCEPTION #{err}"
          $error_message.value = "#{err}"
          raise err
        rescue => err
         $log.error "select_next_field: caught EXCEPTION #{err}"
         $log.error(err.backtrace.join("\n")) 
#         $error_message = "#{err}" # changed 2010  
         $error_message.value = "#{err}"
         Ncurses.beep
         return 0
        end
      end
      f = @widgets[@active_index]
      index = @focusables.index(f)
      index += 1
      f = @focusables[index]
      if f
        select_field f 
        return 0
      end
      #
      #$log.debug "insdie sele nxt field FAILED:  #{@active_index} WL:#{@widgets.length}" 
      ## added on 2008-12-14 18:27 so we can skip to another form/tab
      if @navigation_policy == :CYCLICAL
        f = @focusables.first
        if f
          select_field f
          return 0
        end
      end
      $log.debug "inside sele nxt field : NO NEXT  #{@active_index} WL:#{@widgets.length}" 
      return :NO_NEXT_FIELD
    end
    ##
    # put focus on previous field
    # will cycle by default, unless navigation policy not :CYCLICAL
    # in which case returns :NO_PREV_FIELD.
    # @return [nil, :NO_PREV_FIELD] nil if cyclical and it finds a field
    #  if not cyclical, and no more fields then :NO_PREV_FIELD
    def select_prev_field
      return :UNHANDLED if @widgets.nil? or @widgets.empty?
      #$log.debug "insdie sele prev field :  #{@active_index} WL:#{@widgets.length}" 
      if @active_index.nil?
        @active_index = @widgets.length 
      else
        f = @widgets[@active_index]
        begin
          on_leave f
        rescue => err
         $log.error " Caught EXCEPTION #{err}"
         Ncurses.beep
#         $error_message = "#{err}" # changed 2010  
         $error_message.value = "#{err}"
         return
        end
      end

      f = @widgets[@active_index]
      index = @focusables.index(f)
      if index > 0
        index -= 1
        f = @focusables[index]
        if f
          select_field f
          return
        end
      end
      
      ## added on 2008-12-14 18:27 so we can skip to another form/tab
      # 2009-01-08 12:24 no recursion, can be stack overflows if no focusable field
      if @navigation_policy == :CYCLICAL
        f = @focusables.last
        select_field @widgets.index(f) if f
      end

      return :NO_PREV_FIELD
    end
    ##
    # move cursor by num columns. Form
    def addcol num
      return if @col.nil? || @col == -1
      @col += num
      @window.wmove @row, @col
      ## 2010-01-30 23:45 exchange calling parent with calling this forms setrow
      # since in tabbedpane with table i am not gietting this forms offset. 
      setrowcol nil, col
    end
    ##
    # move cursor by given rows and columns, can be negative.
    # 2010-01-30 23:47 FIXME, if this is called we should call setrowcol like in addcol
    def addrowcol row,col
      return if @col.nil? or @col == -1   # contradicts comment on top
      return if @row.nil? or @row == -1
      @col += col
      @row += row
      @window.wmove @row, @col
    
    end

    ## Form
    # New attempt at setting cursor using absolute coordinates
    # Also, trying NOT to go up. let this pad or window print cursor.
    def setrowcol r, c
      @row = r unless r.nil?
      @col = c unless c.nil?
    end
  ##

  # e.g. process_key ch, self
  # returns UNHANDLED if no block for it
  # after form handles basic keys, it gives unhandled key to current field, if current field returns
  # unhandled, then it checks this map.
  # Please update widget with any changes here. TODO: match regexes as in mapper

  def process_key keycode, object
    return _process_key keycode, object, @window
  end

  # Defines how user can give numeric args to a command even in edit mode
  # User either presses universal_argument (C-u) which generates a series of 4 16 64.
  # Or he presses C-u and then types some numbers. Followed by the action.
  # @returns [0, :UNHANDLED] :UNHANDLED implies that last keystroke is still to evaluated
  # by system. ) implies only numeric args were obtained. This method updates $multiplier

  def universal_argument
    $multiplier = ( ($multiplier.nil? || $multiplier == 0) ? 4 : $multiplier *= 4)
        $log.debug " inside UNIV MULT0: #{$multiplier} "
    # See if user enters numerics. If so discard existing varaible and take only 
    #+ entered values
    _m = 0
    while true
      ch = @window.getchar()
      case ch
      when -1
        next 
      when ?0.getbyte(0)..?9.getbyte(0)
        _m *= 10 ; _m += (ch-48)
        $multiplier = _m
        $log.debug " inside UNIV MULT #{$multiplier} "
      when ?\C-u.getbyte(0)
        if _m == 0
          # user is incrementally hitting C-u
          $multiplier *= 4
        else
          # user is terminating some numbers so he can enter a numeric command next
          return 0
        end
      else
        $log.debug " inside UNIV MULT else got #{ch} "
        # here is some other key that is the function key to be repeated. we must honor this
        # and ensure it goes to the right widget
        return ch
        #return :UNHANDLED
      end
    end
    return 0
  end

  def digit_argument ch
    $multiplier = ch - ?\M-0.getbyte(0)
    $log.debug " inside UNIV MULT 0 #{$multiplier} "
    # See if user enters numerics. If so discard existing varaible and take only 
    #+ entered values
    _m = $multiplier
    while true
      ch = @window.getchar()
      case ch
      when -1
        next 
      when ?0.getbyte(0)..?9.getbyte(0)
        _m *= 10 ; _m += (ch-48)
        $multiplier = _m
        $log.debug " inside UNIV MULT 1 #{$multiplier} "
      when ?\M-0.getbyte(0)..?\M-9.getbyte(0)
        _m *= 10 ; _m += (ch-?\M-0.getbyte(0))
        $multiplier = _m
        $log.debug " inside UNIV MULT 2 #{$multiplier} "
      else
        $log.debug " inside UNIV MULT else got #{ch} "
        # here is some other key that is the function key to be repeated. we must honor this
        # and ensure it goes to the right widget
        return ch
        #return :UNHANDLED
      end
    end
    return 0
  end
  #
  # These mappings will only trigger if the current field
  #  does not use them.
  #
  def map_keys
    return if @keys_mapped
    bind_keys([?\M-?,?\?], 'show field help') { 
      #if get_current_field.help_text 
        #textdialog(get_current_field.help_text, 'title' => 'Help Text', :bgcolor => 'green', :color => :white) 
      #else
        print_key_bindings
      #end
    }
    bind_key(FFI::NCurses::KEY_F9, "Print keys", :print_key_bindings) # show bindings, tentative on F9
    bind_key(?\M-:, 'show menu') {
      fld = get_current_field
      am = fld.action_manager()
      #fld.init_menu
      am.show_actions
    }
    @keys_mapped = true
  end

  # this forces a repaint of all visible widgets and has been added for the case of overlapping
  # windows, since a black rectangle is often left when a window is destroyed. This is internally
  # triggered whenever a window is destroyed, and currently only for root window.
  def repaint_all_widgets
    $log.debug "  REPAINT ALL in FORM called "
    @widgets.each do |w|
      next if w.visible == false
      next if w.class.to_s == "Canis::MenuBar"
      $log.debug "   ---- REPAINT ALL #{w.name} "
      w.repaint_required true
      w.repaint
    end
    $log.debug "  REPAINT ALL in FORM complete "
    #  place cursor on current_widget 
    setpos
  end
  
  ## forms handle keys
  # mainly traps tab and backtab to navigate between widgets.
  # I know some widgets will want to use tab, e.g edit boxes for entering a tab
  #  or for completion.
  # @throws FieldValidationException
  # NOTE : please rescue exceptions when you use this in your main loop and alert() user
  #
  def handle_key(ch)
    map_keys unless @keys_mapped
    handled = :UNHANDLED # 2011-10-4 
        if ch ==  ?\C-u.getbyte(0)
          ret = universal_argument
          $log.debug "C-u FORM set MULT to #{$multiplier}, ret = #{ret}  "
          return 0 if ret == 0
          ch = ret # unhandled char
        elsif ch >= ?\M-1.getbyte(0) && ch <= ?\M-9.getbyte(0)
          if $catch_alt_digits # emacs EMACS
            ret = digit_argument ch
            $log.debug " FORM set MULT DA to #{$multiplier}, ret = #{ret}  "
            return 0 if ret == 0 # don't see this happening
            ch = ret # unhandled char
          end
        end

        $current_key = ch
        case ch
        when -1
          return
        when 1000
          $log.debug " form RESIZE HK #{ch} #{self}, #{@name} "
          repaint_all_widgets
          return
        #when Ncurses::KEY_RESIZE # SIGWINCH
        when FFI::NCurses::KEY_RESIZE # SIGWINCH #  FFI
          lines = Ncurses.LINES
          cols = Ncurses.COLS
          x = Ncurses.stdscr.getmaxy
          y = Ncurses.stdscr.getmaxx
          $log.debug " form RESIZE HK #{ch} #{self}, #{@name}, #{ch}, x #{x} y #{y}  lines #{lines} , cols: #{cols} "
          #alert "SIGWINCH WE NEED TO RECALC AND REPAINT resize #{lines}, #{cols}: #{x}, #{y} "

          # next line may be causing flicker, can we do without.
          Ncurses.endwin
          @window.wrefresh
          @window.wclear
          if @layout_manager
            @layout_manager.do_layout
            # we need to redo statusline and others that layout ignores
          else
            @widgets.each { |e| e.repaint_all(true) } # trying out
          end
          ## added RESIZE on 2012-01-5 
          ## stuff that relies on last line such as statusline dock etc will need to be redrawn.
          fire_handler :RESIZE, self 
        else
          field =  get_current_field
          if $log.debug?
            keycode = keycode_tos(ch)
            $log.debug " form HK #{ch} #{self}, #{@name}, #{keycode}, field: giving to: #{field}, #{field.name}  " if field
          end
          handled = :UNHANDLED 
          handled = field.handle_key ch unless field.nil? # no field focussable
          $log.debug "handled inside Form #{ch} from #{field} got #{handled}  "
          # some widgets like textarea and list handle up and down
          if handled == :UNHANDLED or handled == -1 or field.nil?
            case ch
            when KEY_TAB, ?\M-\C-i.getbyte(0)  # tab and M-tab in case widget eats tab (such as Table)
              ret = select_next_field
              return ret if ret == :NO_NEXT_FIELD
              # alt-shift-tab  or backtab (in case Table eats backtab)
            when FFI::NCurses::KEY_BTAB, 481 ## backtab added 2008-12-14 18:41 
              ret = select_prev_field
              return ret if ret == :NO_PREV_FIELD
            when FFI::NCurses::KEY_UP
              ret = select_prev_field
              return ret if ret == :NO_PREV_FIELD
            when FFI::NCurses::KEY_DOWN
              ret = select_next_field
              return ret if ret == :NO_NEXT_FIELD
            else
              #$log.debug " before calling process_key in form #{ch}  " if $log.debug? 
              ret = process_key ch, self
              $log.debug "FORM process_key #{ch} got ret #{ret} in #{self} "
              return :UNHANDLED if ret == :UNHANDLED
            end
          elsif handled == :NO_NEXT_FIELD || handled == :NO_PREV_FIELD # 2011-10-4 
            return handled
          end
        end
       $log.debug " form before repaint #{self} , #{@name}, ret #{ret}"
       repaint
       $last_key = ch
       ret || 0  # 2011-10-17 
  end

  # 2010-02-07 14:50 to aid in debugging and comparing log files.
  def to_s; @name || self; end

  #
  # returns in instance of help_manager with which one may install help_text and call help.
  # user apps will only supply help_text, form would already have mapped F1 to help.
  def help_manager
    @help_manager ||= HelpManager.new self
  end
  # returns forms color, or if not set then app default
  # This is used by widget's as the color to fallback on when no color is specified for them.
  # This way all widgets in a form can have one color.
  def color
    @color || $def_fg_color
  end
  # returns form's bgcolor, or global default.
  def bgcolor
    @bgcolor || $def_bg_color
  end

    ## ADD HERE FORM
  end # }}}


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
      _layout = [ h, sc, sh - h, 0]
      Canis::Viewer.view(arr, :layout => _layout, :close_key => KEY_F10, :title => "[ Help ]", :print_footer => true,
                        :app_header => true ) do |t|
        # would have liked it to be 'md' or :help
        t.content_type = :tmux
        t.stylesheet   = stylesheet
        t.suppress_borders = true
        t.print_footer = false
        t.bgcolor = :black
        t.bgcolor = 16
        t.color = :white
        #t.text_patterns[:link] = Regexp.new(/\[[^\]]\]/)
        t.text_patterns[:link] = Regexp.new(/\[\w+\]/)
        t.bind_key(KEY_TAB, "goto link") { t.next_regex(:link) }
        # FIXME bgcolor add only works if numberm not symbol
        t.bind_key(?a, "goto link") { t.bgcolor += 1 ; t.bgcolor = 1 if t.bgcolor > 256; 
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
              t.add_content arr, :title => link
              t.buffer_last
            else
              alert "No help file for #{link}"
            end
          else
          end
        }

        # help was provided, so default help is provided in second buffer
        unless defhelp
          t.add_content defarr, :title => ' General Help ', :stylesheet => stylesheet, :content_type => :tmux
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
  ## Created and sent to all listeners whenever a property is changed
  # @see fire_property_change
  # @see fire_handler 
  # @since 1.0.5 added 2010-02-25 23:06 
  class PropertyChangeEvent # {{{
    attr_accessor :source, :property_name, :oldvalue, :newvalue
    def initialize source, property_name, oldvalue, newvalue
      set source, property_name, oldvalue, newvalue
    end
    def set source, property_name, oldvalue, newvalue
        @source, @property_name, @oldvalue, @newvalue =
        source, property_name, oldvalue, newvalue
    end
    def to_s
      "PROPERTY_CHANGE name: #{property_name}, oldval: #{@oldvalue}, newvalue: #{@newvalue}, source: #{@source}"
    end
    def inspect
      to_s
    end
  end # }}}

  ##
  # Text edit field
  # NOTE: +width+ is the length of the display whereas +maxlen+ is the maximum size that the value 
  # can take. Thus, +maxlen+ can exceed +width+. Currently, +maxlen+ defaults to +width+ which 
  # defaults to 20.
  # NOTE: Use +text(val)+ to set value, and +text()+ to retrieve value
  # == Example
  #     f = Field.new @form, text: "Some value", row: 10, col: 2
  #
  # Field introduces an event :CHANGE which is fired for each character deleted or inserted
  # TODO: some methods should return self, so chaining can be done. Not sure if the return value of the 
  #   fire_handler is being checked.
  #   NOTE: i have just added repain_required check in Field before repaint
  #   this may mean in some places field does not paint. repaint_require will have to be set
  #   to true in those cases. this was since field was overriding a popup window that was not modal.
  #  
  class Field < Widget # {{{
    dsl_accessor :maxlen             # maximum length allowed into field
    attr_reader :buffer              # actual buffer being used for storage
    #
    # Unlike `set_label` which creates a separate +Label+
    # object, this stores a +String+ and prints it before the string. This is less
    # customizable, however, in some cases when a field is attached to some container
    # the label gets left out. This label is gauranteed to print to the left of the field
    # This label prints on +row+ and +col+ and the +Field+ after one space, so to align multiple
    # fields and labels, pad the label appropriately to the longest label.
    # 
    dsl_accessor :label              # label of field  
    dsl_property :label_color_pair   # label of field  Unused earlier, now will print 
    dsl_property :label_attr   # label of field  Unused earlier, now will print 
  
    dsl_accessor :values             # validate against provided list, (+include?+)
    dsl_accessor :valid_regex        # validate against regular expression (+match()+)
    dsl_accessor :valid_range        # validate against numeric range, should respond to +include?+
    # for numeric fields, specify lower or upper limit of entered value
    attr_accessor :below, :above

    dsl_accessor :chars_allowed           # regex, what characters to allow entry, will ignore all else
    # character to show, earlier called +show+ which clashed with Widget method +show+
    dsl_accessor :mask                    # what charactr to show for each char entered (password field)
    dsl_accessor :null_allowed            # allow nulls, don't validate if null # added , boolean

    # any new widget that has editable should have modified also
    dsl_accessor :editable          # allow editing

    # +type+ is just a convenience over +chars_allowed+ and sets some basic filters 
    # @example:  :integer, :float, :alpha, :alnum
    # NOTE: we do not store type, only chars_allowed, so this won't return any value
    attr_reader :type                          # datatype of field, currently only sets chars_allowed
    # this is the class of the field set in +text()+, so value is returned in same class
    # @example : Fixnum, Integer, Float
    attr_accessor :datatype                    # crrently set during set_buffer
    attr_reader :original_value                # value on entering field
    attr_accessor :overwrite_mode              # true or false INSERT OVERWRITE MODE

    # column on which field printed, usually the same as +col+ unless +label+ used.
    # Required by +History+ to popup field history.
    attr_reader :field_col                     # column on which field is printed
                                               # required due to labels. Is updated after printing
    #                                          # so can be nil if accessed early 2011-12-8 

    def initialize form=nil, config={}, &block
      @form = form
      @buffer = String.new
      #@type=config.fetch("type", :varchar)
      @row = 0
      @col = 0
      #@bgcolor = $def_bg_color
      #@color = $def_fg_color
      @editable = true
      @focusable = true
      #@event_args = {}             # arguments passed at time of binding, to use when firing event
      map_keys 
      init_vars
      register_events(:CHANGE)
      super
      @width ||= 20
      @maxlen ||= @width
    end
    def init_vars
      @pcol = 0                    # needed for horiz scrolling
      @curpos = 0                  # current cursor position in buffer
                                   # this is the index where characters are put or deleted
      #                            # when user edits
      @modified = false
      @repaint_required = true
    end

    # define a datatype, sets +chars_allowed+ with some predefined regex
    # integer and float. what about allowing a minus sign? 
    # These are pretty restrictive, so if you need an open field, use +chars_allowed+
    # @param symbol :integer, :float, :alpha, :alnum
    # NOTE: there is some confusion and duplication between chars_allowed, type and datatype.
    #    +datatype+ is set by set_buffer and can be set manually and decides return type.
    #    +type+ is merely a convenience over chars_allowed
    def type dtype
      return self if @chars_allowed # disallow changing
      dtype = dtype.to_s.downcase.to_sym if dtype.is_a? String
      case dtype # missing to_sym would have always failed due to to_s 2011-09-30 1.3.1
      when :integer, Fixnum, Integer
        @chars_allowed = /\d/
      when :numeric, :float, Numeric, Float
        @chars_allowed = /[\d\.]/ 
      when :alpha
        @chars_allowed = /[a-zA-Z]/ 
      when :alnum
        @chars_allowed = /[a-zA-Z0-9]/ 
      else
        raise ArgumentError, "Field type: invalid datatype specified. Use :integer, :numeric, :float, :alpha, :alnum "
      end
      self
    end

    #
    # add a char to field, and validate
    # NOTE: this should return self for chaining operations and throw an exception
    # if disabled or exceeding size
    # @param [char] a character to add
    # @return [Fixnum] 0 if okay, -1 if not editable or exceeding length
    def putch char
      return -1 if !@editable 
      return -1 if !@overwrite_mode && (@buffer.length >= @maxlen)
      blen = @buffer.length
      if @chars_allowed != nil
        return if char.match(@chars_allowed).nil?
      end
      # added insert or overwrite mode 2010-03-17 20:11 
      oldchar = nil
      if @overwrite_mode
        oldchar = @buffer[@curpos] 
        @buffer[@curpos] = char
      else
        @buffer.insert(@curpos, char)
      end
      oldcurpos = @curpos
      #$log.warn "XXX:  FIELD CURPOS #{@curpos} blen #{@buffer.length} " #if @curpos > blen
      @curpos += 1 if @curpos < @maxlen
      @modified = true
      #$log.debug " FIELD FIRING CHANGE: #{char} at new #{@curpos}: bl:#{@buffer.length} buff:[#{@buffer}]"
      # i have no way of knowing what change happened and what char was added deleted or changed
      #fire_handler :CHANGE, self    # 2008-12-09 14:51 
      if @overwrite_mode
        fire_handler :CHANGE, InputDataEvent.new(oldcurpos,@curpos, self, :DELETE, 0, oldchar) # 2010-09-11 12:43 
      end
      fire_handler :CHANGE, InputDataEvent.new(oldcurpos,@curpos, self, :INSERT, 0, char) # 2010-09-11 12:43 
      0
    end

    ##
    # TODO : sending c>=0 allows control chars to go. Should be >= ?A i think.
    def putc c
      if c >= 0 and c <= 127
        ret = putch c.chr
        if ret == 0
          if addcol(1) == -1  # if can't go forward, try scrolling
            # scroll if exceeding display len but less than max len
            if @curpos > @width && @curpos <= @maxlen
              @pcol += 1 if @pcol < @width 
            end
          end
          set_modified 
          return 0 # 2010-09-11 12:59 else would always return -1
        end
      end
      return -1
    end
    def delete_at index=@curpos
      return -1 if !@editable 
      char = @buffer.slice!(index,1)
      #$log.debug " delete at #{index}: #{@buffer.length}: #{@buffer}"
      @modified = true
      #fire_handler :CHANGE, self    # 2008-12-09 14:51 
      fire_handler :CHANGE, InputDataEvent.new(@curpos,@curpos, self, :DELETE, 0, char)     # 2010-09-11 13:01 
    end
    #
    # silently restores value without firing handlers, use if exception and you want old value
    # @since 1.4.0 2011-10-2 
    def restore_original_value
      @buffer = @original_value.dup
      # earlier commented but trying again, since i am getting IndexError in insert 2188
      # Added next 3 lines to fix issue, now it comes back to beginning. FIX IN RBC
      cursor_home

      @repaint_required = true
    end
    ## 
    # set value of Field
    # fires CHANGE handler
    # Please don't use this directly, use +text+
    # This name is from ncurses field, added underscore to emphasize not to use
    def _set_buffer value   #:nodoc:
      @repaint_required = true
      @datatype = value.class
      @delete_buffer = @buffer.dup
      @buffer = value.to_s.dup
      # don't allow setting of value greater than maxlen
      @buffer = @buffer[0,@maxlen] if @maxlen && @buffer.length > @maxlen
      @curpos = 0
      # hope @delete_buffer is not overwritten
      fire_handler :CHANGE, InputDataEvent.new(@curpos,@curpos, self, :DELETE, 0, @delete_buffer)     # 2010-09-11 13:01 
      fire_handler :CHANGE, InputDataEvent.new(@curpos,@curpos, self, :INSERT, 0, @buffer)     # 2010-09-11 13:01 
      self # 2011-10-2 
    end
    # converts back into original type
    #  changed to convert on 2009-01-06 23:39 
    def getvalue
      dt = @datatype || String
      case dt.to_s
      when "String"
        return @buffer
      when "Fixnum"
        return @buffer.to_i
      when "Float"
        return @buffer.to_f
      else
        return @buffer.to_s
      end
    end
  
    # create a label linked to this field
    # Typically one passes a Label, but now we can pass just a String, a label 
    # is created. This differs from +label+ in positioning. The +Field+ is printed on 
    # +row+ and +col+ and the label before it. Thus, all fields are aligned on column,
    # however you must leave adequate columns for the label to be printed to the left of the field.
    #
    # NOTE: 2011-10-20 when field attached to some container, label won't be attached
    # In such cases, use just +label()+ not +set_label()+.
    # @param [Label, String] label object to be associated with this field
    # @return label created which can be further customized.
    # FIXME this may not work since i have disabled -1, now i do not set row and col 2011-11-5 
    def set_label label
      # added case for user just using a string
      case label
      when String
        # what if no form at this point
        @label_unattached = true unless @form
        label = Label.new @form, {:text => label}
      end
      @label = label
      # in the case of app it won't be set yet FIXME
      # So app sets label to 0 and t his won't trigger
      # can this be delayed to when paint happens XXX
      if @row
        position_label
      else
        @label_unplaced = true
      end
      label
    end
    # FIXME this may not work since i have disabled -1, now i do not set row and col
    def position_label
      $log.debug "XXX: LABEL row #{@label.row}, #{@label.col} "
      @label.row  @row unless @label.row #if @label.row == -1
      @label.col  @col-(@label.name.length+1) unless @label.col #if @label.col == -1
      @label.label_for(self) # this line got deleted when we redid stuff !
      $log.debug "   XXX: LABEL row #{@label.row}, #{@label.col} "
    end

  ## Note that some older widgets like Field repaint every time the form.repaint
  ##+ is called, whether updated or not. I can't remember why this is, but
  ##+ currently I've not implemented events with these widgets. 2010-01-03 15:00 

  def repaint
    return unless @repaint_required  # 2010-11-20 13:13 its writing over a window i think TESTING
    if @label_unattached
      alert "came here unattachd"
      @label.set_form(@form)
      @label_unattached = nil
    end
    if @label_unplaced
      alert "came here unplaced"
      position_label
      @label_unplaced = nil
    end
    @bgcolor ||= $def_bg_color
    @color   ||= $def_fg_color
    $log.debug("repaint FIELD: #{id}, #{name}, #{row} #{col},pcol:#{@pcol},  #{focusable} st: #{@state} ")
    @width = 1 if width == 0
    printval = getvalue_for_paint().to_s # added 2009-01-06 23:27 
    printval = mask()*printval.length unless @mask.nil?
    if !printval.nil? 
      if printval.length > width # only show maxlen
        printval = printval[@pcol..@pcol+width-1] 
      else
        printval = printval[@pcol..-1]
      end
    end
  
    acolor = @color_pair || get_color($datacolor, @color, @bgcolor)
    if @state == :HIGHLIGHTED
      _bgcolor = @highlight_background || @bgcolor
      _color = @highlight_foreground || @color
      acolor = get_color(acolor, _color, _bgcolor)
    end
    @graphic = @form.window if @graphic.nil? ## cell editor listbox hack 
    #$log.debug " Field g:#{@graphic}. r,c,displen:#{@row}, #{@col}, #{@width} c:#{@color} bg:#{@bgcolor} a:#{@attr} :#{@name} "
    r = row
    c = col
    if label.is_a? String
      lcolor = @label_color_pair || $datacolor # this should be the same color as window bg XXX
      lattr = @label_attr || NORMAL
      @graphic.printstring row, col, label, lcolor, lattr
      c += label.length + 2
      @col_offset = c-@col            # required so cursor lands in right place
    end
    @graphic.printstring r, c, sprintf("%-*s", width, printval), acolor, @attr
    @field_col = c
    @repaint_required = false
  end

  # deprecated
  # set or unset focusable 
  def set_focusable(tf)
    $log.warn "pls don't use, deprecated. use focusable(boolean)"
    focusable tf
  end
 

  def map_keys
    return if @keys_mapped
    bind_key(FFI::NCurses::KEY_LEFT, :cursor_backward )
    bind_key(FFI::NCurses::KEY_RIGHT, :cursor_forward )
    bind_key(FFI::NCurses::KEY_BACKSPACE, :delete_prev_char )
    bind_key(127, :delete_prev_char )
    bind_key(330, :delete_curr_char )
    bind_key(?\C-a, :cursor_home )
    bind_key(?\C-e, :cursor_end )
    bind_key(?\C-k, :delete_eol )
    bind_key(?\C-_, :undo_delete_eol )
    #bind_key(27){ text @original_value }
    bind_key(?\C-g, 'revert'){ text @original_value } # 2011-09-29 V1.3.1 ESC did not work
    @keys_mapped = true
  end

  # field
  # 
  def handle_key ch
    @repaint_required = true 
    #map_keys unless @keys_mapped # moved to init
    case ch
    when 32..126
      #$log.debug("FIELD: ch #{ch} ,at #{@curpos}, buffer:[#{@buffer}] bl: #{@buffer.to_s.length}")
      putc ch
    when 27 # cannot bind it
      #text @original_value 
      # commented above and changed 2014-05-12 - 20:05 I think above creates positioning issues. TEST XXX
      restore_original_value
    else
      ret = super
      return ret
    end
    0 # 2008-12-16 23:05 without this -1 was going back so no repaint
  end
  # does an undo on delete_eol, not a real undo
  def undo_delete_eol
    return if @delete_buffer.nil?
    #oldvalue = @buffer
    @buffer.insert @curpos, @delete_buffer 
    fire_handler :CHANGE, InputDataEvent.new(@curpos,@curpos+@delete_buffer.length, self, :INSERT, 0, @delete_buffer)     # 2010-09-11 13:01 
  end
  ## 
  # position cursor at start of field
  def cursor_home
    @curpos = 0
    @pcol = 0
    set_form_col 0
  end
  ##
  # goto end of field, "end" is a keyword so could not use it.
  def cursor_end
    blen = @buffer.rstrip.length
    if blen < @width
      set_form_col blen
    else
      # there is a problem here FIXME. 
      @pcol = blen-@width
      #set_form_col @width-1
      set_form_col blen
    end
    @curpos = blen # this is position in array where editing or motion is to happen regardless of what you see
                   # regardless of pcol (panning)
    #  $log.debug " crusor END cp:#{@curpos} pcol:#{@pcol} b.l:#{@buffer.length} d_l:#{@width} fc:#{@form.col}"
    #set_form_col @buffer.length
  end
  # sets the visual cursor on the window at correct place
  # added here since we need to account for pcol. 2011-12-7 
  # NOTE be careful of curpos - pcol being less than 0
  def set_form_col col1=@curpos
    @curpos = col1 || 0 # NOTE we set the index of cursor here
    c = @col + @col_offset + @curpos - @pcol
    min = @col + @col_offset
    max = min + @width
    c = min if c < min
    c = max if c > max
    $log.debug " #{@name} FIELD set_form_col #{c}, curpos #{@curpos}  , #{@col} + #{@col_offset} pcol:#{@pcol} "
    setrowcol nil, c
  end
  def delete_eol
    return -1 unless @editable
    pos = @curpos-1
    @delete_buffer = @buffer[@curpos..-1]
    # if pos is 0, pos-1 becomes -1, end of line!
    @buffer = pos == -1 ? "" : @buffer[0..pos]
    fire_handler :CHANGE, InputDataEvent.new(@curpos,@curpos+@delete_buffer.length, self, :DELETE, 0, @delete_buffer)
    return @delete_buffer
  end
  def cursor_forward
    if @curpos < @buffer.length 
      if addcol(1)==-1  # go forward if you can, else scroll
        @pcol += 1 if @pcol < @width 
      end
      @curpos += 1
    end
   # $log.debug " crusor FORWARD cp:#{@curpos} pcol:#{@pcol} b.l:#{@buffer.length} d_l:#{@display_length} fc:#{@form.col}"
  end
  def cursor_backward
    if @curpos > 0
      @curpos -= 1
      if @pcol > 0 and @form.col == @col + @col_offset
        @pcol -= 1
      end
      addcol -1
    elsif @pcol > 0 #  added 2008-11-26 23:05 
      @pcol -= 1   
    end
 #   $log.debug " crusor back cp:#{@curpos} pcol:#{@pcol} b.l:#{@buffer.length} d_l:#{@display_length} fc:#{@form.col}"
=begin
# this is perfect if not scrolling, but now needs changes
    if @curpos > 0
      @curpos -= 1
      addcol -1
    end
=end
  end
    def delete_curr_char
      return -1 unless @editable
      delete_at
      set_modified 
    end
    def delete_prev_char
      return -1 if !@editable 
      return if @curpos <= 0
      # if we've panned, then unpan, and don't move cursor back
      # Otherwise, adjust cursor (move cursor back as we delete)
      adjust = true
      if @pcol > 0
        @pcol -= 1
        adjust = false
      end
      @curpos -= 1 if @curpos > 0
      delete_at
      addcol -1 if adjust # move visual cursor back
      set_modified 
    end
    ## add a column to cursor position. Field
    def addcol num
      if num < 0
        if @form.col <= @col + @col_offset
         # $log.debug " error trying to cursor back #{@form.col}"
          return -1
        end
      elsif num > 0
        if @form.col >= @col + @col_offset + @width
      #    $log.debug " error trying to cursor forward #{@form.col}"
          return -1
        end
      end
      @form.addcol num
    end
    # upon leaving a field
    # returns false if value not valid as per values or valid_regex
    # 2008-12-22 12:40 if null_allowed, don't validate, but do fire_handlers
    def on_leave
      val = getvalue
      #$log.debug " FIELD ON LEAVE:#{val}. #{@values.inspect}"
      valid = true
      if val.to_s.empty? && @null_allowed
        #$log.debug " empty and null allowed"
      else
        if !@values.nil?
          valid = @values.include? val
          raise FieldValidationException, "Field value (#{val}) not in values: #{@values.join(',')}" unless valid
        end
        if !@valid_regex.nil?
          valid = @valid_regex.match(val.to_s)
          raise FieldValidationException, "Field not matching regex #{@valid_regex}" unless valid
        end
        # added valid_range for numerics 2011-09-29 
        if !in_range?(val)
          raise FieldValidationException, "Field not matching range #{@valid_range}, above #{@above} or below #{@below}  "
        end
      end
      # here is where we should set the forms modified to true - 2009-01
      if modified?
        set_modified true
      end
      # if super fails we would have still set modified to true
      super
      #return valid
    end

    # checks field against +valid_range+, +above+ and +below+ , returning +true+ if it passes
    # set attributes, +false+ if it fails any one.
    def in_range?( val )
      val = val.to_i
      (@above.nil? or val > @above) and
        (@below.nil? or val < @below) and
        (@valid_range.nil? or @valid_range.include?(val))
    end
    ## save original value on enter, so we can check for modified.
    #  2009-01-18 12:25 
    #   2011-10-9 I have changed to take @buffer since getvalue returns a datatype
    #   and this causes a crash in set_original on cursor forward.
    def on_enter
      #@original_value = getvalue.dup rescue getvalue
      @original_value = @buffer.dup # getvalue.dup rescue getvalue
      super
    end
    ##
    # overriding widget, check for value change
    #  2009-01-18 12:25 
    def modified?
      getvalue() != @original_value
    end
    #
    # Set the value in the field.
    # @param if none given, returns value existing
    # @param value (can be int, float, String)
    # 
    # @return self
    def text(*val)
      if val.empty?
        return getvalue()
      else
        return unless val # added 2010-11-17 20:11, dup will fail on nil
        return unless val[0]
        # 2013-04-20 - 19:02 dup failing on fixnum, set_buffer does a dup
        # so maybe i can do without it here
        #s = val[0].dup
        s = val[0]
        _set_buffer(s)
      end
    end
    alias :default :text
    def text=(val)
      return unless val # added 2010-11-17 20:11, dup will fail on nil
      # will bomb on integer or float etc !!
      #_set_buffer(val.dup)
      _set_buffer(val)
    end
  # ADD HERE FIELD
  end # }}}
        
  ##
  # Like Tk's TkVariable, a simple proxy that can be passed to a widget. The widget 
  # will update the Variable. A variable can be used to link a field with a label or 
  # some other widget.
  # This is the new version of Variable. Deleting old version on 2009-01-17 12:04 
  # == Example
  #    x = Variable.new
  # If x is passed as the +variable+ for a RadioButton group, then this keeps the value of the
  # button that is on.
  #    y = Variable.new false
  #
  #    z = Variable.new Hash.new
  # If z is passed as variable to create several Checkboxes, and each has the +name+ property set,
  # then this hash will contain the status of each checkbox with +name+ as key.

  class Variable # {{{
  
    def initialize value=""
      @update_command = []
      @args = []
      @value = value
      @klass = value.class.to_s
    end

    ## 
    # This is to ensure that change handlers for all dependent objects are called
    # so they are updated. This is called from text_variable property of some widgets. If you 
    # use one text_variable across objects, all will be updated auto. User does not need to call.
    # NOTE: I have removed text_variable from widget to simplify, so this seems to be dead.
    # @ private
    def add_dependent obj
      $log.debug " ADDING DEPENDE #{obj}"
      @dependents ||= []
      @dependents << obj
    end
    ##
    # install trigger to call whenever a value is updated
    # @public called by user components
    def update_command *args, &block
      $log.debug "Variable: update command set " # #{args}"
      @update_command << block
      @args << args
    end
    alias :command :update_command
    ##
    # value of the variable
    def get_value val=nil
      if @klass == 'String'
        return @value
      elsif @klass == 'Hash'
        return @value[val]
      elsif @klass == 'Array'
        return @value[val]
      else
        return @value
      end
    end
    ##
    # update the value of this variable.
    # 2008-12-31 18:35 Added source so one can identify multiple sources that are updating.
    # Idea is that mutiple fields (e.g. checkboxes) can share one var and update a hash through it.
    # Source would contain some code or key relatin to each field.
    def set_value val, key=""
      oldval = @value
      if @klass == 'String'
        @value = val
      elsif @klass == 'Hash'
        #$log.debug " Variable setting hash #{key} to #{val}"
        oldval = @value[key]
        @value[key]=val
      elsif @klass == 'Array'
        #$log.debug " Variable setting array #{key} to #{val}"
        oldval = @value[key]
        @value[key]=val
      else
        oldval = @value
        @value = val
      end
      return if @update_command.nil?
      @update_command.each_with_index do |comm, ix|
        comm.call(self, *@args[ix]) unless comm.nil?
      end
      @dependents.each {|d| d.fire_property_change(d, oldval, val) } unless @dependents.nil?
    end
    ##
    def value= (val)
      raise "Please use set_value for hash/array" if @klass=='Hash' or @klass=='Array'
      oldval = @value
      @value=val
      return if @update_command.nil?
      @update_command.each_with_index do |comm, ix|
        comm.call(self, *@args[ix]) unless comm.nil?
      end
      @dependents.each {|d| d.fire_property_change(d, oldval, val) } unless @dependents.nil?
    end
    def value
      raise "Please use set_value for hash/array: #{@klass}" if @klass=='Hash' #or @klass=='Array'
      @value
    end
    def inspect
      @value.inspect
    end
    def [](key)
      @value[key]
    end
    ## 
    # in order to run some method we don't yet support
    def source
      @value
    end
    def to_s
      inspect
    end
  end # }}}
  ##
  # The preferred way of printing text on screen, esp if you want to modify it at run time.
  # Use display_length to ensure no spillage.
  # This can use text or text_variable for setting and getting data (inh from Widget).
  # 2011-11-12 making it simpler, and single line only. The original multiline label
  #    has moved to extras/multilinelabel.rb
  #
  class Label < Widget # {{{
    dsl_accessor :mnemonic       # keyboard focus is passed to buddy based on this key (ALT mask)

    # justify required a display length, esp if center.
    dsl_property :justify        #:right, :left, :center
    #dsl_property :display_length #please give this to ensure the we only print this much
    # for consistency with others 2011-11-5 
    #alias :width :display_length
    #alias :width= :display_length=

    def initialize form, config={}, &block
  
      @text = config.fetch(:text, "NOTFOUND")
      @editable = false
      @focusable = false
      # we have some processing for when a form is attached, registering a hotkey
      register_events :FORM_ATTACHED
      super
      @justify ||= :left
      @name ||= @text
      @repaint_required = true
    end
    #
    # get the value for the label
    def getvalue
      #@text_variable && @text_variable.value || @text
      @text
    end
    def label_for field
      @label_for = field
      #$log.debug " label for: #{@label_for}"
      if @form
        bind_hotkey 
      else
      # we have some processing for when a form is attached, registering a hotkey
        bind(:FORM_ATTACHED){ bind_hotkey }
      end
    end

    ##
    # for a button, fire it when label invoked without changing focus
    # for other widgets, attempt to change focus to that field
    def bind_hotkey
      if @mnemonic
        ch = @mnemonic.downcase()[0].ord   ##  1.9 DONE 
        # meta key 
        mch = ?\M-a.getbyte(0) + (ch - ?a.getbyte(0))  ## 1.9
        if (@label_for.is_a? Canis::Button ) && (@label_for.respond_to? :fire)
          @form.bind_key(mch, "hotkey for button #{@label_for.text} ") { |_form, _butt| @label_for.fire }
        else
          $log.debug " bind_hotkey label for: #{@label_for}"
          @form.bind_key(mch, "hotkey for label #{text} ") { |_form, _field| @label_for.focus }
        end
      end
    end

    ##
    # label's repaint - I am removing wrapping and Array stuff and making it simple 2011-11-12 
    def repaint
      return unless @repaint_required
      raise "Label row or col nil #{@row} , #{@col}, #{@text} " if @row.nil? || @col.nil?
      r,c = rowcol

      @bgcolor ||= $def_bg_color
      @color   ||= $def_fg_color
      # value often nil so putting blank, but usually some application error
      value = getvalue_for_paint || ""

      if value.is_a? Array
        value = value.join " "
      end
      # ensure we do not exceed
      if @width
        if value.length > @width
          value = value[0..@width-1]
        end
      end
      len = @width || value.length
      #acolor = get_color $datacolor
      # the user could have set color_pair, use that, else determine color
      # This implies that if he sets cp, then changing col and bg won't have an effect !
      # A general routine that only changes color will not work here.
      acolor = @color_pair || get_color($datacolor, @color, @bgcolor)
      #$log.debug "label :#{@text}, #{value}, r #{r}, c #{c} col= #{@color}, #{@bgcolor} acolor  #{acolor} j:#{@justify} dlL: #{@width} "
      str = @justify.to_sym == :right ? "%*s" : "%-*s"  # added 2008-12-22 19:05 
    
      @graphic ||= @form.window
      # clear the area
      @graphic.printstring r, c, " " * len , acolor, @attr
      if @justify.to_sym == :center
        padding = (@width - value.length)/2
        value = " "*padding + value + " "*padding # so its cleared if we change it midway
      end
      @graphic.printstring r, c, str % [len, value], acolor, @attr
      if @mnemonic
        ulindex = value.index(@mnemonic) || value.index(@mnemonic.swapcase)
        @graphic.mvchgat(y=r, x=c+ulindex, max=1, Ncurses::A_BOLD|Ncurses::A_UNDERLINE, acolor, nil)
      end
      @repaint_required = false
    end
    # Added 2011-10-22 to prevent some naive components from putting focus here.
    def on_enter
      raise "Cannot enter Label"
    end
    def on_leave
      raise "Cannot leave Label"
    end
  # ADD HERE LABEL
  end # }}}
  ##
  # action buttons
  # Use +text+ to pass the string to be printed on the button
  # An ampersand is understaod to denote a shortcut and will map Alt-char to that button's FIRE event
  # Alternative, +mnemonic(char)+ can also be used.
  # In the config hash, ':hotkey' may be passed which maps the character itself to the button's FIRE.
  # This is for menulinks, and maybe a form that has only buttons.
  # 
  # NOTE: When firing event, an ActionEvent will be passed as the first parameter, followed by anything
  # you may have passed when binding, or calling the command() method. 
  #  - Action: may have to listen to Action property changes so enabled, name etc change can be reflected
  # 2011-11-26 : define button as default, so it can show differently and also fire on ENTER
  # trying out behavior change. space to fire current button, ENTER for default button which has
  # > Name < look.
  class Button < Widget # {{{
    dsl_accessor :surround_chars   # characters to use to surround the button, def is square brackets
    # char to be underlined, and bound to Alt-char
    dsl_accessor :mnemonic
    def initialize form, config={}, &block
      require 'canis/core/include/ractionevent'
      @focusable = true
      @editable = false
      # hotkey denotes we should bind the key itself not alt-key (for menulinks)
      @hotkey = config.delete(:hotkey) 
      register_events([:PRESS, :FORM_ATTACHED])
      @default_chars = ['> ', ' <'] 
      super


      @surround_chars ||= ['[ ', ' ]'] 
      @col_offset = @surround_chars[0].length 
      @text_offset = 0
      map_keys
    end
    ##
    # set button based on Action
    def action a
      text a.name
      mnemonic a.mnemonic unless a.mnemonic.nil?
      command { a.call }
    end
    ##
    # button:  sets text, checking for ampersand, uses that for hotkey and underlines
    def text(*val)
      if val.empty?
        return @text
      else
        s = val[0].dup
        s = s.to_s if !s.is_a? String  # 2009-01-15 17:32 
        if (( ix = s.index('&')) != nil)
          s.slice!(ix,1)
          @underline = ix #unless @form.nil? # this setting a fake underline in messageboxes
          @text = s # mnemo needs this for setting description
          mnemonic s[ix,1]
        end
        @text = s
      end
      return self 
    end

    ## 
    # FIXME this will not work in messageboxes since no form available
    # if already set mnemonic, then unbind_key, ??
    # NOTE: Some buttons like checkbox directly call mnemonic, so if they have no form
    # then this processing does not happen

    # set mnemonic for button, this is a hotkey that triggers +fire+ upon pressing Alt+char
    def mnemonic char=nil
      return @mnemonic unless char  # added 2011-11-24 so caller can get mne

      unless @form
        # we have some processing for when a form is attached, registering a hotkey
        bind(:FORM_ATTACHED) { mnemonic char }
        return self # added 2014-03-23 - 22:59 so that we can chain methods
      end
      @mnemonic = char
      ch = char.downcase()[0].ord ##  1.9 
      # meta key 
      ch = ?\M-a.getbyte(0) + (ch - ?a.getbyte(0)) unless @hotkey
      $log.debug " #{self} setting MNEMO to #{char} #{ch}, #{@hotkey} "
      _t = self.text || self.name || "Unnamed #{self.class} "
      @form.bind_key(ch, "hotkey for button #{_t} ") { |_form, _butt| self.fire }
      return self # added 2015-03-23 - 22:59 so that we can chain methods
    end

    ##
    # bind hotkey to form keys. added 2008-12-15 20:19 
    # use ampersand in name or underline
    # IS THIS USED ??
    def bind_hotkey
      alert "bind_hotkey was called in button"
      if @form.nil? 
        if @underline
          bind(:FORM_ATTACHED){ bind_hotkey }
        end
        return
      end
      _value = @text || getvalue # hack for Togglebutton FIXME
      $log.debug " bind hot #{_value} #{@underline}"
      ch = _value[@underline,1].downcase()[0].ord ##  1.9  2009-10-05 18:55  TOTEST
      @mnemonic = _value[@underline,1]
      # meta key 
      mch = ?\M-a.getbyte(0) + (ch - ?a.getbyte(0))
      @form.bind_key(mch, "hotkey for button #{self.text}" ) { |_form, _butt| self.fire }
    end
    def default_button tf=nil
      return @default_button unless tf
      raise ArgumentError, "default button must be true or false" if ![false,true].include? tf
      $log.debug "XXX:  BUTTON DEFAULT setting to true : #{tf} "
      @default_button = tf
      if tf
        @surround_chars = @default_chars
        @form.bind_key(13, "fire #{self.text} ") { |_form, _butt| self.fire }
      else
        # i have no way of reversing the above
      end
    end

    def getvalue
      #@text_variable.nil? ? @text : @text_variable.get_value(@name)
      @text
    end

    # ensure text has been passed or action
    def getvalue_for_paint
      ret = getvalue
      @text_offset = @surround_chars[0].length
      @surround_chars[0] + ret + @surround_chars[1]
    end

    def repaint  # button

      @bgcolor ||= $def_bg_color
      @color   ||= $def_fg_color
        $log.debug("BUTTON repaint : #{self}  r:#{@row} c:#{@col} , #{@color} , #{@bgcolor} , #{getvalue_for_paint}" )
        r,c = @row, @col #rowcol include offset for putting cursor
        # NOTE: please override both (if using a string), or else it won't work 
        @highlight_foreground ||= $reversecolor
        @highlight_background ||= 0
        _bgcolor = @bgcolor
        _color = @color
        if @state == :HIGHLIGHTED
          _bgcolor = @state==:HIGHLIGHTED ? @highlight_background : @bgcolor
          _color = @state==:HIGHLIGHTED ? @highlight_foreground : @color
        elsif selected? # only for certain buttons lie toggle and radio
          _bgcolor = @selected_background || @bgcolor
          _color   = @selected_foreground || @color
        end
        $log.debug "XXX: button #{text}   STATE is #{@state} color #{_color} , bg: #{_bgcolor} "
        if _bgcolor.is_a?( Fixnum) && _color.is_a?( Fixnum)
        else
          _color = get_color($datacolor, _color, _bgcolor)
        end
        value = getvalue_for_paint
        $log.debug("button repaint :#{self} r:#{r} c:#{c} col:#{_color} bg #{_bgcolor} v: #{value} ul #{@underline} mnem #{@mnemonic} datacolor #{$datacolor} ")
        len = @width || value.length
        @graphic = @form.window if @graphic.nil? ## cell editor listbox hack 
        @graphic.printstring r, c, "%-*s" % [len, value], _color, @attr
#       @form.window.mvchgat(y=r, x=c, max=len, Ncurses::A_NORMAL, bgcolor, nil)
        # in toggle buttons the underline can change as the text toggles
        if @underline || @mnemonic
          uline = @underline && (@underline + @text_offset) ||  value.index(@mnemonic) || 
            value.index(@mnemonic.swapcase)
          # if the char is not found don't print it
          if uline
            y=r #-@graphic.top
            x=c+uline #-@graphic.left
            if @graphic.window_type == :PAD
              x -= @graphic.left 
              y -= @graphic.top
            end
            #
            # NOTE: often values go below zero since root windows are defined 
            # with 0 w and h, and then i might use that value for calcaluting
            #
            $log.error "XXX button underline location error #{x} , #{y} " if x < 0 or c < 0
            raise " #{r} #{c}  #{uline} button underline location error x:#{x} , y:#{y}. left #{@graphic.left} top:#{@graphic.top} " if x < 0 or c < 0
            @graphic.mvchgat(y, x, max=1, Ncurses::A_BOLD|Ncurses::A_UNDERLINE, _color, nil)
          end
        end
    end

    ## command of button (invoked on press, hotkey, space)
    # added args 2008-12-20 19:22 
    def command *args, &block
      bind :PRESS, *args, &block
    end
    ## fires PRESS event of button
    def fire
      #$log.debug "firing PRESS #{text}"
      fire_handler :PRESS, ActionEvent.new(self, :PRESS, text)
    end
    # for campatibility with all buttons, will apply to radio buttons mostly
    def selected?; false; end

    def map_keys
      return if @keys_mapped
      bind_key(32, "fire") { fire } if respond_to? :fire
      if $key_map_type == :vim
        bind_key( key("j"), "down") { @form.window.ungetch(KEY_DOWN) }
        bind_key( key("k"), "up") { @form.window.ungetch(KEY_UP) }
      end
    end

    # Button
    def handle_key ch
      super
    end
=begin
      case ch
      when FFI::NCurses::KEY_LEFT, FFI::NCurses::KEY_UP
        return :UNHANDLED
        #  @form.select_prev_field
      when FFI::NCurses::KEY_RIGHT, FFI::NCurses::KEY_DOWN
        return :UNHANDLED
        #  @form.select_next_field
      # 2014-05-07 - 12:26 removed ENTER on buttons
        #  CANIS : button only responds to SPACE, ENTER will only work on default button.
      #when FFI::NCurses::KEY_ENTER, 10, 13, 32  # added space bar also
        # I am really confused about this. Default button really confuses things in some 
        # situations, but is great if you are not on the buttons.
        # shall we keep ENTER for default button
      when 32  # added space bar also
        if respond_to? :fire
          fire
        end
      else
        if $key_map_type == :vim
          case ch
          when ?j.getbyte(0)
            @form.window.ungetch(KEY_DOWN)
            return 0
          when ?k.getbyte(0)
            @form.window.ungetch(KEY_UP)
            return 0
          end

        end
        return :UNHANDLED
      end
    end
=end

    # temporary method, shoud be a proper class
    def self.button_layout buttons, row, startcol=0, cols=Ncurses.COLS-1, gap=5
      col = startcol
      buttons.each_with_index do |b, ix|
        $log.debug " BUTTON #{b}: #{b.col} "
        b.row = row
        b.col col
        $log.debug " after BUTTON #{b}: #{b.col} "
        len = b.text.length + gap
        col += len
      end
    end
  end #BUTTON # }}}
  
  ##
  # an event fired when an item that can be selected is toggled/selected
  class ItemEvent  # {{{
    # http://java.sun.com/javase/6/docs/api/java/awt/event/ItemEvent.html
    attr_reader :state   # :SELECTED :DESELECTED
    attr_reader :item   # the item pressed such as toggle button
    attr_reader :item_selectable   # item originating event such as list or collection
    attr_reader :item_first   # if from a list
    attr_reader :item_last   # 
    attr_reader :param_string   #  for debugging etc
=begin
    def initialize item, item_selectable, state, item_first=-1, item_last=-1, paramstring=nil
      @item, @item_selectable, @state, @item_first, @item_last =
        item, item_selectable, state, item_first, item_last 
      @param_string = "Item event fired: #{item}, #{state}"
    end
=end
    # i think only one is needed per object, so create once only
    def initialize item, item_selectable
      @item, @item_selectable =
        item, item_selectable
    end
    def set state, item_first=-1, item_last=-1, param_string=nil
      @state, @item_first, @item_last, @param_string =
        state, item_first, item_last, param_string 
      @param_string = "Item event fired: #{item}, #{state}" if param_string.nil?
    end
  end # }}}
  ##
  # A button that may be switched off an on. 
  # To be extended by RadioButton and checkbox.
  # WARNING, pls do not override +text+ otherwise checkboxes etc will stop functioning.
  # TODO: add editable here nd prevent toggling if not so.
  class ToggleButton < Button # {{{
    # text for on value and off value
    dsl_accessor :onvalue, :offvalue
    # boolean, which value to use currently, onvalue or offvalue
    dsl_accessor :value
    # characters to use for surround, array, default square brackets
    dsl_accessor :surround_chars 
    dsl_accessor :variable    # value linked to this variable which is a boolean
    # background to use when selected, if not set then default
    dsl_accessor :selected_background 
    dsl_accessor :selected_foreground 

    def initialize form, config={}, &block
      super
      
      @value ||= (@variable.nil? ? false : @variable.get_value(@name)==true)
    end
    def getvalue
      @value ? @onvalue : @offvalue
    end

    # WARNING, pls do not override +text+ otherwise checkboxes etc will stop functioning.

    # added for some standardization 2010-09-07 20:28 
    # alias :text :getvalue # NEXT VERSION
    # change existing text to label
    ##
    # is the button on or off
    # added 2008-12-09 19:05 
    def checked?
      @value
    end
    alias :selected? :checked?

    def getvalue_for_paint
      unless @width
        if @onvalue && @offvalue
          @width = [ @onvalue.length, @offvalue.length ].max
        end
      end
      buttontext = getvalue().center(@width)
      @text_offset = @surround_chars[0].length
      @surround_chars[0] + buttontext + @surround_chars[1]
    end

    # toggle button handle key
    # @param [int] key received
    #
    def handle_key ch
      if ch == 32
        toggle
      else
        super
      end
    end

    ##
    # toggle the button value
    def toggle
      fire
    end

    # called on :PRESS event
    # caller should check state of itemevent passed to block
    def fire
      checked(!@value)
      @item_event = ItemEvent.new self, self if @item_event.nil?
      @item_event.set(@value ? :SELECTED : :DESELECTED)
      fire_handler :PRESS, @item_event # should the event itself be ITEM_EVENT
    end
    ##
    # set the value to true or false
    # user may programmatically want to check or uncheck
    def checked tf
      @value = tf
      if @variable
        if @value 
          @variable.set_value((@onvalue || 1), @name)
        else
          @variable.set_value((@offvalue || 0), @name)
        end
      end
    end
  end # class # }}}

  ##
  # A checkbox, may be selected or unselected
  #
  class CheckBox < ToggleButton # {{{
    dsl_accessor :align_right    # the button will be on the right 2008-12-09 23:41 
    # if a variable has been defined, off and on value will be set in it (default 0,1)
    def initialize form, config={}, &block
      @surround_chars = ['[', ']']    # 2008-12-23 23:16 added space in Button so overriding
      super
    end
    def getvalue
      @value 
    end
      
    def getvalue_for_paint
      buttontext = getvalue() ? "X" : " "
      dtext = @width.nil? ? @text : "%-*s" % [@width, @text]
      dtext = "" if @text.nil?  # added 2009-01-13 00:41 since cbcellrenderer prints no text
      if @align_right
        @text_offset = 0
        @col_offset = dtext.length + @surround_chars[0].length + 1
        return "#{dtext} " + @surround_chars[0] + buttontext + @surround_chars[1] 
      else
        pretext = @surround_chars[0] + buttontext + @surround_chars[1] 
        @text_offset = pretext.length + 1
        @col_offset = @surround_chars[0].length
        #@surround_chars[0] + buttontext + @surround_chars[1] + " #{@text}"
        return pretext + " #{dtext}"
      end
    end
  end # class # }}}

  # This is not a visual class or a widget.
  # This class allows us to attach several RadioButtons to it, so it can maintain which one is the 
  # selected one. It also allows for assigning of commands to be executed whenever a button is pressed,
  # akin to binding to the +fire+ of the button, except that one would not have to bind to each button,
  # but only once here.
  #
  # @example
  #     group = ButtonGroup.new
  #     group.add(r1).add(r2).add(r3)
  #     # change the color of +somelabel+ to the color specified by the value of clicked radio.
  #     group.command(somelabel) do |grp, label| label.color(grp.value); end
  #
  # Added on 2014-04-30
  class ButtonGroup # -- {{{

    # Array of buttons that have been added.
    attr_reader :elements

    # the value of the radio button that is selected. To get the button itself, use +selection+.
    attr_reader :value
    def initialize 
      @elements = []
      @hash = {}
    end

    def add e
      @elements << e
      @hash[e.value] = e
      e.variable(self)
      self
    end
    def remove e
      @elements.delete e
      @hash.delete e.value
      self
    end

    # @return the radiobutton that is selected
    def selection
      @hash[@value]
    end

    # @param [String, RadioButton] +value+ of a button, or +Button+ itself to check if selected.
    # @return [true or false] for wether the given value or button is the selected one
    def selected? val
      if val.is_a? String
        @value == val
      else
        @hash[@value] == val
      end
    end
    # install trigger to call whenever a value is updated
    # @public called by user components
    def command *args, &block
      @commands ||= []
      @args ||= []
      @commands << block
      @args << args
    end
    # select the given button or value. 
    # This may be called by user programs to programmatically select a button
    def select button
      if button.is_a? String
        ;
      else
        button = button.value
      end
      set_value button
    end

    # when a radio button is pressed, it calls set_value giving the value of that radio.
    # it also gives the name (optionally) since Variables can also be passed and be used across 
    # groups. Here, since a button group is only for one group, so we discard name.
    # @param [String] value (text) of radio button that is selected
    #
    # This is used by RadioButton class for backward compat with Variable.
    def set_value value, name=nil
      @value = value
      return unless @commands
      @commands.each_with_index do |comm, ix|
        comm.call(self, *@args[ix]) unless comm.nil?
      end
    end
    # returns the value of the selected button
    # NOTE: This is used by RadioButton class for backward compat with Variable.
    # User programs should use +value()+
    def get_value name=nil
      @value
    end
  end # -- }}}
  ##
  # A selectable button that has a text value. It is based on a Variable that
  # is shared by other radio buttons. Only one is selected at a time, unlike checkbox
  # +text+ is the value to display, which can include an ampersand for a hotkey
  # +value+ is the value returned if selected, which usually is similar to text (or a short word)
  # +width+ is helpful if placing the brackets to right of text, used to align round brackets
  #   By default, radio buttons place the button on the left of the text.
  #
  # Typically, the variable's update_command is passed a block to execute whenever any of the 
  # radiobuttons of this group is fired.

  class RadioButton < ToggleButton # {{{
    dsl_accessor :align_right    # the button will be on the right 2008-12-09 23:41 
    # if a variable has been defined, off and on value will be set in it (default 0,1)
    def initialize form, config={}, &block
      @surround_chars = ['(', ')'] if @surround_chars.nil?
      super
      $log.warn "XXX: FIXME Please set 'value' for radiobutton. If not sure, try setting it to the same value as 'text'" unless @value
      # I am setting value of value here if not set 2011-10-21 
      @value ||= @text
      ## trying with off since i can't do conventional style construction
      #raise "A single Variable must be set for a group of Radio Buttons for this to work." unless @variable
    end

    # all radio buttons will return the value of the selected value, not the offered value
    def getvalue
      @variable.get_value @name
    end

    def getvalue_for_paint
      buttontext = getvalue() == @value ? "o" : " "
      dtext = @width.nil? ? text : "%-*s" % [@width, text]
      if @align_right
        @text_offset = 0
        @col_offset = dtext.length + @surround_chars[0].length + 1
        return "#{dtext} " + @surround_chars[0] + buttontext + @surround_chars[1] 
      else
        pretext = @surround_chars[0] + buttontext + @surround_chars[1] 
        @text_offset = pretext.length + 1
        @col_offset = @surround_chars[0].length
        return pretext + " #{dtext}"
      end
    end

    def toggle
      @variable.set_value @value, @name
      # call fire of button class 2008-12-09 17:49 
      fire
    end

    # added for bindkeys since that calls fire, not toggle - XXX i don't like this
    def fire
      @variable.set_value  @value, @name
      super
    end

    ##
    # ideally this should not be used. But implemented for completeness.
    # it is recommended to toggle some other radio button than to uncheck this.
    def checked tf
      if tf
        toggle
      elsif !@variable.nil? and getvalue() != @value # XXX ???
        @variable.set_value "", ""
      end
    end
  end # class radio # }}}

  def self.startup
    Canis::start_ncurses
    path = File.join(ENV["LOGDIR"] || "./" ,"canis14.log")
    file   = File.open(path, File::WRONLY|File::TRUNC|File::CREAT) 
    $log = Logger.new(path)
    $log.level = Logger::DEBUG
  end

end # module
include Canis::Utils
