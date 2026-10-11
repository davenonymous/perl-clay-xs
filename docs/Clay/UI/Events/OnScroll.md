# NAME

Clay::UI::Events::OnScroll - fired when a scroll container's scroll position changed

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Clay::XS qw(sizing_grow sizing_fixed CLAY_TOP_TO_BOTTOM);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Role::Layout::HasScroll;

class My::Panel :strict(params) :does(Clay::UI::Box) {}
class My::List  :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Layout::HasScroll)
{}

my $list = My::List->new(
        id     => 'list',
        layout => {
                layout_direction => CLAY_TOP_TO_BOTTOM,
                sizing => { width => sizing_fixed(100), height => sizing_fixed(50) },
        },
);
$list->add_child(map {
        My::Panel->new(layout => {
                sizing => { width => sizing_grow(), height => sizing_fixed(20) },
        })
} 1 .. 10);
$list->on('OnScroll', sub ($event) {
        say 'scrolled by ', $event->delta_x, ',', $event->delta_y;
        return;
});

my $ui = Clay::UI->new(width => 200, height => 200, root => $list);
$ui->render(pointer_state => { x => 10, y => 10, down => 0 });
$ui->render(scroll_delta => { x => 0, y => -3 });   # prints "scrolled by 0,-30"
```

# DESCRIPTION

`OnScroll` fires during ["render" in Clay::UI](../../UI.md#render) at a scroll container (a
widget composing [Clay::UI::Role::Layout::HasScroll](../Role/Layout/HasScroll.md)) whose scroll
position changed in this frame: through wheel input (`scroll_delta`),
drag scrolling (`enable_drag_scrolling`) or the momentum that
follows drag scrolling (wheel input has no momentum). It does not fire
for your own calls to ["scroll\_to" in Clay::UI](../../UI.md#scroll_to) or
["set\_scroll\_position" in Clay::XS](../../XS.md#set_scroll_position), with one exception: a
`set_scroll_position` beyond the content is clamped by the next
`render`, and that clamp fires `OnScroll` (the delta runs from the
position you set to the clamped one). `scroll_to` clamps the position
itself, so it never fires `OnScroll`. A synthetic ["update" in Clay::UI::Interaction](../Interaction.md#update) fires
it for every entry of its `scrolled` argument.

- Name

    `'OnScroll'`.

- Received by

    Each scroll container that moved, one event per container.

- Bubbling

    Bubbles with `Clay::UI::Enum::Bubble->IF_CONTINUE`: the parent
    sees the event when the container has no `OnScroll` listener or all
    its listeners return `Clay::UI::Enum::Result->CONTINUE`.

- Order

    Last in the frame, after the hover events, `OnPress` and
    `OnRelease`, in tree order. Dropped when an earlier listener removed
    the container from the tree.

# ACCESSORS

## delta\_x

```perl
my $dx = $event->delta_x;
```

How far the horizontal scroll position moved in this frame, in layout
units: new position minus old. Scroll positions are 0 at the left and
negative when scrolled right, so scrolling right gives a negative
`delta_x`.

## delta\_y

```perl
my $dy = $event->delta_y;
```

How far the vertical scroll position moved, like ["delta\_x"](#delta_x);
scrolling down gives a negative `delta_y`. Read the new position with
["scroll\_state" in Clay::UI](../../UI.md#scroll_state).

## Inherited accessors

`name` is `'OnScroll'` and `bubble_mode` is `IF_CONTINUE`.
`target` is the scroll container, `current_target` the widget whose
listeners run right now, `handled_by` and `result` tell where the
event stopped (see [Clay::UI::Events::Event](Event.md)).

# CONSTRUCTOR

```perl
my $event = Clay::UI::Events::OnScroll->new(delta_x => 0, delta_y => -30);
```

Both parameters are optional and default to 0; `name` and
`bubble_mode` as in ["new" in Clay::UI::Events::Event](Event.md#new).

# CLASS METHODS

## event\_name

```perl
my $name = Clay::UI::Events::OnScroll->event_name;    # 'OnScroll'
```

Returns `'OnScroll'`, the event name listeners register for with `on`
and the default `name` of a new event (see
["event\_name" in Clay::UI::Events::Event](Event.md#event_name)).

# SEE ALSO

[Clay::UI::Role::Layout::HasScroll](../Role/Layout/HasScroll.md), ["scroll\_state" in Clay::UI](../../UI.md#scroll_state),
["scroll\_to" in Clay::UI](../../UI.md#scroll_to), ["EVENTS" in Clay::UI](../../UI.md#events).
