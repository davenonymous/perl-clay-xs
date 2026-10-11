# NAME

Clay::UI::Events::OnBlur - fired at a widget that loses the focus

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Role::Interaction::Focusable;

class My::Panel :strict(params) :does(Clay::UI::Box) {}
class My::Input :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Focusable)
{}

my $name  = My::Input->new(id => 'name');
my $email = My::Input->new(id => 'email');
my $root  = My::Panel->new(id => 'form');
$root->add_child($name, $email);
$name->on('OnBlur', sub ($event) {
        say 'focus left ', $event->target->id;
        return;
});

my $ui = Clay::UI->new(width => 400, height => 300, root => $root);
$ui->interaction->set_focused_widget($name);
$ui->interaction->set_focused_widget($email);   # prints "focus left name"
```

# DESCRIPTION

`OnBlur` fires at the widget that had the focus, right after it lost
it:

- the focus moved to another widget or was cleared
(["set\_focused\_widget" in Clay::UI::Interaction](../Interaction.md#set_focused_widget), `focus_next`,
`focus_previous`); the old widget's `OnBlur` fires before the new
widget's [Clay::UI::Events::OnFocus](OnFocus.md);
- the focused widget, or an ancestor, was removed from the tree (at once,
during the removal; the widget is still attached while the listeners
run, so the event bubbles through its old ancestors);
- the focused widget was disabled
([Clay::UI::Role::Interaction::Disableable](../Role/Interaction/Disableable.md)) or its `can_focus` was
set to false ([Clay::UI::Role::Interaction::Focusable](../Role/Interaction/Focusable.md)).

The widget no longer has the focus (`is_focused` is 0) when its
listeners run. A widget gets `OnBlur` only after it got `OnFocus`.
`render` never fires `OnBlur` by itself.

- Name

    `'OnBlur'`.

- Received by

    The widget that lost the focus.

- Bubbling

    Bubbles with `Clay::UI::Enum::Bubble->IF_CONTINUE`: the parent
    sees the event when the widget has no `OnBlur` listener or all its
    listeners return `Clay::UI::Enum::Result->CONTINUE`.

# ACCESSORS

No payload. The inherited accessors (see [Clay::UI::Events::Event](Event.md)):
`name` is `'OnBlur'`, `bubble_mode` is `IF_CONTINUE`, `target` is
the widget that lost the focus, `current_target` the widget whose
listeners run right now, and `handled_by` and `result` tell where the
event stopped.

# CLASS METHODS

## event\_name

```perl
my $name = Clay::UI::Events::OnBlur->event_name;    # 'OnBlur'
```

Returns `'OnBlur'`, the event name listeners register for with `on`
and the default `name` of a new event (see
["event\_name" in Clay::UI::Events::Event](Event.md#event_name)).

# SEE ALSO

[Clay::UI::Events::OnFocus](OnFocus.md), [Clay::UI::Role::Interaction::Focusable](../Role/Interaction/Focusable.md),
["FOCUS" in Clay::UI::Interaction](../Interaction.md#focus), ["REMOVED WIDGETS" in Clay::UI::Interaction](../Interaction.md#removed-widgets).
