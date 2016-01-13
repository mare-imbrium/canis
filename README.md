# Canis

wrapper over ruby ffi-ncurses library with essential components/controls only.

Canis has taken over the codebase of rbcurse. Canis is _not_ backward compatible with rbcurse.
Canis tries to simplify and refactor rbcurse. Canis also tries to standardize without causing too much change.

Applications that worked with rbcurse can be moved over to canis with some minor rework. An example is the `ri`
document reader, `rigel` which is based on the code of `ribhu` (which was rbcurse based).

## Installation

    gem install canis

## Usage

Until, we have better documentation, the best way to understand "canis" is to run the examples in the examples
folder. This gives a good idea of what the library does. Now you can open the source and get a feel of the 
structure of the code and what to study. One can also select an example that is close to the application one has in mind
and use the source as a starting point.

That said, all applications will use a `Window`, typically a `root_window` which covers the entire screen.
A Window contains a `Form`, which manages all the widgets or controls inside it. It manages traversal, as well
as calling events on them and setting their state.
So you may be interested in reading up on the controls you need such as a `Listbox` or a `Textpad` (a multiline readonly
textarea). Pay attention to the events that they handle such as row_selection, or entering and leaving a row, etc.

Of interest is also the `App` class which wraps some basic boilerplate code such as starting and shutting ncurses, setting
colors, and creating a root_window and its form.

Each widget has a large number of properties which can be changed at any time. Unfortunately these may not show up
in the generated documentation since they are not created using `attr_accessor`. It is necessary for a widget to be repainted whenever
a property is changed, thus `dsl_property` has been used in place of `attr_accessor`.

Canis (from rbcurse) provides all the small utilities you need for user interfaces such as dialogs to get a string from the user, confirmation dialogs, dialogs to display running text or exceptions, alerts, statuslines (like vim), an application header (like alpine). dialogs to select one or more rows from a list, menus etc. It borrows features from other text applications such as vim or emacs such as multiple key mappings (e.g., 'gg'). All multiline widgets have vim keybindings for traversal including numeric prefixes.

There are routines for accessing the OS, such as shelling out to the shell, or running a shell command and seeing the results in a Viewer, or editing a file externally in your EDITOR. These can be seen in the examples.

The key F1, provides access to a help system which explains the keys related to all the widgets. An application can and should add its help to this.


TODO: Write usage instructions here

Commonly used widgets and features:

- Textpad - to display non-editable multiline text. Text can be colored. 
- Listbox - identical to the textpad except that it allows single or multiple selection, and has 
    some extra events such as entering and leaving or row, and selection.
- Field - user entry of a single line of data.
- Label - readonly text
- Button - action oriented widget

Some optional application related widgets and features:

- Application Header : the first row of an application, containing application name, or program module name. Usually
  some of this text changes as a user navigates, such as line number in a list.
- Statusline : similar to vim's statusline with various bits of information, or status, and time.
- Dock : Identical to Alpine's key-action labels at the bottom of the screen informing the user of some actions
  that may be taken in the current context.

Lesser used widgets and features:

- Menubar: similar to the menubar on all applications with menu's and menuitems that trigger actions.
- Tree : heirarchical data structure
- Table : tabular data structure
- Other buttons: Checkbox, Radiobutton, Togglebutton
- TabbedPane  - useful for configuration screens
- Variable : based on TK's tkVariable, once used a lot internally in each widget, now used only in radiobuttons.
- Progress Bar - display progress of a process. See also progress_dialog.
- Textarea : editable multiline widget.

Some Issues with rbcurse:

Widgets required explicit coordinates. To that effect the App class allowed for `Stack` and `Flow` (idea borrowed from
the **Shoes** project. This works well, but all stack and flow information is lost when controls are placed meaning that a 
change in the window size (if user resizes) does not (and cannot) resize the application.

Canis has recently introduced Layout objects which have the ability to re-locate and resize objects when screen size
is changed, although these layout objects are quite simple compared to the earlier stack and flow. The earlier stack
and flow allowed any number of recursive layers.

Currently there are three layout objects:
- `StackLayout` : does only stacking of objects (vertical placement)
- `FlowLayout` : does only horizontal placement of obects
- `SplitLayout` : allows for multiple stacks and flows by means of splitting a split either horizontally or vertically
  and either placing an object in it, or splitting it further. 
These are based on an `AbstractLayout` which can be used to derive further layouts.

It is my intention to move usage over to these layouts since they are simpler, and allow for resizing (and to abandon
stacks and flows at some stage, unless people find them easier to use).

Issues canis would like to address:

- further simplifying of canis, but giving the user/programmer the ability of adding complexity at his level.
  I would like to do this before reaching 1.0.

- Keymapping. Currently, takes codes as integers, but i would have liked moving to strings as in vim.
  Currently we have to map `?\C-a.getbytes(0)` or `[?g, ?g]`, whereas a string would allow us to map `"<C-x>s"` 
  or `"<F1>"` or `"gg"`. The issue is that there is too much rework within the library since each widget uses integer mappings.
  Mapping and matching multiple keys would be a lot easier if stored internally as a string, currently multiple
  mappings require a hash or tree at each level.

For a tutorial of rbcurse, see:
https://github.com/rkumar/rbcurse-tutorial
This tutorial needs to be updated for canis. Although, canis has diverged/forked from rbcurse, but the basic principles are still the same.

There is some on-line documentation of classes at:
http://rubydoc.info/gems/canis/0.0.8/frames

## Contributing

- Please give suggestions on how to improve the documentation.
- Please give suggestions on how to improve canis.

1. Fork it ( https://github.com/[my-github-username]/canis/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
