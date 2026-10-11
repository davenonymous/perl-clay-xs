# NAME

Clay::UI::Role::Interaction::HasFocusOrder - role for containers that choose the focus order in their subtree

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
use Clay::UI::Role::Interaction::HasFocusOrder;

class My::Input :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Focusable)
{}

# A form whose first Tab goes to the toolbar, although it comes last.
class My::Form :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::HasFocusOrder)
{
        field $toolbar :param :reader;

        method get_next_focus () {
                return $toolbar unless defined $self->ui->interaction->get_focused_widget;
                return $self->default_next_focus;
        }

        method get_previous_focus () {
                return $self->default_previous_focus;
        }
}

my $toolbar = My::Input->new(id => 'toolbar');
my $form    = My::Form->new(id => 'form', toolbar => $toolbar);
$form->add_child(My::Input->new(id => 'name'), My::Input->new(id => 'email'), $toolbar);
my $ui = Clay::UI->new(width => 400, height => 300, root => $form);

for (1 .. 4) {
        $ui->interaction->focus_next;
        say $ui->interaction->get_focused_widget->id;   # toolbar, name, email, toolbar
}
```

# DESCRIPTION

By default, `focus_next` and `focus_previous`
([Clay::UI::Interaction](../../Interaction.md)) move the focus in the depth-first pre-order
of the widget tree. A widget that composes this role decides the order
inside its subtree instead. It does not need to take the focus itself:
HasFocusOrder does not imply [Clay::UI::Role::Interaction::Focusable](Focusable.md).

Which widget decides:

- With a focused widget: the nearest widget composing HasFocusOrder among
the focused widget and its ancestors. When there is none, the default
order applies.
- With nothing focused: the root widget of the [Clay::UI](../../../UI.md), if it
composes HasFocusOrder; otherwise the default order applies.

The deciding widget's ["get\_next\_focus"](#get_next_focus) (for `focus_next`) or
["get\_previous\_focus"](#get_previous_focus) (for `focus_previous`) is called without
arguments and must return one of:

- `undef`

    The focus stays where it is.

- a Focusable widget of the same Clay::UI

    It gets the focus, unless its `can_focus` is 0 at that moment; then
    the focus stays where it is.

Anything else is a bug in the composing class: a non-widget, a widget
that does not compose [Clay::UI::Role::Interaction::Focusable](Focusable.md), or a
widget that is not part of this Clay::UI. `focus_next` /
`focus_previous` then die with
`Clay::UI::Interaction: <class> returned ...`, naming the class
and the problem.

The role composes [Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md) (for `ui`).

# REQUIRED METHODS

The composing class must implement both.

## get\_next\_focus

```perl
method get_next_focus () { ... }
```

Returns the widget that should get the focus on `focus_next`, or
`undef` to keep it. `$self->ui->interaction->get_focused_widget`
tells where the focus is now (`undef` when nothing is focused).

## get\_previous\_focus

```perl
method get_previous_focus () { ... }
```

Returns the widget that should get the focus on `focus_previous`, or
`undef`; the mirror of ["get\_next\_focus"](#get_next_focus).

# PROVIDED METHODS

## default\_next\_focus

```perl
return $self->default_next_focus;
return $self->default_next_focus(within => $self);
```

Returns the widget the default order would focus next from the
currently focused widget, ignoring every HasFocusOrder (see
["default\_next\_focus" in Clay::UI::Interaction](../../Interaction.md#default_next_focus)), or `undef` when no
widget can take the focus or this widget does not belong to a
Clay::UI. Use it for partial overrides: handle the special case, and
return `$self->default_next_focus` for everything else.

The arguments go to the tracker as they are. With
`within => $widget` (a focus scope, see
["Focus scopes" in Clay::UI::Interaction](../../Interaction.md#focus-scopes)) the order is limited to that
subtree and wraps around inside it, which is how a modal dialog keeps
Tab inside itself:

```perl
method get_next_focus ()     { return $self->default_next_focus(within => $self) }
method get_previous_focus () { return $self->default_previous_focus(within => $self) }
```

## default\_previous\_focus

```perl
return $self->default_previous_focus;
return $self->default_previous_focus(within => $self);
```

The mirror of ["default\_next\_focus"](#default_next_focus).

# SEE ALSO

["FOCUS" in Clay::UI::Interaction](../../Interaction.md#focus), ["focus\_next" in Clay::UI::Interaction](../../Interaction.md#focus_next),
[Clay::UI::Role::Interaction::Focusable](Focusable.md).
