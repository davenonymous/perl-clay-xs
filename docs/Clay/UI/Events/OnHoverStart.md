# NAME

Clay::UI::Events::OnHoverStart - fired when the pointer comes over a hoverable widget

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Clay::XS qw(sizing_grow);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Role::Interaction::Hoverable;

class My::Tile :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Hoverable)
{}

my $tile = My::Tile->new(
        id     => 'tile',
        layout => { sizing => { width => sizing_grow(), height => sizing_grow() } },
);
$tile->on('OnHoverStart', sub ($event) {
        say 'pointer entered ', $event->target->id;
        return;
});

my $ui = Clay::UI->new(width => 100, height => 100, root => $tile);
$ui->render;                                                     # first layout
$ui->render(pointer_state => { x => 50, y => 50, down => 0 });   # "pointer entered tile"
```

# DESCRIPTION

`OnHoverStart` fires at a [Clay::UI::Role::Interaction::Hoverable](../Role/Interaction/Hoverable.md)
widget in the frame it comes under the pointer: during
["render" in Clay::UI](../../UI.md#render), or during a synthetic
["update" in Clay::UI::Interaction](../Interaction.md#update). The widget is hovered (`is_hovered`
is 1) when its listeners run. Its partner is
[Clay::UI::Events::OnHoverStopped](OnHoverStopped.md).

- Name

    `'OnHoverStart'`.

- Received by

    The Hoverable widget that came under the pointer. Every such widget
    gets its own event, nested ones included; a widget that is not
    Hoverable gets none.

- Bubbling

    Does not bubble by default (`Clay::UI::Enum::Bubble->NEVER`), like
    the DOM's `mouseenter`.

- Order

    All `OnHoverStart` events of a frame fire after its
    `OnHoverStopped` events and before `OnPress`, in tree order. An event
    whose widget is no longer hovered when its turn comes (an earlier
    listener removed it, say) is dropped.

# ACCESSORS

No payload. The inherited accessors (see [Clay::UI::Events::Event](Event.md)):

- name

    `'OnHoverStart'`.

- bubble\_mode

    `Clay::UI::Enum::Bubble->NEVER`.

- target
- current\_target

    The hovered widget.

- handled\_by
- result

    The hovered widget and `HANDLED` when one of its listeners returned
    anything but `Clay::UI::Enum::Result->CONTINUE`.

# CLASS METHODS

## event\_name

```perl
my $name = Clay::UI::Events::OnHoverStart->event_name;    # 'OnHoverStart'
```

Returns `'OnHoverStart'`, the event name listeners register for with `on`
and the default `name` of a new event (see
["event\_name" in Clay::UI::Events::Event](Event.md#event_name)).

## default\_bubble\_mode

```perl
my $mode = Clay::UI::Events::OnHoverStart->default_bubble_mode;    # Bubble->NEVER
```

Returns `Clay::UI::Enum::Bubble->NEVER`, the default
`bubble_mode` of a new event: `OnHoverStart` does not bubble (see
["default\_bubble\_mode" in Clay::UI::Events::Event](Event.md#default_bubble_mode)).

# SEE ALSO

[Clay::UI::Events::OnHoverStopped](OnHoverStopped.md),
[Clay::UI::Role::Interaction::Hoverable](../Role/Interaction/Hoverable.md), ["EVENTS" in Clay::UI](../../UI.md#events).
