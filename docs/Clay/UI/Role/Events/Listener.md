# NAME

Clay::UI::Role::Events::Listener - role that lets every widget listen to events

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

my $box = My::Panel->new(id => 'box');
# Both listeners always run; the return values only decide whether
# the event moves on to the parent.
$box->on('OnPress', sub ($event) {    # stops bubbling
        say 'first listener';
        return;
})->on('OnPress', sub ($event) {
        say 'second listener';
        return Clay::UI::Enum::Result->CONTINUE;
});

say scalar @{ $box->handlers_for('OnPress') }, ' listeners';   # 2 listeners
$box->fire_event(Clay::UI::Events::OnPress->new);    # first listener, second listener
```

# DESCRIPTION

This role is the _receiving_ half of the Clay::UI event system. Every
widget has it: [Clay::UI::Role::Core::Element](../Core/Element.md) and
[Clay::UI::Role::Core::TextNode](../Core/TextNode.md) compose it, so you never compose it
yourself. Any widget can therefore listen to events fired at it and to
events that bubble up to it from its descendants, whether or not it can
fire events itself (see [Clay::UI::Role::Events::Emitter](Emitter.md)).

Text widgets have the role too, but no event reaches them: a text
widget cannot fire, nothing bubbles through it (it has no descendants),
and Clay::UI fires events only at element widgets. Listen on the
element widget around the text instead.

# METHODS

## on

```perl
$widget->on($event_name, sub ($event) { ... });
```

Registers a listener: a coderef called with the event object when an
event whose `name` is `$event_name` is fired at the widget or bubbles
to it. A widget may have several listeners for one name; they run in
the order they were registered. There is no way to remove a listener.

All listeners of a widget for the event always run, whatever the
earlier ones return. The return values only decide whether the event
moves on to the parent (see [Clay::UI::Enum::Result](../../Enum/Result.md)): return
`Clay::UI::Enum::Result->CONTINUE` to let it bubble on. **Anything
else stops it** from bubbling, including an empty `return`, `undef`
and whatever the last statement happens to return; one stopping
listener is enough.

A listener that needs the widget it is registered on should read it
from the event (`$event->current_target`) instead of naming the
widget's variable inside the closure. The widget keeps its listeners,
so a closure that captures the widget makes a reference cycle, and the
widget is never freed:

```perl
$box->on('OnPress', sub ($event) {
        my $box = $event->current_target;    # not the outer $box
        ...
        return;
});
```

Returns the widget, so calls can be chained. Dies with
`Clay::UI::Role::Events::Listener: event name must be a non-empty string`
or `Clay::UI::Role::Events::Listener: handler must be a coderef`.

## handlers\_for

```perl
my $listeners = $widget->handlers_for($event_name);
```

Returns a new arrayref of the listeners registered for `$event_name`,
in registration order (empty when there are none). Changing the
arrayref does not change the widget.
["fire\_event" in Clay::UI::Role::Events::Emitter](Emitter.md#fire_event) calls it for every widget
the event visits.

Listeners are called _handlers_ in this method's name and in the
error message of ["on"](#on) (`handler must be a coderef`); both words mean
the coderefs registered with `on`.

# SEE ALSO

[Clay::UI::Role::Events::Emitter](Emitter.md), [Clay::UI::Events::Event](../../Events/Event.md),
["EVENTS" in Clay::UI](../../../UI.md#events).
