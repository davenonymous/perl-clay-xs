# Clay::XS and Clay::UI

Perl bindings for [Clay](https://github.com/nicbarker/clay) v0.14, a
header-only C UI layout library. The distribution has two layers:

- `Clay::XS`, the low-level binding. Every public `Clay_*` function of
  clay.h (plus `Clay_SetExternalScrollHandlingEnabled`, which upstream
  implements but does not declare) and the internal `Clay__*` functions
  the C macros expand to are exposed under their exact C names. The one
  exception is `Clay_CreateArenaWithCapacityAndMemory`: `Clay_Initialize`
  takes the arena size and allocates the arena itself. The C macros
  (`CLAY()`, `CLAY_TEXT()`, ...) use C control-flow tricks and have no
  Perl equivalent; call the open / configure / close primitives they
  expand to instead.
- `Clay::UI`, an idiomatic layer built from Object::Pad roles: you
  compose widget classes from roles, build a tree of widgets, and a
  `Clay::UI` object lays it out and turns pointer input into widget
  events.

Neither layer draws anything: a layout pass returns an array of render
commands for your renderer.

## Build

```sh
perl Makefile.PL
make
make test
```

Requirements:

- Perl 5.22 or later
- A C99 compiler accepting GCC-style flags (GCC or Clang; `Makefile.PL`
  passes `-std=c99 -Wall -Wextra`)
- The `patch` tool (applies `patches/*.patch` to the vendored header)
- ExtUtils::MakeMaker 7.12+
- Object::Pad 0.800+ and Object::PadX::Enum (for `Clay::UI`)
- Test2::V0 and JSON::PP (tests only)

Clay's header is vendored as `src/clay/clay.h.orig`; there are no
external runtime dependencies. At build time `make` applies the patches
under `patches/` in order - cross-tree sizing groups (used by
`Clay::UI::Grid`), flow layout (`CLAY_LEFT_TO_RIGHT_WRAP`) and stack
layout (`CLAY_BACK_TO_FRONT`) - and writes the result to `src/clay/clay.h` (generated, gitignored).

## Clay::XS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Clay::XS qw(:all);

my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 800, height => 600 },
    sub ($err, $userdata) { die "Clay error: $err->{errorText}\n" },
);

Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
    return {
        width  => length($text) * $config->{fontSize},
        height => $config->{fontSize},
    };
});

Clay_BeginLayout();

Clay__OpenElementWithId(Clay_GetElementId('root'));
Clay__ConfigureOpenElement({
    layout          => { sizing => { width => sizing_grow(), height => sizing_grow() }, padding => padding_all(16) },
    backgroundColor => [240, 240, 240, 255],
});
Clay__OpenTextElement('Hello', { fontSize => 16, textColor => [0, 0, 0, 255] });
Clay__CloseElement();

my $render_commands = Clay_EndLayout();
for my $command (@$render_commands) {
    printf "type %d at (%g, %g)\n", $command->{commandType}, @{ $command->{boundingBox} }{qw(x y)};
}
```

Structs are hashes keyed by the exact C field names (`backgroundColor`,
`layoutDirection`, ...); colours, vectors and dimensions also accept
arrayrefs. The POD of `Clay::XS` documents contexts, frames, callbacks,
the render-command hashes and the mapping from every C macro to Perl.

Input is checked where it crosses into Clay: misuse (no current
context, unbalanced open/close, configuring an element twice, pointer
input in the middle of a frame or after one that was never finished, a
wrong-typed or out-of-range struct field) croaks with a descriptive
message instead of crashing inside Clay. An exception thrown by one of your callbacks while Clay is
running is re-thrown once Clay returns - by `Clay_EndLayout` for the
measure, error and transition callbacks, by `Clay_SetPointerState` for
hover callbacks. Strings are characters in and out (UTF-8 inside
Clay), and the binding copies them, so you never keep them alive for
Clay.

See `examples/01-minimal.pl` and `examples/02-sidebar-demo.pl` for more.

## Clay::UI

Widgets are Object::Pad classes you declare by composing roles. The
distribution ships three widget roles - `Clay::UI::Box`,
`Clay::UI::Text` and `Clay::UI::Grid` - and the mixin roles they are
made of, so a widget class is usually one line:

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Clay::XS qw(:all);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;

class My::Box  :strict(params) :does(Clay::UI::Box)  {}
class My::Text :strict(params) :does(Clay::UI::Text) {}

my $root = My::Box->new(
    id               => 'root',
    layout           => { sizing => { width => sizing_grow(), height => sizing_grow() }, padding => padding_all(16) },
    background_color => [240, 240, 240, 255],
);
$root->add_child(My::Text->new(text => 'hello', font_size => 18, text_color => [0, 0, 0, 255]));

my $ui = Clay::UI->new(width => 800, height => 600, root => $root);
my $render_commands = $ui->render;

for my $command (@$render_commands) {
    my $widget = $ui->widget_for($command->{userData});
    printf "%s from %s\n", $command->{commandType}, ref $widget;
}
```

Attributes use `snake_case` keys (`background_color`, `layout_direction`);
Clay::UI converts them to Clay's field names. They are validated where
they are set - in the constructor and in the read/write accessors - so a
misspelled key, a wrong-typed value or an out-of-range number dies at that
point, with the same rules Clay::XS applies (`check_struct`). `:strict(params)`
on your classes makes misspelled constructor parameters die too.
`widget_for` maps a render command back to the widget that produced it.

### Roles

- `Clay::UI::Role::Core::Element` - the base of every element widget:
  optional `id`, `children` (a copy), `to_config`. Widgets without an
  `id` get one derived from their position (user ids must not start
  with `anon:`, the prefix of the derived ids).
- `Clay::UI::Role::Core::Container` - an Element with `add_child`,
  `remove_child`, `remove_children_with` and `clear_children`. A widget
  can be attached whenever it has no parent: removed widgets can be
  added again, attaching one that still has a parent dies.
- `Clay::UI::Role::Core::TextNode` - the base of text leaves.
- `Clay::UI::Role::Core::Stateful` - an Element that requires an `id`.
- `Clay::UI::Role::Core::Preparable` - a widget that brings its subtree
  up to date once per frame: `request_prepare` queues it, and `render`
  calls its `prepare_layout` after the frame's events and before the
  layout pass, however many changes came before.
- Style and layout mixins: `HasLayout`, `HasBackground`, `HasBorder`,
  `HasCornerRadius`, `HasFloating`, `HasSizingGroup` (every Element),
  `HasScroll` (a Stateful Container that clips and scrolls its
  children), and the marker `GridCell` (`Clay::UI::Grid` uses such a
  widget as a cell as it is instead of wrapping it).
- Interaction: `Hoverable`, `Pressable` (implies Hoverable),
  `Focusable`, `HasFocusOrder` for custom focus traversal, and
  `Disableable` (a `disabled` flag: a disabled widget takes no focus and
  is never pressed).
- Events: `Listener` (every widget can listen) and `Emitter` (widgets
  that fire events: Box and every Hoverable, Pressable, Focusable and
  HasScroll widget).

`Clay::UI::Box` is Container + HasLayout + HasBackground + HasBorder +
HasCornerRadius + HasFloating + Emitter. `Clay::UI::Text` is a TextNode
with the text attributes. `Clay::UI::Grid` is described below. Each
role's POD lists its attributes. A widget class may also define its own
`contribute_<slice>` methods to add to the element configuration.

### Pointer input and events

Pass the pointer to `render`; it fires the widget events before it lays
out the frame, so listeners may change the tree:

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Clay::XS qw(:all);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Enum::Result;
use Clay::UI::Role::Core::Stateful;
use Clay::UI::Role::Interaction::Pressable;

class My::Box :strict(params) :does(Clay::UI::Box) {}
class My::Button :strict(params)
    :does(Clay::UI::Box)
    :does(Clay::UI::Role::Core::Stateful)
    :does(Clay::UI::Role::Interaction::Pressable)
{}

my $root   = My::Box->new(id => 'root', layout => { padding => padding_all(10) });
my $button = My::Button->new(
    id               => 'ok',
    layout           => { sizing => { width => sizing_fixed(80), height => sizing_fixed(30) } },
    background_color => [60, 120, 200, 255],
);
$root->add_child($button);

$button->on('OnPress',   sub ($event) { say 'pressed at ', $event->x, ',', $event->y; return });
$button->on('OnRelease', sub ($event) {
    say 'clicked ', $event->target->id;
    return Clay::UI::Enum::Result->HANDLED;    # do not bubble to the ancestors
});

my $ui = Clay::UI->new(width => 400, height => 300, root => $root);
$ui->render;                                                   # first layout
$ui->render(pointer_state => { x => 30, y => 20, down => 1 }); # OnPress
$ui->render(pointer_state => { x => 30, y => 20, down => 0 }); # OnRelease
say 'pressed now: ', $button->is_pressed;
```

The events:

- `OnHoverStart` / `OnHoverStopped` - a Hoverable comes under the
  pointer or leaves it (or is removed while hovered). They do not
  bubble: every hovered widget gets its own.
- `OnPress` - when the pointer goes down, on exactly one widget: the
  Pressable under the pointer that is drawn on top (the innermost of
  nested ones, the later of overlapping siblings).
- `OnRelease` - when the pointer goes up, on the topmost Pressable
  still under the pointer that the press started over (a press arms
  every Pressable under the pointer, so dragging from a button onto the
  pressable card around it and releasing there gives the card its
  OnRelease). Releasing over no such widget fires nothing.
- `OnScroll` - a HasScroll widget's scroll position changed; carries
  `delta_x` / `delta_y`.
- `OnFocus` / `OnBlur` - focus moved, through the tracker's
  `set_focused_widget`, `focus_next` / `focus_previous`, or the removal
  of the focused widget.
  `render` never changes focus.

`OnPress` and `OnRelease` bubble to the ancestors while listeners return
`Clay::UI::Enum::Result->CONTINUE`. Bubbling is a property of the event
(`Clay::UI::Enum::Bubble`: `ALWAYS`, `IF_CONTINUE`, `NEVER`). If a
listener dies, the frame's remaining events still fire, the layout pass
still runs, and then `render` dies with the first error (the frame's
render commands are discarded). Hover, press and focus state lives in
the UI's interaction tracker (`$ui->interaction`, `Clay::UI::Interaction`),
which `render` feeds every frame and which also takes synthetic input.
The `is_hovered` / `is_pressed` / `is_focused` readers and the derived,
read-only `hovered`, `pressed` and `focused` states
(`Clay::UI::Role::Style::HasStates`) ask it. A hovered
widget removed from the tree gets `OnHoverStopped` at once. `Clay::UI`'s
POD (section POINTER EVENTS) has the details.

### Scrolling

A widget composing `Clay::UI::Role::Layout::HasScroll` clips its
children and scrolls them with the wheel input you pass to `render`:

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Clay::XS qw(:all);
use Clay::UI;
use Clay::UI::Text;
use Clay::UI::Role::Layout::HasScroll;
use Clay::UI::Role::Layout::HasLayout;

class My::Text :strict(params) :does(Clay::UI::Text) {}
class My::LogView :strict(params)
    :does(Clay::UI::Role::Layout::HasScroll)
    :does(Clay::UI::Role::Layout::HasLayout)
{}

my $log = My::LogView->new(
    id     => 'log',
    layout => {
        sizing           => { width => sizing_fixed(200), height => sizing_fixed(100) },
        layout_direction => CLAY_TOP_TO_BOTTOM,
    },
);
$log->add_child(My::Text->new(text => "line $_", font_size => 16)) for 1 .. 20;
$log->on('OnScroll', sub ($event) { say 'scrolled by ', $event->delta_y; return });

my $ui = Clay::UI->new(width => 400, height => 300, root => $log);
$ui->render;
$ui->render(pointer_state => { x => 50, y => 50 }, scroll_delta => { x => 0, y => -3 }, delta_time => 0.016);
```

The geometry of the last completed frame is available between renders:
`$ui->scroll_state($log)` returns a scroll container's `position`,
`viewport` and `content` size, `$ui->scroll_to($log, { y => -40 })`
moves it (kept within its content; the next `render` shows it), and
`$ui->bounding_box($widget)` returns where any element widget was
placed (`{ x, y, width, height }`). All three return `undef` for a
widget that frame did not lay out.

### Auto-sized grids

`Clay::UI::Grid` lays out rows of cells whose columns shrink-wrap to
their widest cell and rows to their tallest, in a single layout pass.
Add rows with `append_row` (or `insert_row`, `replace_row`,
`remove_row`, `set_cell`); pass `Clay::UI::Grid::Cell` objects for
styled cells, or any other widget to have it wrapped in an unstyled
cell:

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Clay::XS qw(:all);
use Clay::UI;
use Clay::UI::Grid;
use Clay::UI::Grid::Cell;
use Clay::UI::Text;

class My::Grid :strict(params) :does(Clay::UI::Grid) {}
class My::Text :strict(params) :does(Clay::UI::Text) {}

my $header = Clay::UI::Grid::Cell->new(
    background_color => [55, 90, 140, 255],
    layout           => { padding => padding_all(4) },
);
$header->add_child(My::Text->new(text => 'Header', text_color => [255, 255, 255, 255]));

my $grid = My::Grid->new(id => 'report', row_gap => 2, cell_gap => 8);
$grid->append_row([ $header, My::Text->new(text => 'Value') ]);
$grid->append_row([ My::Text->new(text => 'a much longer label'), My::Text->new(text => '42') ]);

my $render_commands = Clay::UI->new(width => 800, height => 600, root => $grid)->render;
```

Every element widget also accepts `width_group => N` /
`height_group => M` (N, M below 2**20): widgets sharing a non-zero id on
an axis are equalized to the largest of them, each staying within its
own sizing `max`. Groups may nest (a grid in a grid cell). Use them for
form-label alignment, equal-height buttons and the like, independent of
the Grid widget. See `examples/05-ui-grid.pl` for an SVG demo and
`examples/04-ui-sidebar.pl` for the sidebar demo rebuilt on Clay::UI.

Grids have more for tables:

- Spanning rows (`append_spanning_row`, `insert_spanning_row`,
  `replace_spanning_row`) hold one cell as wide as the grid, for example
  a group heading; they size no column, and a long heading wraps
  instead of widening the grid.
- `share_columns_with => $other_grid` makes column N of both grids one
  column for Clay, and gives the grids a common width: a header grid
  stays aligned with a body grid that scrolls below it.
- `reorder_rows(\@order)` puts the rows in a new order without detaching
  any, so focus and hover stay where they were; `clear_rows` removes
  them all.
- A widget composing `Clay::UI::Role::Layout::GridCell` (such as
  `Clay::UI::Grid::Cell`) is used as the cell as it is, so a cell class
  of your own can carry events or styles.

### Flow layout

Any widget with a `layout` slice wraps its children onto new lines when
it sets `layout_direction => CLAY_LEFT_TO_RIGHT_WRAP`: children go left
to right, and a child that does not fit the remaining width starts a new
line below. `child_gap` separates neighbours, `line_gap` separates lines.
When the container is taller than its lines, `line_sizing` decides what
happens to the leftover height: `CLAY_LINE_SIZING_GROW` (the default)
shares it equally between the lines, `CLAY_LINE_SIZING_FIT` keeps lines
tight and lets `child_alignment.y` place them. `GROW` children fill the
rest of their own line, and `border_width => { between_children => N }`
draws separators between neighbours and between lines:

```perl
my $tags = My::Box->new(layout => {
    sizing           => { width => sizing_grow() },
    child_gap        => 8,
    line_gap         => 8,
    layout_direction => CLAY_LEFT_TO_RIGHT_WRAP,
    line_sizing      => CLAY_LINE_SIZING_FIT,
});
$tags->add_child(My::Text->new(text => $_)) for qw(perl layout clay flow);
```

See `examples/07-ui-flow.pl` for an SVG demo.

### Stack layout

`layout_direction => CLAY_BACK_TO_FRONT` puts a widget's children on top
of each other, each placed by `child_alignment` on both axes; later
children are drawn over earlier ones and get the press where they
overlap (every child under the pointer is still hovered). The container
fits its largest child on each axis, and `GROW` children fill it, so a
background, content and a corner badge stack like this:

```perl
my $card = My::Box->new(layout => {
    layout_direction => CLAY_BACK_TO_FRONT,
    child_alignment  => { x => CLAY_ALIGN_X_RIGHT, y => CLAY_ALIGN_Y_TOP },
});
$card->add_child(
    My::Box->new(background_color => [30, 30, 30, 255],
        layout => { sizing => { width => sizing_grow(), height => sizing_grow() } }),
    My::Text->new(text => 'content'),
    My::Box->new(background_color => [220, 60, 60, 255],
        layout => { sizing => { width => sizing_fixed(8), height => sizing_fixed(8) } }),
);
```

A stack has one `child_alignment`; to put children in different corners,
wrap each in a `GROW` stack with its own. See `examples/08-ui-stack.pl`
for an SVG demo.

### Focus

`$ui->interaction->set_focused_widget($widget)`,
`$ui->interaction->focus_next` and `$ui->interaction->focus_previous`
move focus between `Focusable` widgets in
depth-first order; a container composing `HasFocusOrder` can take over
the order for its subtree (the root also decides the first focus).
Widgets whose `can_focus` is false are skipped: `can_focus` reads whether
a widget can take the focus now (the users' wish, its class's
`accepts_focus` and, with `Disableable`, not disabled). A focused widget
that becomes disabled or unfocusable loses the focus at once (`OnBlur`),
and `$ui->interaction->can_take_focus($widget)` asks the same question
the tracker asks.

### Skipping unchanged frames

Every setter that changes what a frame lays out or draws (widget
attributes, children, user states, the viewport size, and hover, press
and focus changes) bumps one process-wide counter,
`Clay::UI::Revision::current_revision()`, and so does scrolling inside
`render`. A renderer still calls `render` every frame (input reaches the
widgets only there), remembers the value it drew and skips drawing
while it has not changed:

```perl
my $commands = $ui->render(%input);
unless (current_revision() == $drawn_revision) {
    $drawn_revision = current_revision();
    draw($commands);
}
```

Widget classes with state of their own call `$widget->mark_changed`
from their setters.

Event listeners and `Preparable` widgets may change the tree inside
`render`, before its layout pass. `$ui->laid_out_revision` is the
revision that layout pass started at, so every change up to it is in
the frame `render` returned. Remember it instead of `current_revision()`
when your drawing code may change widgets itself: those later changes
then still get a frame of their own.

### Tree size

Each `Clay::UI` holds up to `max_element_count` Clay elements (default
8192, Clay's default; every widget is one, and Clay keeps two for
itself). Pass a larger `max_element_count` to `Clay::UI->new` for a
bigger tree; with the default error handler, a tree that does not fit
makes `render` die with a message naming the parameter.

## Known limitations

- **Per-element transition callbacks are not supported.** Clay's
  transition callbacks carry no element id, so one handler set per
  context (`Clay_SetTransitionHandlers`) serves every transitioning
  element; dispatch on the handler's arguments if needed.
- **Contexts belong to one interpreter.** Clay keeps one process-wide
  current context. Several contexts can be used from one interpreter
  through `Clay_SetCurrentContext` (a `Clay::UI` object switches to its
  own context on every call); contexts are not copied into new threads,
  and while another thread's context is current every Clay call croaks.

## Renderers

The layout pass only produces render commands. `examples/03-svg-render.pl`
writes SVG and `examples/06-png-render.pl` renders PNG through Imager.

## License

zlib/libpng, matching Clay itself. See `src/clay/LICENSE.md` for the
upstream notice.
