require 'canis/core/widgets/rlink'
##
module Canis
  class MenuLink < Link
    dsl_property :description

    def initialize form, config={}, &block
      config[:hotkey] = true
      super
      @col_offset = -1 * (@col || 1)
      @row_offset = -1 * (@row || 1)
      # in this case, we wish to use ENTER for firing
      bind_key( KEY_ENTER, "fire" ) { fire }
      # next did not work
      #bind_key( KEY_ENTER, "fire" ) { get_action( 32 ) }
      # next 2 work
      #bind_key( KEY_ENTER, "fire" ) { @form.window.ungetch(32)  }
      #@_key_map[KEY_ENTER] = @_key_map[32]
      #get_action_map()[KEY_ENTER] = get_action(32)
    end
    # added for some standardization 2010-09-07 20:28 
    # alias :text :getvalue # NEXT VERSION
    # change existing text to label

    def getvalue_for_paint
      "%s      %-12s   -    %-s" % [ @mnemonic , getvalue(), @description ]
    end
    ##
  end # class
end # module
