# ----------------------------------------------------------------------------- #
#         File: stacklayout.rb
#  Description: 
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-05-08 - 18:33
#      License: MIT
#  Last update: 2014-05-09 19:58
# ----------------------------------------------------------------------------- #
#  stacklayout.rb  Copyright (C) 2012-2014 j kepler
require 'canis/core/include/layouts/abstractlayout'
#  ---- 
#  This does a simple stacking of objects. Or all objects.
#  Some simple layout managers may not require objects to be passed to
#  it, others that are complex may require the same.
class StackLayout < AbstractLayout

  # @param [Form]  optional give a form      
  # @param [Hash]  optional give settings/attributes which will be set into variables
  def initialize arg, config={}, &block
    @wts = {}
    super
  end


  # in case user does not wish to add objects, but wishes to specify the weightage on one,
  # send in the widget and its weightage.
  #
  # @param [Widget] widget whose weightage is to be specified
  # @param [Float, Fixnum] weightage for the given widget (@see add_with_weight)
  def weightage item, wt
    @wts[item] = wt
  end


  # This program lays out the widgets deciding their row and columm and height and weight.
  # This program is called once at start of application, and again whenever a RESIZE event happens.
  def do_layout
    _init_layout
    r = @top_margin
    c = @left_margin
    #
    # determine fixed widths and how much is left to share with others,
    # and how many variable width components there are.
    ht = 0   # accumulate fixed height
    fixed_ctr = 0 # how many items have a fixed wt
    var_ctr = 0
    var_wt = 0.0
    @components.each do |e|
      $log.debug "  looping 1 #{e.name} "
      _tmpwt = @wts[e] || 0
      # what of field and button placed side by side
      if e.is_a? Field or e.is_a? Button or e.is_a? Label
        @wts[e] ||= 1
        ht += @wts[e] || 1
        fixed_ctr += 1
      elsif _tmpwt >= 1
          ht += @wts[e] || 0
          fixed_ctr += 1
      elsif _tmpwt > 0 and _tmpwt <= 1
        # FIXME how to specify 100 % ???
        var_ctr += 1
        var_wt += @wts[e]
      end
    end
    unaccounted = @components.count - (fixed_ctr + var_ctr)
    $log.debug "  unacc #{unaccounted} , fixed #{fixed_ctr} , var : #{var_ctr} , ht #{ht} height #{@height}  "
    balance_ht = @height - ht # use this for those who have specified a %
    balance_ht1 = balance_ht * (1 - var_wt )
    average_ht = (balance_ht1 / unaccounted).floor # give this to those who have not specified ht
    average_ht = (balance_ht1 / unaccounted) # give this to those who have not specified ht
    $log.debug "  #{balance_ht} , #{balance_ht1} , #{average_ht} "
    # not accounted for gap in heights
    rem = 0 # remainder to be carried over
    @components.each do |e|
      $log.debug "  looping 2 #{e.name} #{e.class.to_s.downcase} "
      next if @ignore_list.include? e.class.to_s.downcase
      $log.debug "  looping 3 #{e.name} "
      e.row = r
      e.col = c
      wt = @wts[e]
      if wt
        if wt.is_a? Fixnum
          e.height = wt
        elsif wt.is_a? Float
          e.height = (wt * balance_ht).floor
        end
      else
        # no wt specified, give average of balance wt
        e.height = average_ht
        hround = e.height.floor

        rem += e.height - hround
        e.height = hround
        # see comment in prev block regarding remaininder
        if rem >= 1
          e.height += 1
          rem = 0
        end
      end
      $log.debug "  layout #{e.name} , h: #{e.height} r: #{e.row} , c = #{e.col} "

      e.width = @width
      r += e.height.floor
      r += @gap
    end
    $log.debug "  layout finished "
  end

end
