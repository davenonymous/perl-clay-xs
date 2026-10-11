# NAME

Clay::UI::Role::Core::Container - element widget role with public child mutators

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::UI::Role::Core::Container;
use Clay::UI::Text;

class My::Panel :strict(params) :does(Clay::UI::Role::Core::Container) {}
class My::Label :strict(params) :does(Clay::UI::Text) {}

my $panel  = My::Panel->new(id => 'panel');
my $header = My::Panel->new(id => 'header');
my $body   = My::Panel->new(id => 'body');

my $footer = My::Label->new(text => 'footer');

$panel->add_child($header)->add_child($body, $footer);
$panel->remove_child($footer) if $panel->has_child($footer);
$panel->remove_child_with_id('body');
$panel->remove_children_with(sub { $_->isa('My::Label') });
$panel->clear_children;
```

# DESCRIPTION

`Clay::UI::Role::Core::Container` extends
[Clay::UI::Role::Core::Element](Element.md) with the public methods that change a
widget's children. [Clay::UI::Box](../../Box.md), [Clay::UI::Grid::Cell](../../Grid/Cell.md) and
[Clay::UI::Role::Layout::HasScroll](../Layout/HasScroll.md) compose it. [Clay::UI::Grid](../../Grid.md) does
not: a grid's children are its rows, changed through `append_row` and
the other row methods.

All methods follow ["ATTACHING CHILDREN" in Clay::UI::Role::Core::Element](Element.md#attaching-children):
new children are checked as a whole before anything changes, every
change bumps the revision ([Clay::UI::Revision](../../Revision.md)), and removed children
are detached and can be attached again (see
["ATTACHING AND REMOVING" in Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md#attaching-and-removing)). Changes
show from the next `render` on. None of these methods see the internal
children of ["add\_internal\_children" in Clay::UI::Role::Core::Element](Element.md#add_internal_children).

# METHODS

## add\_child

```perl
$widget->add_child(@kids);
```

Appends one or more widgets, in the given order. Each must be a widget
(composing [Clay::UI::Role::Core::Element](Element.md) or
[Clay::UI::Role::Core::TextNode](TextNode.md)) without a parent: never attached, or
removed since. Returns the widget, so calls chain:

```perl
$root->add_child($header)->add_child($body, $footer);
```

Dies, changing nothing, for the cases listed in
["ATTACHING CHILDREN" in Clay::UI::Role::Core::Element](Element.md#attaching-children), for example
`Clay::UI: widget ... is still attached to a parent; remove it first`.

## insert\_children

```perl
$widget->insert_children($offset, @kids);
```

Like ["add\_child"](#add_child), but puts the widgets before the child at index
`$offset` (0 inserts them first, the number of children appends). The
children already there keep their state: none is detached. Returns the
widget. Dies, changing nothing, like ["add\_child"](#add_child), and with
`Clay::UI: child offset ... out of range 0..N` for an offset that is
not an index of the children or the count of them: anything but an
integer in plain decimal digits from 0 to N (`'abc'`, `0.5`, `-1`,
`'01'`, undef and references die).

## clear\_children

```perl
$widget->clear_children;
```

Removes and detaches every child. Returns the widget.

## remove\_child

```perl
$widget->remove_child($footer);
$widget->remove_child(@kids);
```

Removes and detaches each given widget that is a direct child, compared
by identity, so widgets without an id and text widgets are removed as
well. A widget that is not a direct child (never attached, attached
elsewhere, a grandchild or an internal child) is ignored and keeps its
parent. Returns the widget. Dies, changing nothing, with
`Clay::UI: remove_child takes widgets, got ...` for anything but a
widget; to remove by id use ["remove\_child\_with\_id"](#remove_child_with_id). Ask
["has\_child" in Clay::UI::Role::Core::Element](Element.md#has_child) whether a widget is a
child.

## remove\_child\_with\_id

```perl
$widget->remove_child_with_id('body');
```

Removes and detaches every direct child whose `id` equals the argument
(string comparison). Children without an id and text widgets are never
matched. An id no child has is ignored. Returns the widget. Dies with
`Clay::UI: remove_child_with_id takes an id string, got ...` for undef
or a reference.

## remove\_children\_with

```perl
$widget->remove_children_with(sub { ($_->id // '') =~ /^tmp-/ });
$widget->remove_children_with(sub ($child) { $child->isa('My::Row') });
```

Removes and detaches every direct child for which
`$predicate->($child)` is true. `$_` is set to the child as well.
Text widgets are passed too; their `id` is undef.
Returns the widget. Dies with
`Clay::UI: remove_children_with takes a code reference, got ...` for
anything else.

If a removal releases the focused or hovered widget and one of the
resulting `OnBlur` / `OnHoverStopped` listeners dies, the removal
still completes and the method then dies with the listener's error
(this applies to all removal methods).

# SEE ALSO

[Clay::UI::Role::Core::Element](Element.md), [Clay::UI::Box](../../Box.md),
[Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md).
