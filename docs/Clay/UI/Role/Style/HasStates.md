# NAME

Clay::UI::Role::Style::HasStates - named states such as selected or loading on a Clay::UI widget

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Style::HasStates;

class My::Item :strict(params)
        :does(Clay::UI::Role::Core::Container)
        :does(Clay::UI::Role::Style::HasStates)
{}

my $item = My::Item->new(id => 'item-1');
$item->add_state('loading');
$item->has_state('loading');       # 1
$item->remove_state('loading');
$item->toggle_state('selected');   # on
my @active = $item->states;        # ('selected')
$item->clear_states;
```

# DESCRIPTION

`Clay::UI::Role::Style::HasStates` gives a widget a set of state
names, so that a theme or renderer has one place to ask what the widget
is doing right now. There are two kinds of states:

- user states

    Any name you choose, such as `selected`, `loading` or `error`. You
    add and remove them; the set holds each name once and has no order.
    A name is a plain, non-empty string; anything else dies.

- derived states

    `hovered`, `pressed`, `focused` and `disabled`. They are never
    stored: `has_state` and `states` ask the widget each time (see
    ["DERIVED STATES"](#derived-states)), and they cannot be added, removed or toggled.

The interaction roles [Clay::UI::Role::Interaction::Hoverable](../Interaction/Hoverable.md),
[Clay::UI::Role::Interaction::Pressable](../Interaction/Pressable.md),
[Clay::UI::Role::Interaction::Focusable](../Interaction/Focusable.md) and
[Clay::UI::Role::Interaction::Disableable](../Interaction/Disableable.md) compose this role already;
compose it yourself only for a widget that needs user states without
any of them.

States do not change the declaration: Clay never sees them. A
contribute method of your own (see
["EXTENDING THE DECLARATION" in Clay::UI::Role::Core::Element](../Core/Element.md#extending-the-declaration)) can turn
them into colours, for example. Such a method must not set a value
that another method of the class also sets: a widget that picks its
`background_color` by state must leave the `background_color`
attribute unset, or not compose [Clay::UI::Role::Style::HasBackground](HasBackground.md)
at all. Every change bumps the revision
([Clay::UI::Revision](../../Revision.md)).

# METHODS

## add\_state

```perl
$widget->add_state('selected');
```

Adds a user state. Adding a state that is already set changes nothing,
but still bumps the revision. Returns the widget. Dies with
`Clay::UI: a state name must be a non-empty string` for undef, a
reference or the empty string, and with
`Clay::UI: state 'hovered' is derived and cannot be set` for a derived
state.

## remove\_state

```perl
$widget->remove_state('selected');
```

Removes a user state; removing one that is not set changes nothing.
Bumps the revision and returns the widget. Dies for a derived state,
like ["add\_state"](#add_state).

## toggle\_state

```perl
$widget->toggle_state('selected');
```

Adds the user state if it is not set, removes it if it is. Bumps the
revision and returns the widget. Dies for a derived state.

## has\_state

```perl
if ($widget->has_state('selected')) { ... }
if ($widget->has_state('hovered'))  { ... }
```

Returns true if the state is active: a user state that is set, or a
derived state that currently applies. A name that is neither is
false.

## clear\_states

```perl
$widget->clear_states;
```

Removes every user state. Derived states are not affected; they keep
following the widget. Bumps the revision and returns the widget.

## states

```perl
my @active = $widget->states;
```

Returns the names of all active states, user and derived, as a list in
no particular order; in scalar context, how many there are.

# DERIVED STATES

Each derived state is answered by a reader of the widget. A widget
without that reader (it does not compose the matching role) never has
the state.

- `hovered`

    `is_hovered` of [Clay::UI::Role::Interaction::Hoverable](../Interaction/Hoverable.md): the pointer
    is over the widget.

- `pressed`

    `is_pressed` of [Clay::UI::Role::Interaction::Pressable](../Interaction/Pressable.md).

- `focused`

    `is_focused` of [Clay::UI::Role::Interaction::Focusable](../Interaction/Focusable.md).

- `disabled`

    `disabled` of [Clay::UI::Role::Interaction::Disableable](../Interaction/Disableable.md).

`is_hovered`, `is_pressed` and `is_focused` ask the UI's
[Clay::UI::Interaction](../../Interaction.md), which updates them during `render`.

# SEE ALSO

[Clay::UI::Interaction](../../Interaction.md), [Clay::UI::Role::Interaction::Hoverable](../Interaction/Hoverable.md),
[Clay::UI::Role::Interaction::Disableable](../Interaction/Disableable.md).
