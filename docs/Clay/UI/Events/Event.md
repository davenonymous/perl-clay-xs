# NAME

Clay::UI::Events::Event - base class of Clay::UI events, and how to make your own

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Clay::UI::Box;
use Clay::UI::Events::Event;
use Clay::UI::Enum::Bubble;
use Clay::UI::Enum::Result;

class My::Panel :strict(params) :does(Clay::UI::Box) {}

# A custom event: a subclass with its own name, payload and bubble mode.
class My::Events::OnSubmit :isa(Clay::UI::Events::Event) :strict(params) {
        field $value :param :reader;

        method event_name          :common { 'OnSubmit' }
        method default_bubble_mode :common { Clay::UI::Enum::Bubble->ALWAYS }
}

my $form  = My::Panel->new(id => 'form');
my $field = My::Panel->new(id => 'field');
$form->add_child($field);

$form->on('OnSubmit', sub ($event) {
        say 'form got ', $event->value, ' from ', $event->target->id;
        return Clay::UI::Enum::Result->HANDLED;
});

# Fire it at the widget it concerns; it bubbles up to the form.
my $event  = My::Events::OnSubmit->new(value => 42);
my $result = $field->fire_event($event);
say 'handled by ', $event->handled_by->id
        if $result == Clay::UI::Enum::Result->HANDLED;

# A one-off event needs no subclass:
$field->fire_event(Clay::UI::Events::Event->new(name => 'OnPing'));
```

# DESCRIPTION

Every Clay::UI event is an object of this class or of a subclass. An
event has a _name_, which listeners register for with
`$widget->on($name, sub ($event) { ... })`
([Clay::UI::Role::Events::Listener](../Role/Events/Listener.md)), and a _bubble mode_, which says
whether the event travels from the widget it was fired at (the
_target_) up to its ancestors ([Clay::UI::Enum::Bubble](../Enum/Bubble.md)).

A widget that composes [Clay::UI::Role::Events::Emitter](../Role/Events/Emitter.md) fires an
event with `$widget->fire_event($event)`
(["fire\_event" in Clay::UI::Role::Events::Emitter](../Role/Events/Emitter.md#fire_event)). While the event
travels, its accessors tell each listener where it is.

The built-in events are subclasses:
[Clay::UI::Events::OnHoverStart](OnHoverStart.md), [Clay::UI::Events::OnHoverStopped](OnHoverStopped.md),
[Clay::UI::Events::OnPress](OnPress.md), [Clay::UI::Events::OnRelease](OnRelease.md),
[Clay::UI::Events::OnScroll](OnScroll.md), [Clay::UI::Events::OnFocus](OnFocus.md) and
[Clay::UI::Events::OnBlur](OnBlur.md).

# CONSTRUCTOR

## new

```perl
my $event = Clay::UI::Events::Event->new(%params);
```

Creates an event. Both parameters are optional; unknown parameters die
(the class is `:strict(params)`).

- name

    The event name, a non-empty string. Default: what the class method
    `event_name` returns (`'Event'` for this class). Dies with
    `Clay::UI::Events::Event: 'name' must be a non-empty string`.

- bubble\_mode

    A [Clay::UI::Enum::Bubble](../Enum/Bubble.md) value. Default: what the class method
    `default_bubble_mode` returns (`IF_CONTINUE` for this class). Dies
    with `Clay::UI::Events::Event: 'bubble_mode' must be a Clay::UI::Enum::Bubble value`.

# ACCESSORS

## name

```perl
my $name = $event->name;
```

The event name listeners register for.

## bubble\_mode

```perl
my $mode = $event->bubble_mode;
```

The [Clay::UI::Enum::Bubble](../Enum/Bubble.md) value that decides how far the event
travels.

## target

```perl
my $widget = $event->target;
```

The widget `fire_event` was called on. It stays the same while the
event bubbles. `undef` before the event is fired.

## current\_target

```perl
my $widget = $event->current_target;
```

The widget whose listeners are running right now: the target first,
then each ancestor the event bubbles to. `undef` before the event is
fired.

## handled\_by

```perl
my $widget = $event->handled_by;
```

The first widget at which a listener returned anything but
`Clay::UI::Enum::Result->CONTINUE`, or `undef` when no listener
did (or the event has not been fired). With `IF_CONTINUE` and `NEVER`
it is the widget where the event stopped; with `ALWAYS` the event
travels on and this names the first such widget.

`target`, `current_target` and `handled_by` are weak references: a
fired event never keeps widgets alive.

## result

```perl
my $result = $event->result;
```

The outcome of the dispatch so far, as a [Clay::UI::Enum::Result](../Enum/Result.md)
value: `HANDLED` when `handled_by` is set, `CONTINUE` otherwise.
`fire_event` returns this value.

# CLASS METHODS

Subclasses override these `:common` methods to give `new` its
defaults.

## event\_name

```perl
method event_name :common { 'OnSubmit' }
```

The default `name`. Returns `'Event'` in this class.

## default\_bubble\_mode

```perl
method default_bubble_mode :common { Clay::UI::Enum::Bubble->NEVER }
```

The default `bubble_mode`. Returns `Clay::UI::Enum::Bubble->IF_CONTINUE`
in this class.

# CUSTOM EVENTS

To give an event a payload, subclass this class:

1. Declare the class with `:isa(Clay::UI::Events::Event)` and
`:strict(params)`.
2. Add the payload as fields with `:param :reader` (as
[Clay::UI::Events::OnPress](OnPress.md) does with `x`, `y` and `button`).
3. Override `event_name` (and `default_bubble_mode` when
`IF_CONTINUE` is not right) as `:common` methods.
4. Fire a new object with `$widget->fire_event($event)` on a widget
that composes [Clay::UI::Role::Events::Emitter](../Role/Events/Emitter.md), for example any
[Clay::UI::Box](../Box.md). Text widgets can listen but not fire.

For an event without payload, `Clay::UI::Events::Event->new(name =>
'OnPing')` is enough. Clay::UI never fires custom events by itself;
fire them from your own listeners or code, for example from an
`OnRelease` listener of a widget that turns a click into an
`OnSubmit`.

# FIRING AN EVENT TWICE

An event object is single-use. The first `fire_event` records the
target; firing the same object again dies with
`Clay::UI::Events::Event: event already dispatched; build a fresh event to fire again`.
Create a new event for every dispatch.

# SEE ALSO

[Clay::UI::Role::Events::Emitter](../Role/Events/Emitter.md), [Clay::UI::Role::Events::Listener](../Role/Events/Listener.md),
[Clay::UI::Enum::Bubble](../Enum/Bubble.md), [Clay::UI::Enum::Result](../Enum/Result.md), ["EVENTS" in Clay::UI](../../UI.md#events).
