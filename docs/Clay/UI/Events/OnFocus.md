# NAME

Clay::UI::Events::OnFocus - fired at a widget that receives the focus

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

my $name = My::Input->new(id => 'name');
my $root = My::Panel->new(id => 'form');
$root->add_child($name);
$name->on('OnFocus', sub ($event) {
        say 'focus gained by ', $event->target->id;
        return;
});

my $ui = Clay::UI->new(width => 400, height => 300, root => $root);
$ui->interaction->focus_next;   # prints "focus gained by name"
```

# DESCRIPTION

`OnFocus` fires at a [Clay::UI::Role::Interaction::Focusable](../Role/Interaction/Focusable.md) widget
right after it received the focus through
["set\_focused\_widget" in Clay::UI::Interaction](../Interaction.md#set_focused_widget),
["focus\_next" in Clay::UI::Interaction](../Interaction.md#focus_next) or
["focus\_previous" in Clay::UI::Interaction](../Interaction.md#focus_previous). `render` never moves the
focus, so it never fires `OnFocus`. The widget has the focus
(`is_focused` is 1) when its listeners run. Its partner is
[Clay::UI::Events::OnBlur](OnBlur.md).

When the focus moves from one widget to another, the old widget's
`OnBlur` fires first, then the new widget's `OnFocus`. If an
`OnBlur` listener moves the focus elsewhere, this `OnFocus` is
dropped, because its widget no longer has the focus.

- Name

    `'OnFocus'`.

- Received by

    The widget that received the focus.

- Bubbling

    Bubbles with `Clay::UI::Enum::Bubble->IF_CONTINUE`: the parent
    sees the event when the widget has no `OnFocus` listener or all its
    listeners return `Clay::UI::Enum::Result->CONTINUE`. A container
    can therefore learn that the focus entered its subtree.

# ACCESSORS

No payload. The inherited accessors (see [Clay::UI::Events::Event](Event.md)):
`name` is `'OnFocus'`, `bubble_mode` is `IF_CONTINUE`, `target`
is the focused widget, `current_target` the widget whose listeners run
right now, and `handled_by` and `result` tell where the event
stopped.

# CLASS METHODS

## event\_name

```perl
my $name = Clay::UI::Events::OnFocus->event_name;    # 'OnFocus'
```

Returns `'OnFocus'`, the event name listeners register for with `on`
and the default `name` of a new event (see
["event\_name" in Clay::UI::Events::Event](Event.md#event_name)).

# SEE ALSO

[Clay::UI::Events::OnBlur](OnBlur.md), [Clay::UI::Role::Interaction::Focusable](../Role/Interaction/Focusable.md),
["FOCUS" in Clay::UI::Interaction](../Interaction.md#focus).
