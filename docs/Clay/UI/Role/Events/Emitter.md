# NAME

Clay::UI::Role::Events::Emitter - role that lets a widget fire events

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Clay::UI::Box;                 # composes Clay::UI::Role::Events::Emitter
use Clay::UI::Events::Event;
use Clay::UI::Enum::Result;

class My::Panel :strict(params) :does(Clay::UI::Box) {}

my $toolbar = My::Panel->new(id => 'toolbar');
my $button  = My::Panel->new(id => 'save');
$toolbar->add_child($button);
$toolbar->on('OnSave', sub ($event) {
        say 'toolbar: ', $event->target->id, ' wants to save';
        return;
});

my $event  = Clay::UI::Events::Event->new(name => 'OnSave');
# no listener on the button: bubbles to the toolbar
my $result = $button->fire_event($event);
say 'handled by ', $event->handled_by->id if $result == Clay::UI::Enum::Result->HANDLED;
```

# DESCRIPTION

This role is the _sending_ half of the Clay::UI event system: it gives
a widget the ["fire\_event"](#fire_event) method. The _receiving_ half, `on`, is
[Clay::UI::Role::Events::Listener](Listener.md), which every widget has.

[Clay::UI::Box](../../Box.md) composes this role, and so do
[Clay::UI::Role::Interaction::Hoverable](../Interaction/Hoverable.md),
[Clay::UI::Role::Interaction::Pressable](../Interaction/Pressable.md),
[Clay::UI::Role::Interaction::Focusable](../Interaction/Focusable.md) and
[Clay::UI::Role::Layout::HasScroll](../Layout/HasScroll.md), whose events Clay::UI fires
through it. Text widgets ([Clay::UI::Text](../../Text.md)) can register listeners,
but no event reaches a text widget: it cannot fire, nothing bubbles
through it (it is a leaf, and events bubble from a widget to its
ancestors), and Clay::UI fires events only at element widgets.

The role composes [Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md) (for the walk up
the `parent` chain) and [Clay::UI::Role::Events::Listener](Listener.md).

# METHODS

## fire\_event

```perl
my $result = $widget->fire_event($event);
```

Dispatches `$event`, a [Clay::UI::Events::Event](../../Events/Event.md) object, starting at
this widget:

1. Records this widget as `$event->target`.
2. Sets `$event->current_target` to the current widget (this widget
first) and calls each of its listeners for `$event->name`, in
registration order, with the event as the only argument. All
listeners of the widget always run; their return values only decide
whether the event moves on to the parent (step 3). A listener _stops_
the event when it returns anything but
`Clay::UI::Enum::Result->CONTINUE`; the first widget where that
happens becomes `$event->handled_by`.
3. Moves on to the parent and repeats step 2, as the event's bubble mode
allows: `ALWAYS` always moves on, `IF_CONTINUE` moves on only when no
listener of the current widget stopped the event, `NEVER` never does
(see [Clay::UI::Enum::Bubble](../../Enum/Bubble.md)). The walk ends at the root widget.

Returns `Clay::UI::Enum::Result->HANDLED` when some listener
stopped the event, otherwise `Clay::UI::Enum::Result->CONTINUE`
(no listener at all is `CONTINUE` too). The same value is available
afterwards as `$event->result`.

Dies with
`Clay::UI::Role::Events::Emitter: fire_event needs a Clay::UI::Events::Event instance`,
and with
`Clay::UI::Events::Event: event already dispatched; build a fresh event to fire again`
for an event object that was fired before.

A listener that dies ends the dispatch at once: the remaining
listeners and ancestors are skipped and `fire_event` dies with that
error. (When Clay::UI fires events in ["render" in Clay::UI](../../../UI.md#render) or
["update" in Clay::UI::Interaction](../../Interaction.md#update), it catches the error, fires the
remaining events of the frame and rethrows the first error
afterwards.)

The widget does not need to belong to a [Clay::UI](../../../UI.md); firing works on
any widget tree.

# SEE ALSO

[Clay::UI::Role::Events::Listener](Listener.md), [Clay::UI::Events::Event](../../Events/Event.md),
[Clay::UI::Enum::Bubble](../../Enum/Bubble.md), [Clay::UI::Enum::Result](../../Enum/Result.md).
