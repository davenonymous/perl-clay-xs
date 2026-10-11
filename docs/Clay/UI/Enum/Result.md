# NAME

Clay::UI::Enum::Result - what an event listener returns: stop the event or let it continue

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Clay::UI::Box;
use Clay::UI::Events::OnPress;
use Clay::UI::Enum::Result;

class My::Panel :strict(params) :does(Clay::UI::Box) {}

my $card   = My::Panel->new(id => 'card');
my $button = My::Panel->new(id => 'button');
$card->add_child($button);

$card->on('OnPress', sub ($event) { say 'card saw the press'; return });
$button->on('OnPress', sub ($event) {
        say 'button pressed';
        return Clay::UI::Enum::Result->CONTINUE;   # let the card see it too
});

my $result = $button->fire_event(Clay::UI::Events::OnPress->new);
say 'stopped at ', $result == Clay::UI::Enum::Result->HANDLED ? 'the card' : 'nowhere';
```

# DESCRIPTION

An event listener's return value decides whether the event _stops_
at the listener's widget. Return `CONTINUE` to let it go on; anything
else stops it. The bubble mode of the event decides what stopping means
([Clay::UI::Enum::Bubble](Bubble.md)): with `IF_CONTINUE` the event does not
move on to the parent, with `ALWAYS` and `NEVER` it travels as it
would anyway, but the widget is still recorded as the event's
`handled_by`.

["fire\_event" in Clay::UI::Role::Events::Emitter](../Role/Events/Emitter.md#fire_event) and
["result" in Clay::UI::Events::Event](../Events/Event.md#result) also report the outcome as one of
these values.

The values are singleton objects (built with [Object::PadX::Enum](https://metacpan.org/pod/Object%3A%3APadX%3A%3AEnum));
compare them with `==` and `!=`.

# VALUES

## HANDLED

```perl
return Clay::UI::Enum::Result->HANDLED;
```

Stops the event at this widget. Returning `undef`, an empty `return`,
or any other value has the same effect: only `CONTINUE` lets an event
go on. As a result of `fire_event`: some listener stopped the event,
and `$event->handled_by` names the widget.

## CONTINUE

```perl
return Clay::UI::Enum::Result->CONTINUE;
```

Lets the event go on to the parent (with `IF_CONTINUE`). As a result
of `fire_event`: no listener stopped the event.

# METHODS

`name`, `values` and `from_name` work as described in
["METHODS" in Clay::UI::Enum::Bubble](Bubble.md#methods).

# SEE ALSO

[Clay::UI::Enum::Bubble](Bubble.md), [Clay::UI::Role::Events::Emitter](../Role/Events/Emitter.md),
[Clay::UI::Role::Events::Listener](../Role/Events/Listener.md).
