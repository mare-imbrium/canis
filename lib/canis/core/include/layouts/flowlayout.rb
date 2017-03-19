# ----------------------------------------------------------------------------- #
#         File: stacklayout.rb
#  Description: 
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-05-08 - 18:33
#      License: MIT
#  Last update: 2017-03-09 23:13
# ----------------------------------------------------------------------------- #
#  stacklayout.rb  Copyright (C) 2012-2014 j kepler
require 'canis/core/include/layouts/abstractlayout'
#  ---- 
#  This does a simple left to right stacking of objects. 
#  if no objects are passed to it, it will take all widgets from the form.
#
#  Individual objects may be configured by setting :weight using +cset+.
#       layout = FlowLayout.new :height => -1, :top_margin => 1, :bottom_margin => 1, :left_margin => 1
#       layout.cset(obj,  :weight, 15)   # fixed width of 15
#       layout.cset(obj1, :weight, 0.50)  # takes 50% of balance area (area not fixed)
#  
class FlowLayout < AbstractLayout

  # @param [Form]  optional give a form      
  # @param [Hash]  optional give settings/attributes which will be set into variables
  def initialize arg, config={}, &block
    super
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
      _tmpwt = cget(e, :weight) || 0
      # what of field and button placed side by side
      if e.is_a? Field or e.is_a? Button or e.is_a? Label
        # what to do here ?
        @wts[e] ||= 1
        ht += @wts[e] || 1
        fixed_ctr += 1
      elsif _tmpwt >= 1
          ht += _tmpwt || 0
          fixed_ctr += 1
      elsif _tmpwt > 0 and _tmpwt <= 1
        # FIXME how to specify 100 % ???
        var_ctr += 1
        var_wt += _tmpwt
      end
    end
    unaccounted = @components.count - (fixed_ctr + var_ctr)
    $log.debug "  unacc #{unaccounted} , fixed #{fixed_ctr} , var : #{var_ctr} , ht #{ht} height #{@height}  "
    balance_ht = @width - ht # use this for those who have specified a %
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
      wt = cget(e, :weight)
      if wt
        if wt.is_a? Integer
          e.width = wt
        elsif wt.is_a? Float
          e.width = (wt * balance_ht).floor
        end
      else
        # no wt specified, give average of balance wt
        e.width = average_ht
        hround = e.width.floor

        rem += e.width - hround
        e.width = hround
        # see comment in prev block regarding remaininder
        if rem >= 1
          e.width += 1
          rem = 0
        end
      end
      $log.debug "  layout #{e.name} , w: #{e.width} r: #{e.row} , c = #{e.col} "

      e.height = @height
      c += e.width.floor
      c += @gap
    end
    $log.debug "  layout finished "
  end

end
