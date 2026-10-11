# NAME

Clay::UI::Role::Layout::HasScroll - make a Clay::UI widget a scroll container

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::XS qw(sizing_grow sizing_fixed CLAY_TOP_TO_BOTTOM);
use Clay::UI;
use Clay::UI::Text;
use Clay::UI::Role::Layout::HasScroll;
use Clay::UI::Role::Layout::HasLayout;

class My::LogView :strict(params)
        :does(Clay::UI::Role::Layout::HasScroll)
        :does(Clay::UI::Role::Layout::HasLayout)
{}
class My::Line :strict(params) :does(Clay::UI::Text) {}

my $log = My::LogView->new(
        id       => 'log',    # required
        vertical => 1,
        layout   => {
                sizing           => { width => sizing_grow(), height => sizing_fixed(300) },
                layout_direction => CLAY_TOP_TO_BOTTOM,
        },
);
$log->add_child(map { My::Line->new(text => "line $_") } 1 .. 100);

my $ui = Clay::UI->new(width => 800, height => 600, root => $log);
$ui->render;    # one frame first: scrolling works on the last frame's layout
$ui->render(
        pointer_state => { x => 10, y => 10, down => 0 },
        scroll_delta  => { x => 0, y => -4 },    # wheel input: 40 units down
);
$ui->scroll_to($log, { y => 0 });               # back to the top
```

# DESCRIPTION

`Clay::UI::Role::Layout::HasScroll` turns a widget into a scroll
container: an element that clips its children to its own box and moves
them by a scroll offset. Only a widget composing this role scrolls:

- the layout pass (the part of ["render" in Clay::UI](../../../UI.md#render) that declares the tree
to Clay) gives only it Clay's scroll offset;
- only it receives [Clay::UI::Events::OnScroll](../../Events/OnScroll.md);
- only it works with ["scroll\_state" in Clay::UI](../../../UI.md#scroll_state) and ["scroll\_to" in Clay::UI](../../../UI.md#scroll_to).

A widget that writes a `clip` part into its declaration without this
role is clipped but does not scroll.

The role composes:

- [Clay::UI::Role::Core::Stateful](../Core/Stateful.md): `id` is required, because Clay
keeps the scroll position under the element id from frame to frame;
- [Clay::UI::Role::Core::Container](../Core/Container.md): the scrolled content is added with
`add_child`;
- [Clay::UI::Role::Events::Emitter](../Events/Emitter.md): events can be fired on it.

`render` scrolls the containers itself: it passes its `scroll_delta`
and `enable_drag_scrolling` arguments to Clay once per frame (wheel
input moves the container under the pointer, by ten times
`scroll_delta`; negative values scroll down and right). Wheel input
has no momentum. Drag scrolling moves the container with the pointer
and, after the release, lets it glide on with momentum for some frames.
Scrolling uses the
layout of the previous frame, so it starts working after one completed
`render`. Leave `Clay_UpdateScrollContainers` to `render`: movement
from a call of your own between renders goes unnoticed, since `render`
compares the positions it finds at its start with those after its own
call (no `OnScroll`, no revision bump).

# CONSTRUCTOR PARAMETERS

## id

Required. See ["id" in Clay::UI::Role::Core::Element](../Core/Element.md#id). The constructor dies
with `Clay::UI::Role::Core::Stateful: widget '...' requires an explicit 'id'` without one.

# ATTRIBUTES

Each attribute is a constructor parameter and a read/write accessor:
call it without an argument to read, with one argument to write. A
write bumps the revision ([Clay::UI::Revision](../../Revision.md)), takes effect at the
next `render` and returns the new value. Values are checked when they
are set; a bad value dies naming the attribute.

## horizontal

```perl
$scroll->horizontal(1);
```

Whether the container clips and scrolls horizontally. A plain scalar,
used as a Perl boolean. Default `0`. Undef dies with
`Clay::UI: 'horizontal' must be defined`, a reference with
`Clay::UI: 'horizontal' expected a plain boolean value`.

## vertical

```perl
$scroll->vertical(0);
```

Whether the container clips and scrolls vertically, like
["horizontal"](#horizontal). Default `1`.

## child\_offset

```perl
$scroll->child_offset({ x => 0, y => -120 });    # you place the content
$scroll->child_offset(undef);                    # Clay scrolls again
```

Where the content is placed, relative to the container's top left
corner. Default undef: each frame the layout pass uses Clay's own
scroll position, which `render` updates from wheel and drag input.
Set `{ x, y }` (or `[x, y]`) to place the content yourself:
the offset is used as it is, and input no longer moves the content.
Clay still tracks its own scroll position meanwhile: wheel and drag
input still change `position` in ["scroll\_state" in Clay::UI](../../../UI.md#scroll_state), fire
[Clay::UI::Events::OnScroll](../../Events/OnScroll.md) and bump the revision, although the
content does not move.
Negative values move the content up and left, like scrolling down and
right. Set it back to undef to give control back to Clay.

Reading returns a new copy (or undef); writing stores a copy. An unknown
key or a non-number dies, for example
`Clay::UI: 'child_offset' has unknown key 'z' (known keys: x, y)`.

To scroll to a position while keeping Clay in control (and its limits
to the content size), use ["scroll\_to" in Clay::UI](../../../UI.md#scroll_to) instead.

# METHODS

## contribute\_clip

Adds the `clip` part to the widget's declaration (see
["EXTENDING THE DECLARATION" in Clay::UI::Role::Core::Element](../Core/Element.md#extending-the-declaration) and
["clip" in Clay::XS::Structs](../../../XS/Structs.md#clip)): `horizontal`, `vertical` and, when set,
`child_offset`.

# SEE ALSO

["scroll\_state" in Clay::UI](../../../UI.md#scroll_state), ["scroll\_to" in Clay::UI](../../../UI.md#scroll_to),
[Clay::UI::Events::OnScroll](../../Events/OnScroll.md), ["clip" in Clay::XS::Structs](../../../XS/Structs.md#clip),
[Clay::Manual](../../../Manual.md).
