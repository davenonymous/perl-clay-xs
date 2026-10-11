# NAME

Clay::UI::Role::Interaction::Disableable - role for widgets that can be switched off

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
use Clay::UI::Role::Interaction::Pressable;
use Clay::UI::Role::Interaction::Disableable;

class My::Button :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Focusable)
        :does(Clay::UI::Role::Interaction::Pressable)
        :does(Clay::UI::Role::Interaction::Disableable)
{}

my $button = My::Button->new(id => 'save', disabled => 1);
my $ui     = Clay::UI->new(width => 400, height => 300, root => $button);

say $button->can_focus;     # 0 while disabled
$button->disabled(0);       # enabled again: can take the focus and be pressed
say $button->is_enabled;    # 1
say $button->can_focus;     # 1
```

# DESCRIPTION

A widget that composes this role can be disabled. While it is
disabled:

- it cannot take the focus: ["can\_focus" in Clay::UI::Role::Interaction::Focusable](Focusable.md#can_focus)
returns 0, so `focus_next` and `focus_previous` skip it and
`set_focused_widget` rejects it. The widget's own `can_focus` wish is
kept for when it is enabled again;
- it is never armed or pressed (see
["PRESS AND RELEASE" in Clay::UI::Interaction](../../Interaction.md#press-and-release)): a press over it fires no
`OnPress` at it, a release no `OnRelease`, and `is_pressed` stays 0.
It is still hovered and still gets the hover events. A press over a
disabled Pressable is absorbed: a pressable card around a disabled
button gets no `OnPress` either (see
["PRESS AND RELEASE" in Clay::UI::Interaction](../../Interaction.md#press-and-release));
- it has the derived state `disabled` (see
[Clay::UI::Role::Style::HasStates](../Style/HasStates.md)), so a style can depend on it.

Disabling a widget that has the focus, or that is armed or pressed,
takes that away at once: it is disarmed and unpressed, and a focused
widget gets `OnBlur` before the `disabled` writer returns (see
["release\_ineligible" in Clay::UI::Interaction](../../Interaction.md#release_ineligible)).

Disabling a widget does not disable its children; each widget has its
own `disabled` value.

The role composes [Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md) and
[Clay::UI::Role::Style::HasStates](../Style/HasStates.md).

# PARAMETERS

## disabled (constructor parameter)

```perl
My::Button->new(disabled => 1);
```

Constructor parameter: whether the widget starts disabled, any plain
boolean value, stored as 1 or 0; default 0. Dies for a reference with
`Clay::UI: 'disabled' must be a plain boolean value`.

# METHODS

## disabled

```perl
my $off = $widget->disabled;    # 1 or 0
$widget->disabled(1);
```

Reads or writes whether the widget is disabled. A write takes one plain
boolean value and returns the new value, 1 or 0. A write that changes
the value bumps the revision ([Clay::UI::Revision](../../Revision.md)) and, when the
widget belongs to a [Clay::UI](../../../UI.md), releases its focus, arming and press
as described above; writing the current value does nothing. Dies with
`Clay::UI: 'disabled' must be a plain boolean value` for a reference
and `Clay::UI: 'disabled' takes one value` for more than one value.

## is\_enabled

```perl
my $on = $widget->is_enabled;
```

Returns 1 while the widget is not disabled, 0 while it is.

# SEE ALSO

[Clay::UI::Role::Interaction::Focusable](Focusable.md),
[Clay::UI::Role::Interaction::Pressable](Pressable.md), [Clay::UI::Interaction](../../Interaction.md).
