# NAME

Clay::UI - widget layer over Clay::XS: build a widget tree, lay it out, turn pointer input into events

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Clay::XS qw(sizing_grow sizing_fixed);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;
use Clay::UI::Role::Interaction::Pressable;

# Widget classes: Object::Pad classes composed from Clay::UI roles.
class My::Panel  :strict(params) :does(Clay::UI::Box) {}
class My::Label  :strict(params) :does(Clay::UI::Text) {}
class My::Button :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Pressable)
{}

# The widget tree.
my $root = My::Panel->new(
        id               => 'root',
        layout           => {
                sizing  => { width => sizing_grow(), height => sizing_grow() },
                padding => { left => 10, top => 10 },
        },
        background_color => [40, 50, 60, 255],
);
my $button = My::Button->new(
        id     => 'ok',
        layout => { sizing => { width => sizing_fixed(80), height => sizing_fixed(30) } },
);
$button->add_child(My::Label->new(text => 'OK', font_size => 16));
$button->on('OnHoverStart', sub ($event) { say 'over the button'; return });
$button->on('OnRelease',    sub ($event) { say 'clicked';         return });
$root->add_child($button);

# The UI that owns the tree and its Clay context.
my $ui = Clay::UI->new(width => 800, height => 600, root => $root);

# One call per frame: pointer input in, render commands out.
for my $down (0, 1, 0) {
        my $commands = $ui->render(pointer_state => { x => 20, y => 20, down => $down });
        for my $command (@$commands) {
                my $widget = $ui->widget_for($command->{userData});
                # draw $command; $widget is the widget that produced it
        }
}
```

# DESCRIPTION

`Clay::UI` is the widget layer of this distribution. You build a tree
of widgets (Perl objects that describe boxes and text), hand its root
widget to a `Clay::UI` object, and call ["render"](#render) once per frame.
`render` does three things:

- it turns the frame's pointer and scroll input into widget events
(["EVENTS"](#events)) and calls your listeners,
- it lays out the widget tree with Clay, and
- it returns Clay's render commands: an arrayref of hashes, each one a
rectangle, text, border or clipping instruction with a bounding box
(see ["RENDER COMMANDS" in Clay::XS](XS.md#render-commands)).

Nothing is drawn. A renderer (your code) draws the render commands with
whatever graphics library you use, and finds the widget behind each
command with ["widget\_for"](#widget_for).

A `Clay::UI` object owns one Clay context (a [Clay::XS](XS.md) context: one
independent Clay instance), the measure-text callback and the
interaction tracker ([Clay::UI::Interaction](UI/Interaction.md)), which holds which
widgets are hovered, pressed and focused. You never call `Clay_*`
functions yourself, with one exception: to animate transitions, call
`Clay_SetTransitionHandlers` right after `Clay::UI->new`, while
the new UI's context is current (see ["TRANSITIONS" in Clay::Manual](Manual.md#transitions)). The
low-level [Clay::XS](XS.md) API stays usable on its own.

For a guided introduction read [Clay::Manual](Manual.md); for ready-made
solutions see [Clay::Cookbook](Cookbook.md).

# WIDGET CLASSES

A _widget class_ is an [Object::Pad](https://metacpan.org/pod/Object%3A%3APad) class that composes roles from
this distribution. The roles provide the attributes, the children and
the behaviour; the class itself is often empty:

```perl
class My::Button :strict(params)
        :does(Clay::UI::Box)                             # an element with layout and style
        :does(Clay::UI::Role::Interaction::Pressable)    # OnPress / OnRelease
{}
```

There are two kinds of widget:

- element widgets

    Compose [Clay::UI::Role::Core::Element](UI/Role/Core/Element.md) (usually through
    [Clay::UI::Box](UI/Box.md), which adds layout, background, border, corner radius,
    floating and the public child methods). An element widget becomes one
    Clay element and may have children.

- text widgets

    Compose [Clay::UI::Role::Core::TextNode](UI/Role/Core/TextNode.md) (usually through
    [Clay::UI::Text](UI/Text.md)). A text widget becomes one Clay text element and has
    no children.

A grid is an element widget too: a class composing [Clay::UI::Grid](UI/Grid.md)
(a widget role like `Clay::UI::Box` and `Clay::UI::Text`) lays its
children out in rows and columns.

Further roles add behaviour: [Clay::UI::Role::Interaction::Hoverable](UI/Role/Interaction/Hoverable.md),
[Clay::UI::Role::Interaction::Pressable](UI/Role/Interaction/Pressable.md),
[Clay::UI::Role::Interaction::Focusable](UI/Role/Interaction/Focusable.md),
[Clay::UI::Role::Interaction::Disableable](UI/Role/Interaction/Disableable.md),
[Clay::UI::Role::Interaction::HasFocusOrder](UI/Role/Interaction/HasFocusOrder.md),
[Clay::UI::Role::Layout::HasScroll](UI/Role/Layout/HasScroll.md) (scroll containers)
and [Clay::UI::Role::Core::Preparable](UI/Role/Core/Preparable.md) (widgets that rebuild their
children right before the layout).

Every widget can listen to events with `on`
([Clay::UI::Role::Events::Listener](UI/Role/Events/Listener.md)); widgets that compose
[Clay::UI::Role::Events::Emitter](UI/Role/Events/Emitter.md) can also fire them. `Clay::UI::Box`,
[Clay::UI::Role::Interaction::Hoverable](UI/Role/Interaction/Hoverable.md),
[Clay::UI::Role::Interaction::Pressable](UI/Role/Interaction/Pressable.md),
[Clay::UI::Role::Interaction::Focusable](UI/Role/Interaction/Focusable.md) and
[Clay::UI::Role::Layout::HasScroll](UI/Role/Layout/HasScroll.md) compose it; `Clay::UI::Text`,
`Disableable` and `HasFocusOrder` do not.

The `class` keyword opens a new package, so `use Clay::XS qw(...)`
imports made at file scope are not visible inside the class block.

# KEYS AND VALIDATION

Clay::UI accepts the keys of Clay's structs in snake\_case
(`child_gap`, `layout_direction`, `background_color`) as well as in
the camelCase spelling Clay::XS uses (`childGap`, `layoutDirection`).
Widgets store every key in snake\_case, so readers return snake\_case
whatever spelling was set:

```perl
my $box = My::Box->new(layout => { childGap => 4 });
$box->layout;    # { child_gap => 4 }
```

Both spellings of the same key in one hash die where the value is set:

```text
Clay::UI: key 'childGap' in 'layout' is 'child_gap' in snake_case, which is already present in the same hash
```

The layout pass converts every key to camelCase before it passes a
widget's settings to Clay.

Widget attributes are validated where they are set: in the constructor
and in the accessor that writes them, not later in `render`. The rules
are exactly the ones Clay::XS applies when the value reaches Clay
(see `check_struct` in ["CHECKING STRUCTS" in Clay::XS](XS.md#checking-structs)). Errors name the attribute and the
snake\_case path inside it:

```text
Clay::UI: 'layout.padding.left' expected an integer in 0..65535, got '-5'
Clay::UI: 'layout' has unknown key 'chld_gap' (known keys: sizing, padding, child_gap, ...)
```

Attributes are copied when they are set and when they are read, so a
widget never shares a hash or array with your code: changing a hash
after passing it, or changing what a reader returned, does not change
the widget. Use the accessor to write a new value.

# HOW A FRAME WORKS

One call to ["render"](#render) is one _frame_. It runs these steps in order:

- 1. Pointer input

    The pointer position and button state (the `pointer_state` argument,
    or the previous frame's when it is omitted) go to Clay. Clay tests the
    position against the layout of the previous frame and lists the
    elements under the pointer, topmost floating element first. Clay::UI
    maps those elements back to widgets: these are the widgets _under the
    pointer_. A widget added to the tree can be hovered from the frame
    after the one that first lays it out.

- 2. Scrolling

    The `scroll_delta`, `enable_drag_scrolling` and `delta_time`
    arguments go to Clay. Wheel input moves the scroll container under the
    pointer at once. Drag scrolling moves it while the button is held and,
    after the release, keeps it gliding (momentum) for some frames. Wheel
    input has no momentum.

- 3. Events

    The widgets under the pointer, the button state and the scroll
    containers that moved go to the interaction tracker
    (["update" in Clay::UI::Interaction](UI/Interaction.md#update)). It updates the hovered, armed and
    pressed widgets first, then fires the events in this order: every
    `OnHoverStopped`, every `OnHoverStart`, `OnPress`, `OnRelease`,
    every `OnScroll`. Events of one kind fire in tree order (depth-first
    pre-order of the last layout). See ["EVENTS"](#events).

- 4. Preparations

    Every widget of this UI that called `request_prepare` since its last
    preparation gets its `prepare_layout` method called
    ([Clay::UI::Role::Core::Preparable](UI/Role/Core/Preparable.md)), so it can rebuild its children
    from its own state: parents before their descendants, widgets at the
    same depth in the order they asked. A widget that an earlier
    preparation detached is not prepared and stays queued. Preparations
    may request more preparations; after 100 rounds `render` gives up and
    dies.

- 5. Layout pass

    `render` records the current revision as ["laid\_out\_revision"](#laid_out_revision), then
    declares the widget tree to Clay: one Clay element per element widget,
    one text element per text widget, in tree order. Nothing may change the
    tree from here on. Clay computes the layout.

- 6. Result

    `render` returns the render commands. The frame is now the _last
    completed frame_: ["widget\_for"](#widget_for), ["bounding\_box"](#bounding_box), ["scroll\_state"](#scroll_state),
    ["scroll\_to"](#scroll_to) and the next frame's pointer test refer to it.

Listeners and preparations run in steps 3 and 4, while no Clay element
is open. They may change the tree, widget attributes and focus, and use
other Clay::UI objects; the changes show in this frame's layout. They
must not call `render` of the same Clay::UI.

If a listener dies, the remaining events still fire and the
preparations still run. If a `prepare_layout` dies, the other widgets
due in that round are still prepared; then preparation stops: later
rounds do not run, and the requests made during that round stay queued
for the next `render` (see ["prepare\_layout" in Clay::UI::Role::Core::Preparable](UI/Role/Core/Preparable.md#prepare_layout)).
In both cases the layout pass still runs, so the frame shows the scroll
input already applied and the changes made before the error. Then
`render` dies with the first error and the frame's render commands are
lost. The next
`render` works normally.

# CONSTRUCTOR

## new

```perl
my $ui = Clay::UI->new(
        root   => $root_widget,
        width  => 800,
        height => 600,
        # optional: memory_size, max_element_count,
        #           max_measure_text_cache_word_count, error_handler, measure_text
);
```

Creates a Clay::UI, its Clay context and its interaction tracker, and
makes `root` the root widget of this UI. Then every widget of the
root's subtree gets its
[tree\_changed](UI/Role/Layout/HasParent.md#tree_changed) call;
`new` dies with the first error of those hooks once all ran. The new
context is current when `new` returns. If `new` dies, it frees the
new context and makes the context that was current before current
again; the root is then free to become the root of another Clay::UI.

Unknown parameters die (`Unrecognised parameters for Clay::UI constructor`).

- root

    Required. The root widget: an object composing
    [Clay::UI::Role::Core::Element](UI/Role/Core/Element.md) or [Clay::UI::Role::Core::TextNode](UI/Role/Core/TextNode.md).
    It must have no parent and must not be the root of another Clay::UI;
    a widget that was removed from its parent may become a root. Read it
    back with ["root"](#root); it cannot be replaced, but the tree below it can
    change at any time. Dies with:

    ```text
    Clay::UI: 'root' must be a widget consuming Clay::UI::Role::Core::Element or TextNode
    Clay::UI: 'root' must not have a parent; the root is the top of its widget tree
    Clay::UI: 'root' is already the root of another Clay::UI
    ```

- width

    Required. The viewport width in layout units, a positive finite number.
    Change it later with ["width"](#width).

- height

    Required. The viewport height, like `width`. Both die with
    `Clay::UI: 'width' and 'height' must be positive finite numbers`.

- memory\_size

    Optional. Bytes of memory for the Clay context: an integer of at least
    `Clay_MinMemorySize()` for this UI's `max_element_count` and
    `max_measure_text_cache_word_count`, which is also the default. Dies with
    `Clay::UI: 'memory_size' must be an integer >= Clay_MinMemorySize() (...)`.

- max\_element\_count

    Optional. How many Clay elements this UI's context holds: a positive
    integer, default 8192 (Clay's default). Every element widget and every
    text widget is one element. Clay keeps two slots for itself, so one
    frame fits `max_element_count - 2` widgets (none for a count below 3).
    Clay also wraps at most this many text lines per frame, over all the
    text widgets it lays out; past that it silently stops wrapping. Each
    Clay::UI has its own count, whatever context is current when it is
    constructed. A larger count needs more memory (see `memory_size`).
    Dies with `Clay::UI: 'max_element_count' must be a positive integer`.
    Read it back with ["max\_element\_count"](#max_element_count).

- max\_measure\_text\_cache\_word\_count

    Optional. How many measured words Clay's text cache holds: an integer
    of at least 32, default twice `max_element_count` (Clay's default).
    Clay measures every text it lays out word by word and keeps the words
    of the last few frames, visible or not, so a frame whose texts have
    more words than this makes `render` die with
    `Clay::UI: the texts laid out in one frame have more words than max_measure_text_cache_word_count (16384) allows; ...`
    (default error handler). A larger count needs more memory (see
    `memory_size`). Dies with
    `Clay::UI: 'max_measure_text_cache_word_count' must be an integer >= 32`.
    Read it back with ["max\_measure\_text\_cache\_word\_count"](#max_measure_text_cache_word_count).

- error\_handler

    Optional. A coderef Clay calls as `$handler->($error, $userdata)`
    when it reports an error; `$error` is a hashref with `errorType` (a
    `CLAY_ERROR_TYPE_*` constant) and `errorText`. The default handler
    dies with `Clay error: $error->{errorText}`, which makes `render`
    die (see ["ERRORS FROM CALLBACKS" in Clay::XS](XS.md#errors-from-callbacks)); a handler that returns
    lets the frame continue. Dies with `Clay::UI: 'error_handler' must be a coderef`.

    With the default handler, a tree with more widgets than
    `max_element_count` allows makes `render` die with a message that
    names `max_element_count` (see ["render"](#render)) instead of the error Clay
    reports for it (Clay drops the extra elements without a word and then
    reports elements it could not close). A handler of your own receives
    Clay's error unchanged.

    The handler runs inside Clay and must not use any Clay::UI object (see
    ["What a callback may do" in Clay::XS](XS.md#what-a-callback-may-do)).

- measure\_text

    Optional. A coderef Clay calls as `$measure->($text, $config,
    $userdata)` to measure a piece of text; it returns `{ width =>
    $w, height => $h }`. `$config` is the text element's configuration
    with camelCase keys (`fontSize`, `fontId`, `letterSpacing`, ...).
    The default is a monospace estimate: `width = length($text) *
    fontSize`, `height = fontSize`, with a `fontSize` of 16 when it is 0
    or missing. Dies with `Clay::UI: 'measure_text' must be a coderef`.
    Change it later with ["measure\_text"](#measure_text).

    The callback runs inside Clay during the layout pass and must not use
    any Clay::UI object. Inside it:

    - `render` dies (`Clay::UI::render: called while this Clay::UI is already rendering`).
    - The writers `width($w)`, `height($h)` and `measure_text($coderef)`
    die (`Clay_SetCurrentContext: cannot be called from inside a Clay callback`);
    the readers `width`, `height` and `measure_text` work.
    - `bounding_box`, `scroll_state` and `scroll_to` die with the same
    message for a widget the last completed frame laid out, because they
    ask Clay; for a widget it did not lay out they return undef without
    asking Clay.

    If the callback lets such an error escape, the outer `render` dies
    with it after the layout pass.

# METHODS

## root

```perl
my $root = $ui->root;
```

Returns the root widget passed to ["new"](#new). Read-only.

## max\_element\_count

```perl
my $count = $ui->max_element_count;
```

Returns the `max_element_count` passed to ["new"](#new) (8192 by default).
Read-only.

## max\_measure\_text\_cache\_word\_count

```perl
my $words = $ui->max_measure_text_cache_word_count;
```

Returns the `max_measure_text_cache_word_count` passed to ["new"](#new)
(twice `max_element_count` by default). Read-only.

## width

```perl
my $width = $ui->width;
$ui->width(1024);
```

Reads or writes the viewport width. A write takes one positive finite
number, passes it to Clay (`Clay_SetLayoutDimensions`), bumps the
revision ([Clay::UI::Revision](UI/Revision.md)) and returns the new width; the next
["render"](#render) lays out at the new size. A refused value changes nothing.
Dies with `Clay::UI: width must be a positive finite number` or
`Clay::UI: width takes one value`.

## height

```perl
my $height = $ui->height;
$ui->height(768);
```

Reads or writes the viewport height, exactly like ["width"](#width).

## measure\_text

```perl
my $measure = $ui->measure_text;
$ui->measure_text(sub ($text, $config, $userdata) { ... });
```

Reads or replaces the measure-text callback (see `measure_text` under
["new"](#new)). A write takes one coderef, passes it to Clay, clears Clay's
cache of measurements made by the old callback
(`Clay_ResetMeasureTextCache`), bumps the revision and returns the new
callback. Dies with `Clay::UI: measure_text must be a coderef` or
`Clay::UI: measure_text takes one value`.

## render

```perl
my $commands = $ui->render(%args);
```

Runs one frame (see ["HOW A FRAME WORKS"](#how-a-frame-works)): processes the pointer and
scroll input, fires the resulting events, prepares the widgets that
asked for it, lays out the widget tree and returns the render commands
as an arrayref of hashes (see ["RENDER COMMANDS" in Clay::XS](XS.md#render-commands)). Each
command's `userData` identifies the widget that produced it (see
["widget\_for"](#widget_for)).

All arguments are named and optional:

- pointer\_state

    ```perl
    pointer_state => { x => 120, y => 80, down => 1 }
    ```

    The pointer for this frame: a hashref with finite numbers `x` and `y`
    (layout units, origin at the top left of the viewport) and `down`, a
    true value while the button is held (default false). No other keys.
    When omitted (or undef), the pointer state of the previous frame is
    used again. A change of `down` from false to true is a press, from
    true to false a release (see ["EVENTS"](#events)). Until the first
    `pointer_state`, the pointer is up and Clay tests no position, so
    nothing is under it and no press is reported.

- delta\_time

    ```perl
    delta_time => 0.016
    ```

    Seconds since the previous frame, a finite number >= 0, default 0.
    Clay uses it for the momentum after drag scrolling and for transitions.

- scroll\_delta

    ```perl
    scroll_delta => { x => 0, y => -1 }    # or [0, -1]
    ```

    Wheel input for this frame, as `{ x => ..., y => ... }` (both keys
    required, no others) or `[$x, $y]`, both finite numbers; default
    `[0, 0]`. Clay multiplies the delta by 10 and adds it to the scroll
    position of the scroll container under the pointer (the innermost one
    when containers are nested), on each axis that container can scroll (its
    content is larger than its viewport); the result is clamped to the
    content. A negative `y` scrolls down, revealing what is below:
    `scroll_delta => { x => 0, y => -4 }` scrolls the container 40
    layout units down: the content moves up, and its `position` in
    ["scroll\_state"](#scroll_state) goes from `0` to `-40`. A scroll container is a
    widget composing [Clay::UI::Role::Layout::HasScroll](UI/Role/Layout/HasScroll.md). Wheel input has
    no momentum: the container stops where the delta puts it, and wheel
    input also stops a glide left over from drag scrolling.

- enable\_drag\_scrolling

    ```perl
    enable_drag_scrolling => 1
    ```

    A plain boolean, default false. When true, pressing and dragging inside
    a scroll container scrolls it, as on a touch screen. After the release
    the container keeps moving with momentum for some frames, slowing down
    each frame.

`render` dies, with the frame discarded, in these cases:

- A bad argument, before anything happens:
`Clay::UI::render: unknown argument(s)`,
`... 'pointer_state' must be a hashref`,
`... unknown pointer_state key(s)`,
`... pointer_state 'x' must be a finite number`,
`... pointer_state 'down' must be a plain boolean value`,
`... 'delta_time' must be a finite number >= 0`,
`... unknown scroll_delta key(s)`, `... 'scroll_delta' must be ...`,
`... 'enable_drag_scrolling' must be a plain boolean value`.
- `render` is called while the same Clay::UI is rendering, for example
from an event listener, a `prepare_layout` or the measure-text
callback: `Clay::UI::render: called while this Clay::UI is already rendering`.
- An event listener died. All events of the frame fire, the preparations
and the layout pass run, then `render` dies with the first listener
error.
- A `prepare_layout` died: the other preparations of that round still
run, later rounds do not (see ["HOW A FRAME WORKS"](#how-a-frame-works)), the layout pass
runs, then `render` dies with the first error of the frame. Or preparations kept requesting new
ones: `Clay::UI: widgets kept requesting preparation; 100 rounds of prepare_layout did not settle`.
- Clay reported an error and the error handler died. With the default
handler this is `Clay error: ...`, for example when two widgets have
the same `id`
(`Clay error: An element with this ID was already previously declared during this layout.`).
- The tree has more widgets than `max_element_count` allows (default
error handler only):
`Clay::UI: the widget tree has more elements than max_element_count (8192) allows: ...`.
- The texts laid out in the frame have more words than
`max_measure_text_cache_word_count` allows (default error handler
only):
`Clay::UI: the texts laid out in one frame have more words than max_measure_text_cache_word_count (16384) allows; ...`.
- The measure-text callback died: `render` dies with its error.
- A widget class produced settings Clay::XS rejects. Attributes are
validated when they are set, so this happens only when a widget class
builds settings of its own: a `Clay::XS::StructError` (see
["STRUCT ERRORS" in Clay::XS](XS.md#struct-errors)) such as
`Clay_ElementDeclaration.layout.padding.left: expected an integer in 0..65535, got '-3'`,
a key collision between a widget class's own camelCase key and a
stored snake\_case one (`Clay::UI: key '...' camelizes to ...`), or
`Clay::UI: widget ... set user_data in its config` (see ["NOTES"](#notes)).

When a listener error and a layout error happen in the same frame,
`render` dies with the listener error and appends
`(the layout pass also failed: ...)` to it (when the error is a
string).

After any of these, Clay stays usable and the next `render` works
once the cause is fixed. Which frame counts as the last completed frame
depends on the case:

- After a bad argument, a nested `render` or a failed layout pass (a
Clay error, too many widgets, a dying measure-text callback, rejected
settings), the last completed frame is unchanged.
- After a listener error or a preparation error (a dying
`prepare_layout`, or the 100 rounds) without a layout error,
the layout pass completed: that frame becomes the last completed frame
for ["widget\_for"](#widget_for), ["bounding\_box"](#bounding_box), ["scroll\_state"](#scroll_state) and the next
frame's pointer test, even though its render commands were discarded.

## widget\_for

```perl
my $widget = $ui->widget_for($command->{userData});
```

Returns the widget that produced a render command, given the command's
`userData`. Returns `undef` when `$user_data` is undef, 0 or unknown,
or when the widget has been freed since. Lookups use the last completed
frame. Not every command has a widget: Clay gives `SCISSOR_END`
commands a `userData` of 0, so `widget_for` returns `undef` for them.

```perl
for my $command (@$commands) {
        my $widget = $ui->widget_for($command->{userData}) or next;
        # choose how to draw by ref($widget), read its attributes, ...
}
```

## laid\_out\_revision

```perl
my $shown = $ui->laid_out_revision;
```

Returns the revision ([Clay::UI::Revision](UI/Revision.md)) at which the last
`render` started its layout pass, or `undef` before the first
`render`. Every change up to that revision, including the changes the
frame's listeners and preparations made, is part of that frame. A
renderer that skips unchanged frames remembers this value when it
draws a frame, and after each later `render` draws again only when
`laid_out_revision` differs from the remembered value:

```perl
my $drawn;    # the laid_out_revision of the last frame drawn

my $commands = $ui->render(%input);
if (!defined $drawn || $drawn != $ui->laid_out_revision) {
        draw($commands);
        $drawn = $ui->laid_out_revision;
}
```

A running transition (["TRANSITIONS" in Clay::Manual](Manual.md#transitions)) counts as a change
too: every frame that animates an element moves the revision, so the
loop above redraws until the animation is over.

## bounding\_box

```perl
my $box = $ui->bounding_box($widget);    # { x, y, width, height } or undef
```

Returns where the last completed frame placed an element widget, as a
new hashref with `x`, `y`, `width` and `height` in layout units (the
same numbers as the `boundingBox` of its render commands). Scrolling is
included, so a widget scrolled out of view lies outside its scroll
container. Returns `undef` for a widget that frame did not lay out (one
added since, one removed, a text widget, or a widget of another UI).

Text widgets have no bounding box of their own: use the `boundingBox`
of their `TEXT` render commands (["widget\_for"](#widget_for) maps each command back
to its text widget).

The box is the size Clay gave the widget, which can be smaller than
its sizing asks for: when the children of a parent do not fit into
it, Clay shrinks them, down to their minimum size, and
`bounding_box` reports the shrunk size. A parent that clips an axis
(a scroll container scrolling that way) does not shrink its children
along that axis.

Dies when `$widget` is not an object: `Clay::UI: expected a widget, got ...`.

## scroll\_state

```perl
my $state = $ui->scroll_state($scroll_box);
# { position => { x, y }, viewport => { width, height }, content => { width, height } }
```

Returns the scroll data of a scroll container (a widget composing
[Clay::UI::Role::Layout::HasScroll](UI/Role/Layout/HasScroll.md)) as a new hashref:

- position

    Clay's scroll position: `0` at the top and left, negative when the
    content is scrolled down or right. Reflects every scroll since the last
    frame, including ["scroll\_to"](#scroll_to).

- viewport

    The size of the visible area.

- content

    The size of everything inside the container.

Returns `undef` when the last completed frame did not lay the
container out. Dies for anything that is not a scroll container:
`Clay::UI: ... is not a scroll container (it does not compose Clay::UI::Role::Layout::HasScroll)`.

During the layout pass (from a `contribute_` method, say) it returns
the same: the position as this frame lays it out (the wheel, drag and
momentum scrolling of the frame applied) and the viewport and content
of the last completed frame.

## scroll\_to

```perl
$ui->scroll_to($scroll_box, { y => -12 });         # 12 units down
$ui->scroll_to($scroll_box, { x => 0, y => 0 });   # back to the top left
```

Moves a scroll container to a scroll position (in the sense of
`position` under ["scroll\_state"](#scroll_state)). Each axis is clamped to the range
from `0` down to `viewport - content` (or `0` when the content fits);
an axis left out keeps its position. Returns the position as Clay now
holds it, a new hashref `{ x => ..., y => ... }` (Clay keeps
single-precision floats, so a large position may come back rounded),
or `undef` when the last completed frame did not lay the container out
(then nothing moves). The
next `render` shows the new position. The move counts as a change for
[Clay::UI::Revision](UI/Revision.md). It fires no `OnScroll` (that event reports only the
scrolling Clay does inside `render`), and it stops momentum: a glide
started by drag scrolling ends at the new position. A position equal to
the current one still ends a glide and counts as a change for the
revision; it does not prepare the container (see below).

A container that composes [Clay::UI::Role::Core::Preparable](UI/Role/Core/Preparable.md) is
prepared before the next layout pass when its position changed (its
`request_prepare` is called), so a container that builds its children
for the position it shows can follow a move made from code, or from a
listener in the same frame.

Dies with
`Clay::UI: scroll_to needs a position { x => ..., y => ... }`,
`Clay::UI: scroll_to got unknown position key(s)`,
`Clay::UI: scroll_to position 'y' must be a finite number`, and for a
widget that is not a scroll container (as ["scroll\_state"](#scroll_state)).

## interaction

```perl
my $interaction = $ui->interaction;
```

Returns this UI's interaction tracker, a [Clay::UI::Interaction](UI/Interaction.md). It
holds the hovered, armed, pressed and focused widgets and fires the
pointer and focus events. Common uses:

```perl
# widgets under the pointer at the last frame
my $widgets = $ui->interaction->under_pointer;
$ui->interaction->set_focused_widget($input);    # move the focus
$ui->interaction->focus_next;                    # Tab
$ui->interaction->update(over => [$button], down => 1);   # synthetic input
```

# EVENTS

`render` fires the pointer events below at widgets; focus events come
from the focus methods of [Clay::UI::Interaction](UI/Interaction.md). Listen with `$widget->on($name, sub ($event) { ... })`
([Clay::UI::Role::Events::Listener](UI/Role/Events/Listener.md)). An event that _bubbles_ is then
offered to the widget's parent, its parent's parent and so on, as its
bubble mode allows ([Clay::UI::Enum::Bubble](UI/Enum/Bubble.md)). With `IF_CONTINUE`, an
ancestor sees the event only when every listener of the widget below
returned `Clay::UI::Enum::Result->CONTINUE` (or the widget has no
listener for it).

**A listener that returns nothing stops the event.** An empty `return`,
`undef`, or the value of the last statement (such as the return value
of `say`) all count as `Clay::UI::Enum::Result->HANDLED`; only
`CONTINUE` lets the event bubble on ([Clay::UI::Enum::Result](UI/Enum/Result.md)):

```perl
$button->on('OnPress', sub ($event) {
        highlight($event->current_target);
        return Clay::UI::Enum::Result->CONTINUE;    # the card around the button sees it too
});
```

## OnHoverStart

Fires at a [Clay::UI::Role::Interaction::Hoverable](UI/Role/Interaction/Hoverable.md) widget in the frame
it comes under the pointer. Does not bubble: every hovered widget,
nested ones included, gets its own event. See
[Clay::UI::Events::OnHoverStart](UI/Events/OnHoverStart.md).

## OnHoverStopped

Fires at a hovered widget in the frame it is no longer under the
pointer, and at once, during the removal, when a hovered widget is
removed from the tree. Does not bubble. See
[Clay::UI::Events::OnHoverStopped](UI/Events/OnHoverStopped.md).

## OnPress

Fires when the pointer goes down, at exactly one
[Clay::UI::Role::Interaction::Pressable](UI/Role/Interaction/Pressable.md): the enabled Pressable under
the pointer that is drawn on top. A button inside a pressable card gets
it, not the card; of two overlapping siblings (such as the children of
a `CLAY_BACK_TO_FRONT` container) the later one gets it; a Pressable
in a floating element beats every Pressable below that element. Every
enabled Pressable under the pointer becomes _armed_. Bubbles with
`IF_CONTINUE`. The precise rule is under
["PRESS AND RELEASE" in Clay::UI::Interaction](UI/Interaction.md#press-and-release). See
[Clay::UI::Events::OnPress](UI/Events/OnPress.md).

## OnRelease

Fires when the pointer goes up, at the topmost _armed_ Pressable still
under the pointer, chosen like the target of `OnPress`: a completed
click. Every release disarms all Pressables, so a press that started
elsewhere, or one dragged off every armed widget, ends without
`OnRelease`. Bubbles with `IF_CONTINUE`. See
[Clay::UI::Events::OnRelease](UI/Events/OnRelease.md).

A Pressable is _pressed_ (`is_pressed`, the derived `pressed` state)
while it is armed, enabled and under the pointer and the button is
down.

## OnScroll

Fires at a scroll container ([Clay::UI::Role::Layout::HasScroll](UI/Role/Layout/HasScroll.md))
whose scroll position changed in this frame through wheel input, drag
scrolling or the momentum that follows drag scrolling; `delta_x` and `delta_y` say how far. Such a
change also bumps the revision. Bubbles with `IF_CONTINUE`. See
[Clay::UI::Events::OnScroll](UI/Events/OnScroll.md).

## OnFocus

Fires at a [Clay::UI::Role::Interaction::Focusable](UI/Role/Interaction/Focusable.md) that receives the
focus through `set_focused_widget`, `focus_next` or
`focus_previous`. `render` never moves the focus. Bubbles with
`IF_CONTINUE`. See [Clay::UI::Events::OnFocus](UI/Events/OnFocus.md).

## OnBlur

Fires at the widget that loses the focus: when the focus moves
elsewhere or is cleared, when the focused widget is removed from the
tree, is disabled, or cannot take the focus any more. Bubbles with
`IF_CONTINUE`. See [Clay::UI::Events::OnBlur](UI/Events/OnBlur.md).

# CLAY CONTEXTS

Clay has one _current_ context per process. Every method of
Clay::UI that talks to Clay (`new`, `render`, the `width`,
`height` and `measure_text` writers, `bounding_box`,
`scroll_state`, `scroll_to`) first makes this UI's context current
and leaves it current. Several Clay::UI objects can coexist; code that
mixes Clay::UI with direct [Clay::XS](XS.md) calls must set the context it
needs with `Clay_SetCurrentContext` before its own calls.

# NOTES

- Back-references in render commands

    The layout pass sets each element's `userData` to a number that
    identifies its widget, so ["widget\_for"](#widget_for) can map a render command back
    to the widget. A widget class must therefore not set `user_data` (or
    `userData`) in its settings; `render` dies with
    `Clay::UI: widget ... set user_data in its config` if one does.

- Scroll containers

    For a scroll container without an explicit `child_offset`, the layout
    pass sets Clay's `childOffset` to the container's current scroll
    offset, so its children follow the scroll position. A `clip` setting
    from any other widget clips, but does not scroll.

- Widgets without an id

    A widget without an `id` gets one derived from its position below the
    nearest ancestor that has one; see
    ["resolve\_id" in Clay::UI::Role::Core::Element](UI/Role/Core/Element.md#resolve_id). User ids must not start
    with `anon:`.

- Lifetime

    The lookup tables behind ["widget\_for"](#widget_for) and the interaction tracker
    hold widgets weakly. The Clay::UI object keeps its root widget, and so
    the whole tree, alive. The tracker and the widgets refer to the
    Clay::UI weakly; the methods of [Clay::UI::Interaction](UI/Interaction.md) that need it
    die once it is gone.

- Revision

    Every setter that changes what a frame lays out or draws bumps the
    process-wide revision ([Clay::UI::Revision](UI/Revision.md)): widget attributes,
    children, user states, this object's `width`, `height` and
    `measure_text`, and the hovered, armed, pressed and focused widgets.
    Reading never bumps it. Widget classes that keep state of their own
    call `mark_changed` (["mark\_changed" in Clay::UI::Role::Core::Element](UI/Role/Core/Element.md#mark_changed)).

# SEE ALSO

[Clay::Manual](Manual.md) (user guide), [Clay::Cookbook](Cookbook.md) (recipes),
[Clay::UI::Interaction](UI/Interaction.md), [Clay::UI::Revision](UI/Revision.md), [Clay::UI::Box](UI/Box.md),
[Clay::UI::Text](UI/Text.md), [Clay::UI::Grid](UI/Grid.md),
[Clay::UI::Role::Core::Element](UI/Role/Core/Element.md), [Clay::XS](XS.md), [Clay::XS::Structs](XS/Structs.md).

# LICENSE

Released under the same zlib/libpng license as Clay itself. See
`src/clay/LICENSE.md` for the upstream notice.
