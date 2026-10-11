# NAME

Clay::UI::Events::OnHoverStopped - fired when the pointer leaves a hovered widget

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Clay::XS qw(sizing_fixed);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Role::Interaction::Hoverable;

class My::Panel :strict(params) :does(Clay::UI::Box) {}
class My::Tile  :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Hoverable)
{}

my $tile = My::Tile->new(
        id     => 'tile',
        layout => { sizing => { width => sizing_fixed(50), height => sizing_fixed(50) } },
);
$tile->on('OnHoverStopped', sub ($event) {
        say 'pointer left ', $event->target->id;
        return;
});
my $root = My::Panel->new(id => 'root');
$root->add_child($tile);

my $ui = Clay::UI->new(width => 100, height => 100, root => $root);
$ui->render;
$ui->render(pointer_state => { x => 10, y => 10, down => 0 });   # over the tile
$ui->render(pointer_state => { x => 90, y => 90, down => 0 });   # "pointer left tile"
```

# DESCRIPTION

`OnHoverStopped` fires at a hovered widget when it stops being
hovered:

- in the frame the pointer is no longer over it (during
["render" in Clay::UI](../../UI.md#render) or a synthetic ["update" in Clay::UI::Interaction](../Interaction.md#update));
- at once, during the removal, when the widget (or an ancestor) is
removed from the tree while hovered. The widget is still attached to
its parent while the listeners run.

The widget is no longer hovered (`is_hovered` is 0) when its listeners
run. A widget gets `OnHoverStopped` only after it got
[Clay::UI::Events::OnHoverStart](OnHoverStart.md).

- Name

    `'OnHoverStopped'`.

- Received by

    The [Clay::UI::Role::Interaction::Hoverable](../Role/Interaction/Hoverable.md) widget that stopped being
    hovered. Every such widget gets its own event, nested ones included.

- Bubbling

    Does not bubble by default (`Clay::UI::Enum::Bubble->NEVER`), like
    the DOM's `mouseleave`.

- Order

    All `OnHoverStopped` events of a frame fire first, before every other
    event of the frame, in tree order. An event whose widget is hovered
    again when its turn comes is dropped.

# ACCESSORS

No payload. The inherited accessors (see [Clay::UI::Events::Event](Event.md)):

- name

    `'OnHoverStopped'`.

- bubble\_mode

    `Clay::UI::Enum::Bubble->NEVER`.

- target
- current\_target

    The widget that stopped being hovered.

- handled\_by
- result

    That widget and `HANDLED` when one of its listeners returned anything
    but `Clay::UI::Enum::Result->CONTINUE`.

# CLASS METHODS

## event\_name

```perl
my $name = Clay::UI::Events::OnHoverStopped->event_name;    # 'OnHoverStopped'
```

Returns `'OnHoverStopped'`, the event name listeners register for with `on`
and the default `name` of a new event (see
["event\_name" in Clay::UI::Events::Event](Event.md#event_name)).

## default\_bubble\_mode

```perl
my $mode = Clay::UI::Events::OnHoverStopped->default_bubble_mode;    # Bubble->NEVER
```

Returns `Clay::UI::Enum::Bubble->NEVER`, the default
`bubble_mode` of a new event: `OnHoverStopped` does not bubble (see
["default\_bubble\_mode" in Clay::UI::Events::Event](Event.md#default_bubble_mode)).

# SEE ALSO

[Clay::UI::Events::OnHoverStart](OnHoverStart.md),
[Clay::UI::Role::Interaction::Hoverable](../Role/Interaction/Hoverable.md),
["REMOVED WIDGETS" in Clay::UI::Interaction](../Interaction.md#removed-widgets), ["EVENTS" in Clay::UI](../../UI.md#events).
