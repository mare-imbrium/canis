# ----------------------------------------------------------------------------- #
#         File: abstractlayout.rb
#  Description: An abstract class for other concrete layouts to subclass
#       Author: j kepler  http://github.com/mare-imbrium/canis/
#         Date: 2014-05-09 - 17:15
#      License: MIT
#  Last update: 2017-03-09 23:13
# ----------------------------------------------------------------------------- #
#  abstractlayout.rb  Copyright (C) 2012-2014 j kepler


class AbstractLayout
  attr_accessor :form
  # top and left are actually row and col in widgets
  # 
  attr_accessor :top_margin, :left_margin, :right_margin, :bottom_margin
  # if width percent is given, then it calculates and overwrites width. Same for height_pc
  # The _pc values should be between 0 and 1, e.g 0.8 for 80 percent
  # height and width can be negaive. -1 will stretch the stack to one less than end. 0 will stretch till end.
  attr_accessor :width, :height, :width_pc, :height_pc
  # gp between objects
  attr_accessor :gap
  attr_accessor :components
  attr_accessor :ignore_list

  # @param [Form]  optional give a form      
  # @param [Hash]  optional give settings/attributes which will be set into variables
  def initialize form, config={}, &block
    @width = @height = 0
    @top_margin = @left_margin = @right_margin = @bottom_margin = 0
    # weightages of each object
    #@wts = {}
    # item_config is a hash which contains a hash of attibs for each item.
    @item_config = Hash.new do |hash, key| hash[key]={}; end

    if form.is_a? Hash
      @config = form
    elsif form.is_a? Form
      @form = form
    end
    @gap = 0
    @ignore_list = ["canis::statusline", "canis::applicationheader"]
    @config.each_pair { |k,v| instance_variable_set("@#{k}",v) }
    #@ignore_list = [Canis::StatusLine, Canis::ApplicationHeader]
    instance_eval &block if block_given?
  end

  # add one more items for this layout to lay out
  # If no items are given, this program will take all visible widgets from the form
  # and stack them, ignoring statusline and applicationheader
  def push *items
    @components ||= []
    @components.push items
    self
  end
  alias :<< :push

  # add a widget giving a hash of attributes to be used later.
  def add item, config={}
    @components ||= []
    @components << item
    if config
      @item_config[item] = config
    end
    self
  end

  def configure_item item, config={}
    @item_config[item].merge( config )
    self
  end
  # return the config value for a key for an item.
  # The keys are decided by the layout manager itself, such as :weight.
  # @param [Widget] item for which some attribute is required
  # @param [Symbol, String] the key
  def cget item, key
    return @item_config[item][key]
  end

  # set a value for an item and key
  # This is similar to configure_item which takes multiple pairs ( a hash).
  # I am seeing which will be more useful.
  def cset item, key, val
    @item_config[item][key] = val
    self
  end


  # Add a component, giving a weightage for height
  # @param [Integer, Float] give absolute weight, or fraction of layouts height
  # if wt is >= 1 then it is absolute height, else if between 0 and 1 ,
  # it is a percentage.
  def add_with_weight item, weight
    @components ||= []
    @components << item
    cfg[item][:weight] = weight
  end

  # remove given item from components list
  # This could happen if the item has been removed from the form
  def remove item
    @components.remove item
  end

  # clear the list of items the layout has.
  # Usually, the layout fills this list only once. However, if the list of items has changed
  # then this can be used to clear the list, so it is fetched again.
  def clear
    @components.clear
  end

  # does some initial common calculations that hopefully should be common across layouters
  # so that do_layout can be ovveridden while calling this.
  def _init_layout
    # when user gives a negative value, we recalc and overwrite so the need to save, for a redraw.
    @saved_width ||= @width
    @saved_height ||= @height

    lines = Ncurses.LINES - 1
    columns = Ncurses.COLS - 1
    if @height_pc
      @height = ((lines - @top_margin - @bottom_margin) * @height_pc).floor
    elsif @saved_height <= 0
      @height = lines - @saved_height - @top_margin - @bottom_margin
    end
    $log.debug "  layout height = #{@height} "
    if @width_pc
      @width = ((columns - @left_margin - @right_margin) * width_pc).floor
    elsif @saved_width <= 0
      # if width was -1 we have overwritten it so now we cannot recalc it. it remains the same
      @width = columns - @saved_width - @left_margin - @right_margin
    end
    $log.debug "  layout wid = #{@width} "
    # if user has not specified, then get all the objects
    @components ||= @form.widgets.select do |w| w.visible != false && !@ignore_list.include?(w.class.to_s.downcase); end
    $log.debug "  components #{@components.count} "
  end

  # This program lays out the widgets deciding their row and columm and height and weight.
  # This program is called once at start of application, and again whenever a RESIZE event happens.
  def do_layout
    $log.debug "  inside do_layout"
    _init_layout
    raise "please implement this in your subclass "
    c = @left_margin
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
        if wt.is_a? Integer
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
