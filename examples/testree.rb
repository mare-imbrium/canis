require 'canis'
require 'canis/core/widgets/tree'

if $0 == __FILE__
  $choice = ARGV[0].to_i || 1
class Tester
  def initialize
    acolor = $reversecolor
  end
  def run
    @window = Canis::Window.root_window
    @form = Form.new @window

    h = 20; w = 75; t = 3; l = 4
   #$choice = 1
    case $choice
    when 1
    root    =  TreeNode.new "ROOT"
    subroot =  TreeNode.new "subroot"
    leaf1   =  TreeNode.new "leaf 1"
    leaf2   =  TreeNode.new "leaf 2"

    model = DefaultTreeModel.new root
    #model.insert_node_into(subroot, root,  0)
    #model.insert_node_into(leaf1, subroot, 0)
    #model.insert_node_into(leaf2, subroot, 1)
    root << subroot
    subroot << leaf1 << leaf2
    leaf1 << "leaf11"
    leaf1 << "leaf12"

    root.add "blocky", true do
      add "block2"
      add "block3" do
        add "block31"
      end
    end
    Tree.new @form, :data => model, :row =>2, :col=>2, :height => 20, :width => 30

    when 2

      # use an array to populate
      # we need to do root_visible = false so you get just a list
    model  = %W[ ruby lua jruby smalltalk haskell scheme perl lisp ]
    Tree.new @form, :data => model, :row =>2, :col=>2, :height => 20, :width => 30

    when 3

      # use an Has to populate
      #model = { :ruby => %W[ "jruby", "mri", "yarv", "rubinius", "macruby" ], :python => %W[ cpython jython laden-swallow ] }
      model = { :ruby => [ "jruby", {:mri => %W[ 1.8.6 1.8.7]}, {:yarv => %W[1.9.1 1.9.2]}, "rubinius", "macruby" ], :python => %W[ cpython jython pypy ] }

    Tree.new @form, :data => model, :row =>2, :col=>2, :height => 20, :width => 30
    #when 4
    else
      Tree.new @form, :row =>2, :col=>2, :height => 20, :width => 30 do
        root "root" do
          branch "vim" do
            leaf "vimrc"
          end
          branch "ack" do
            leaf "ackrc"
            leaf "agrc"
          end
        end
      end

    end

    #
    help = "C-q to quit. <ENTER> to expand nodes. j/k to navigate. Pass command-line argument 1,2,3,4  #{$0} "
    Canis::Label.new @form, {:text => help, :row => 1, :col => 2, :color => :cyan}
    @form.repaint
    @window.wrefresh
    Ncurses::Panel.update_panels
    while((ch = @window.getchar()) != ?\C-q.getbyte(0))
      ret = @form.handle_key(ch)
      @window.wrefresh
      if ret == :UNHANDLED
        str = keycode_tos ch
        $log.debug " UNHANDLED #{str} by Vim #{ret} "
      end
    end

    @window.destroy

  end
end
include Canis
include Canis::Utils
# Initialize curses
begin
  # XXX update with new color and kb
  Canis::start_ncurses  # this is initializing colors via ColorMap.setup
  $log = Logger.new("canis14.log")
  $log.level = Logger::DEBUG
  n = Tester.new
  n.run
rescue => ex
ensure
  Canis::stop_ncurses
  p ex if ex
  puts(ex.backtrace.join("\n")) if ex
  $log.debug( ex) if ex
  $log.debug(ex.backtrace.join("\n")) if ex
end
end
