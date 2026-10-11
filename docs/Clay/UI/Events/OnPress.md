# NAME

Clay::UI::Events::OnPress - fired at the topmost pressable widget when the pointer goes down

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
use Clay::UI::Role::Interaction::Pressable;

class My::Button :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Pressable)
{}

my $button = My::Button->new(
        id     => 'go',
        layout => { sizing => { width => sizing_grow(), height => sizing_grow() } },
);
$button->on('OnPress', sub ($event) {
        say 'pressed at ', $event->x, ',', $event->y;
        return;
});

my $ui = Clay::UI->new(width => 100, height => 100, root => $button);
$ui->render;
$ui->render(pointer_state => { x => 30, y => 40, down => 1 });   # prints "pressed at 30,40"
```

# DESCRIPTION

`OnPress` fires when the pointer button goes down (`down` changes
from false to true in ["render" in Clay::UI](../../UI.md#render)'s `pointer_state` or in a
synthetic ["update" in Clay::UI::Interaction](../Interaction.md#update)), at exactly one
[Clay::UI::Role::Interaction::Pressable](../Role/Interaction/Pressable.md): the enabled Pressable under
the pointer that is drawn on top. A button inside a pressable card gets
it, not the card. The precise rule is in
["PRESS AND RELEASE" in Clay::UI::Interaction](../Interaction.md#press-and-release). A press over no enabled
Pressable fires nothing.

The press also _arms_ every enabled Pressable under the pointer, which
is what makes a later [Clay::UI::Events::OnRelease](OnRelease.md) possible.

- Name

    `'OnPress'`.

- Received by

    The topmost enabled Pressable under the pointer. A disabled widget
    ([Clay::UI::Role::Interaction::Disableable](../Role/Interaction/Disableable.md)) never receives it.

- Bubbling

    Bubbles with `Clay::UI::Enum::Bubble->IF_CONTINUE`: the parent
    sees the event when the widget has no `OnPress` listener or all its
    listeners return `Clay::UI::Enum::Result->CONTINUE`, and so on
    upwards. An ancestor never gets a second `OnPress` of its own.

- Order

    After the frame's hover events, before `OnRelease` and `OnScroll`.
    Dropped when an earlier listener removed the widget from the tree.

# ACCESSORS

## x

```perl
my $x = $event->x;
```

The horizontal pointer position when the press was seen, in layout
units: what Clay reports for the frame in `render`, or the `x` passed
to `update` (default 0).

## y

```perl
my $y = $event->y;
```

The vertical pointer position, like ["x"](#x).

## button

```perl
my $button = $event->button;
```

The mouse button, always `1` (primary) when Clay::UI fires the event:
Clay's pointer state has no buttons. A constructor parameter, so code
that fires its own `OnPress` can pass another number.

## Inherited accessors

`name` is `'OnPress'` and `bubble_mode` is `IF_CONTINUE`.
`target` is the pressed widget, `current_target` the widget whose
listeners run right now, `handled_by` and `result` tell where the
event stopped (see [Clay::UI::Events::Event](Event.md)).

# CONSTRUCTOR

```perl
my $event = Clay::UI::Events::OnPress->new(x => 10, y => 20, button => 1);
```

All parameters are optional: `x` and `y` default to 0, `button` to
1; `name` and `bubble_mode` as in ["new" in Clay::UI::Events::Event](Event.md#new).
Clay::UI creates the event itself; construct one only to fire it
yourself with ["fire\_event" in Clay::UI::Role::Events::Emitter](../Role/Events/Emitter.md#fire_event).

# CLASS METHODS

## event\_name

```perl
my $name = Clay::UI::Events::OnPress->event_name;    # 'OnPress'
```

Returns `'OnPress'`, the event name listeners register for with `on`
and the default `name` of a new event (see
["event\_name" in Clay::UI::Events::Event](Event.md#event_name)).

# SEE ALSO

[Clay::UI::Events::OnRelease](OnRelease.md), [Clay::UI::Role::Interaction::Pressable](../Role/Interaction/Pressable.md),
["PRESS AND RELEASE" in Clay::UI::Interaction](../Interaction.md#press-and-release), ["EVENTS" in Clay::UI](../../UI.md#events).
