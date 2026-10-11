# NAME

Clay::UI::Enum::Bubble - how far a Clay::UI event travels up the widget tree

# SYNOPSIS

```perl
use v5.22;
use warnings;

use Clay::UI::Enum::Bubble;
use Clay::UI::Events::Event;

my $event = Clay::UI::Events::Event->new(
        name        => 'OnPing',
        bubble_mode => Clay::UI::Enum::Bubble->ALWAYS,
);
say $event->bubble_mode->name;    # ALWAYS
say 'travels to every ancestor'                  # compare with == and !=
        if $event->bubble_mode == Clay::UI::Enum::Bubble->ALWAYS;
```

# DESCRIPTION

Every event has a _bubble mode_
(["bubble\_mode" in Clay::UI::Events::Event](../Events/Event.md#bubble_mode)). When a widget fires an event
(["fire\_event" in Clay::UI::Role::Events::Emitter](../Role/Events/Emitter.md#fire_event)), all listeners of that
widget for the event's name run first, in the order they were
registered. Then the bubble mode decides whether the event moves on to
the widget's parent, where the same happens again, up to the root
widget.

A listener _stops_ the event when it returns anything but
`Clay::UI::Enum::Result->CONTINUE`, including `undef` and an
empty `return` (see [Clay::UI::Enum::Result](Result.md)). Stopping never skips
other listeners of the same widget: the decision is made per widget,
after all its listeners ran.

The values are singleton objects (built with [Object::PadX::Enum](https://metacpan.org/pod/Object%3A%3APadX%3A%3AEnum));
compare them with `==` and `!=`.

# VALUES

## ALWAYS

```perl
Clay::UI::Enum::Bubble->ALWAYS
```

The event visits the widget and every ancestor, whatever the listeners
return. `handled_by` names the first widget where a listener stopped
it.

## IF\_CONTINUE

```perl
Clay::UI::Enum::Bubble->IF_CONTINUE
```

The event moves on to the parent unless a listener of the current
widget stopped it. A widget without listeners for the event passes it
on. This is the default of [Clay::UI::Events::Event](../Events/Event.md) and of the
built-in `OnPress`, `OnRelease`, `OnScroll`, `OnFocus` and
`OnBlur`.

## NEVER

```perl
Clay::UI::Enum::Bubble->NEVER
```

Only the widget the event was fired at sees it; ancestors never do.
The default of `OnHoverStart` and `OnHoverStopped`.

# METHODS

## name

```perl
my $name = $mode->name;    # 'ALWAYS', 'IF_CONTINUE' or 'NEVER'
```

The value's name.

## values

```perl
my @modes = Clay::UI::Enum::Bubble->values;
```

All three values, in the order `ALWAYS`, `IF_CONTINUE`, `NEVER`.

## from\_name

```perl
my $mode = Clay::UI::Enum::Bubble->from_name('NEVER');
```

The value with that name. Further methods (`ordinal`,
`from_ordinal`) come from [Object::PadX::Enum](https://metacpan.org/pod/Object%3A%3APadX%3A%3AEnum).

# SEE ALSO

[Clay::UI::Enum::Result](Result.md), [Clay::UI::Role::Events::Emitter](../Role/Events/Emitter.md),
[Clay::UI::Events::Event](../Events/Event.md).
