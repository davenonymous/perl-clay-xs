# NAME

Clay::UI::Role::Interaction::Focusable - role for widgets that can take the keyboard focus

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
use Clay::UI::Role::Interaction::Disableable;

class My::Panel     :strict(params) :does(Clay::UI::Box) {}
class My::TextInput :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Focusable)
        :does(Clay::UI::Role::Interaction::Disableable)
{}

my $input = My::TextInput->new(id => 'name');
$input->on('OnFocus', sub ($event) { say 'got the focus';  return });
$input->on('OnBlur',  sub ($event) { say 'lost the focus'; return });

my $root = My::Panel->new(id => 'form');
$root->add_child($input);
my $ui = Clay::UI->new(width => 400, height => 300, root => $root);

$ui->interaction->set_focused_widget($input);   # got the focus
say $input->is_focused;                         # 1
$input->disabled(1);    # lost the focus; can_focus is 0 until enabled
```

# DESCRIPTION

A widget that composes this role can take the focus: the one widget of
a [Clay::UI](../../../UI.md) that receives keyboard input. The UI's interaction
tracker ([Clay::UI::Interaction](../../Interaction.md)) holds which widget has the focus and
moves it (["FOCUS" in Clay::UI::Interaction](../../Interaction.md#focus)); this role says whether the
widget may take it (["can\_focus"](#can_focus)) and whether it has it
(["is\_focused"](#is_focused)).

The widget receives [Clay::UI::Events::OnFocus](../../Events/OnFocus.md) when it gets the focus
and [Clay::UI::Events::OnBlur](../../Events/OnBlur.md) when it loses it. Both bubble with
`IF_CONTINUE`.

The role composes [Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md),
[Clay::UI::Role::Events::Emitter](../Events/Emitter.md) and
[Clay::UI::Role::Style::HasStates](../Style/HasStates.md), which provides the derived state
`focused`.

# PARAMETERS

## can\_focus (constructor parameter)

```perl
My::TextInput->new(can_focus => 0);
```

Constructor parameter: whether the widget's users want it to take the
focus, any plain boolean value; default 1. Dies for a reference with
`Clay::UI: 'can_focus' must be a plain boolean value`.

# METHODS

## can\_focus

```perl
my $eligible = $widget->can_focus;    # 1 or 0
$widget->can_focus(0);
```

Reads whether the widget can take the focus now. It can when all of
these hold:

- its users want it to: the `can_focus` constructor parameter, or the
last value written;
- its class accepts the focus (["accepts\_focus"](#accepts_focus));
- it is not disabled, when it composes
[Clay::UI::Role::Interaction::Disableable](Disableable.md).

A write records what the users want, whatever the widget's state: a
widget given `can_focus(1)` while disabled can take the focus once it
is enabled, and one built with `can_focus => 0` stays unable to
take it when it is enabled. A write takes one plain boolean value,
returns what reading returns now, and does not bump the revision
(nothing drawn depends on it). When the widget has the focus and can no
longer take it, it loses the focus at once and gets `OnBlur` (see
["release\_ineligible" in Clay::UI::Interaction](../../Interaction.md#release_ineligible)). Dies with
`Clay::UI: 'can_focus' must be a plain boolean value` or
`Clay::UI: 'can_focus' takes one value`.

A widget whose `can_focus` is 0 is skipped by `focus_next` and
`focus_previous`, rejected by `set_focused_widget` (which dies), and
means "the focus stays" when a
[Clay::UI::Role::Interaction::HasFocusOrder](HasFocusOrder.md) returns it.

## accepts\_focus

```perl
method accepts_focus :override () { return 0 }
```

Whether widgets of the class take the focus at all; returns 1 here. A
subclass overrides it to return 0 when its widgets never take the
focus themselves, for example a radio button whose group takes the
focus for all its buttons. ["can\_focus"](#can_focus) then returns 0 whatever was
written. A class cannot override a method of a role it composes itself,
so the override goes into a subclass of the class that composes
Focusable:

```perl
class My::RadioButton :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Focusable) {}
class My::GroupedRadioButton :strict(params) :isa(My::RadioButton) {
        method accepts_focus :override () { return 0 }
}
```

When the answer depends on the widget's own state (a rating that
takes no focus while it is read-only), the setter of that state calls
["focus\_eligibility\_changed"](#focus_eligibility_changed).

## focus\_eligibility\_changed

```perl
$self->focus_eligibility_changed;
```

For a class whose ["accepts\_focus"](#accepts_focus) answer depends on its own state:
call it from the setter of that state, after the state changed. A
focused widget that can no longer take the focus loses it at once and
gets `OnBlur` before this returns (see
["release\_ineligible" in Clay::UI::Interaction](../../Interaction.md#release_ineligible)); a widget outside a
[Clay::UI](../../../UI.md) is left alone. Bumps the revision
([Clay::UI::Revision](../../Revision.md)), since such state usually changes how the
widget looks. Returns the widget.

```perl
class My::Rating :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Focusable) {}
class My::ReadOnlyRating :strict(params) :isa(My::Rating) {
        field $read_only = 0;

        method accepts_focus :override () { return !$read_only }

        method read_only ($value) {
                $read_only = $value ? 1 : 0;
                $self->focus_eligibility_changed;
                return $self;
        }
}
```

## is\_focused

```perl
my $has_focus = $widget->is_focused;
```

Returns 1 while this widget has the focus of its [Clay::UI](../../../UI.md), 0
otherwise. Returns 0 for a widget that does not belong to a Clay::UI.

# SEE ALSO

["FOCUS" in Clay::UI::Interaction](../../Interaction.md#focus), [Clay::UI::Events::OnFocus](../../Events/OnFocus.md),
[Clay::UI::Events::OnBlur](../../Events/OnBlur.md), [Clay::UI::Role::Interaction::HasFocusOrder](HasFocusOrder.md),
[Clay::UI::Role::Interaction::Disableable](Disableable.md).
