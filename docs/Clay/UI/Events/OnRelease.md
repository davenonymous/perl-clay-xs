# NAME

Clay::UI::Events::OnRelease - fired when a press is released over an armed widget (a click)

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Time::HiRes qw(time);
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
my $pressed_at;
$button->on('OnPress',   sub ($event) { $pressed_at = time; return });
$button->on('OnRelease', sub ($event) {
        my $held = time - $pressed_at;
        say $held < 0.3 ? 'short click' : 'long press';
        return;
});

my $ui = Clay::UI->new(width => 100, height => 100, root => $button);
$ui->render;
$ui->render(pointer_state => { x => 30, y => 40, down => 1 });
$ui->render(pointer_state => { x => 30, y => 40, down => 0 });   # prints "short click"
```

# DESCRIPTION

`OnRelease` fires when the pointer button goes up (`down` changes
from true to false in ["render" in Clay::UI](../../UI.md#render)'s `pointer_state` or in a
synthetic ["update" in Clay::UI::Interaction](../Interaction.md#update)), at the topmost _armed_
[Clay::UI::Role::Interaction::Pressable](../Role/Interaction/Pressable.md) still under the pointer: a
completed click. A Pressable is armed when it was under the pointer at
the press (see [Clay::UI::Events::OnPress](OnPress.md)); the target is chosen
among the armed ones by the rule in
["PRESS AND RELEASE" in Clay::UI::Interaction](../Interaction.md#press-and-release).

Then every widget is disarmed. So nothing fires when:

- the press started elsewhere and the pointer was dragged onto the
widget before the release;
- the pointer was dragged off every armed widget before the release;
- the armed widget was removed from the tree or disabled before the
release.

A press on a button inside a pressable card, dragged off the button and
released over the card, gives the card its `OnRelease`: the press
armed both.

- Name

    `'OnRelease'`.

- Received by

    The topmost armed, enabled Pressable under the pointer.

- Bubbling

    Bubbles with `Clay::UI::Enum::Bubble->IF_CONTINUE`: the parent
    sees the event when the widget has no `OnRelease` listener or all its
    listeners return `Clay::UI::Enum::Result->CONTINUE`.

- Order

    After the frame's hover events and `OnPress`, before `OnScroll`.
    Dropped when an earlier listener removed the widget from the tree.

Clay::UI has no separate click event: an `OnRelease` listener is a
click handler.

# ACCESSORS

## x

```perl
my $x = $event->x;
```

The horizontal pointer position when the release was seen, in layout
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
that fires its own `OnRelease` can pass another number.

## Inherited accessors

`name` is `'OnRelease'` and `bubble_mode` is `IF_CONTINUE`.
`target` is the released widget, `current_target` the widget whose
listeners run right now, `handled_by` and `result` tell where the
event stopped (see [Clay::UI::Events::Event](Event.md)).

# CONSTRUCTOR

```perl
my $event = Clay::UI::Events::OnRelease->new(x => 10, y => 20, button => 1);
```

All parameters are optional: `x` and `y` default to 0, `button` to
1; `name` and `bubble_mode` as in ["new" in Clay::UI::Events::Event](Event.md#new).

# CLASS METHODS

## event\_name

```perl
my $name = Clay::UI::Events::OnRelease->event_name;    # 'OnRelease'
```

Returns `'OnRelease'`, the event name listeners register for with `on`
and the default `name` of a new event (see
["event\_name" in Clay::UI::Events::Event](Event.md#event_name)).

# SEE ALSO

[Clay::UI::Events::OnPress](OnPress.md), [Clay::UI::Role::Interaction::Pressable](../Role/Interaction/Pressable.md),
["PRESS AND RELEASE" in Clay::UI::Interaction](../Interaction.md#press-and-release), ["EVENTS" in Clay::UI](../../UI.md#events).
