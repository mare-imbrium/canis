# ----------------------------------------------------------------------------- #
#         File: stacklayout.rb
#  Description: 
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-05-08 - 18:33
#      License: MIT
#  Last update: 2014-05-09 14:11
# ----------------------------------------------------------------------------- #
#  stacklayout.rb  Copyright (C) 2012-2014 j kepler
#
# TODO move some of this to a basic, abstract Layout class
#  ---- 
#  This does a simple stacking of objects. Or all objects.
#  Some simple layout managers may not require objects to be passed to
#  it, others that are complex may require the same.
class StackLayout
  attr_accessor :form
  # top and left are actually row and col in widgets
  attr_accessor :top_margin, :left_margin, :right_margin, :bottom_margin
  # if width percent is given, then it calculates and overwrites width. Same for height_pc
  attr_accessor :width, :height, :width_pc, :height_pc
  # gp between objects
  attr_accessor :gap
  attr_accessor :components
  def initialize arg, config={}, &block
    @width = @height = 0
    @top_margin = @left_margin = @right_margin = @bottom_margin = 0
    # weightages of each object
    @wts = {}
    if arg.is_a? Hash
      @config = arg
    else
      @arg = arg
    end
    @gap = 0
    @config.each_pair { |k,v| instance_variable_set("@#{k}",v) }
    #@ignore_list = [Canis::StatusLine, Canis::ApplicationHeader]
    @ignore_list = ["canis::statusline", "canis::applicationheader"]
    instance_eval &block if block_given?
  end
  def add *items
    @components ||= []
    @components.push items
  end
  # if wt is >= 1 then it is absolute height, else if between 0 and 1 ,
  # it is a percentage.
  def add_with_weight item, weight
    @components ||= []
    @components << item
    @wts ||= {}
    @wts[item] = weight
  end
  # in case user does not wish to add objects, but wishes to specify the weightage on one,
  # send in the widget and its weightage.
  #
  def weightage item, wt
    @wts[item] = wt
  end

  def remove item
    @components.remeove item
  end
  def clear
    @components.clear
  end

  def do_layout
    $log.debug "  inside do_layout"
    r = @top_margin
    @saved_width ||= @width
    @saved_height ||= @height

    lines = Ncurses.LINES - 1
    columns = Ncurses.COLS - 1
    c = @left_margin
    if @height_pc
      # FIXME calc the percentage
      @height = lines - @top_margin - @bottom_margin
    elsif @saved_height <= 0
      @height = lines - @saved_height - @top_margin - @bottom_margin
    end
    $log.debug "  layout height = #{@height} "
    if @width_pc
      # FIXME calc the percentage
      @width = columns - @left_margin - @right_margin
    elsif @saved_width <= 0
      # if width was -1 we have overwritten it so now we cannot recalc it. it remains the same
      @width = columns - @saved_width - @left_margin - @right_margin
    end
    $log.debug "  layout wid = #{@width} "
    # if user has not specified, then get all the objects
    @components ||= @form.widgets.select do |w| w.visible != false && !@ignore_list.include?(w.class.to_s.downcase); end
    $log.debug "  components #{@components.count} "
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
