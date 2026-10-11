# NAME

Clay::UI::Role::Layout::HasParent - parent, root and UI of a Clay::UI widget

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::UI;
use Clay::UI::Box;

class My::Box :strict(params) :does(Clay::UI::Box) {}

my $root  = My::Box->new(id => 'root');
my $panel = My::Box->new(id => 'panel');
my $child = My::Box->new;
$root->add_child($panel);
$panel->add_child($child);

my $ui = Clay::UI->new(width => 800, height => 600, root => $root);

$child->parent;    # $panel
$child->root;      # $root
$child->ui;        # $ui
$panel->contains($child);    # 1

$root->remove_child($panel);
$child->root;      # $panel: the removed subtree stands alone
$child->ui;        # undef
```

# DESCRIPTION

`Clay::UI::Role::Layout::HasParent` gives every widget its way up the
tree: `parent`, `root`, `ui` and `contains`, and the hook
`tree_changed` that tells a widget its place in a tree changed. [Clay::UI::Role::Core::Element](../Core/Element.md)
and [Clay::UI::Role::Core::TextNode](../Core/TextNode.md) compose it, so every element
widget and every text widget has these methods.

The parent reference is weak: it does not keep the parent alive. A
widget tree is held together by parents holding their children, and a
whole tree by the [Clay::UI](../../../UI.md) that has its root.

# METHODS

## parent

```perl
my $parent = $widget->parent;
```

Returns the widget this one is a child (or internal child) of. Returns
undef when the widget was never attached, was removed from its parent,
or its parent has been freed. Read-only: attaching and removing
(["ATTACHING AND REMOVING"](#attaching-and-removing)) set it.

## root

```perl
my $top = $widget->root;
```

Follows `parent` up to the topmost widget and returns it; for a widget
without a parent that is the widget itself. If an ancestor has been
freed, returns the highest ancestor still reachable. The walk runs on
every call; nothing is cached.

## ui

```perl
my $ui = $widget->ui;
```

Returns the [Clay::UI](../../../UI.md) whose tree this widget is part of: the UI
created with `Clay::UI->new(root => $root)` for the widget's
`root`. Returns undef when the widget is not part of a UI: not yet
attached to one, removed from it, or the UI has been freed (the
reference to the UI is weak).

## contains

```perl
if ($panel->contains($widget)) { ... }
```

Returns 1 when `$widget` is this widget or below it (it walks up from
`$widget` through `parent`, so internal children count), 0
otherwise. Works for element and text widgets on both sides. Dies with
`Clay::UI: contains takes a widget, got ...` for anything else. For
the list of widgets below an element, see
["descendants" in Clay::UI::Role::Core::Element](../Core/Element.md#descendants).

## tree\_changed

```perl
class My::Box :strict(params) :does(Clay::UI::Box) {}
class My::Panel :strict(params) :isa(My::Box) {
        method tree_changed :override () {
                $self->SUPER::tree_changed;
                say 'now in ', (defined $self->ui ? 'a UI' : 'no UI');
                return;
        }
}
```

A hook for widget classes that must react when their place in a tree
changes, for example to rebuild what depends on the UI they are in.
It does nothing here; you never call it yourself. Clay::UI calls it on
**every** widget of a subtree (the subtree's own widget first, then the
others in layout pre-order, internal children included, see
["descendants" in Clay::UI::Role::Core::Element](../Core/Element.md#descendants)) when the subtree's top
widget:

- gets a parent: `add_child`, `insert_children`, a row or cell a
[Clay::UI::Grid](../../Grid.md) adds, `add_internal_children`;
- loses its parent: every removal listed under ["ATTACHING AND REMOVING"](#attaching-and-removing);
- becomes the root of a [Clay::UI](../../../UI.md) (`Clay::UI->new(root => ...)`).

It runs once the change is complete: the parent slots are set or
cleared, and for a removal the leaving subtree's hover and focus are
released (its `OnHoverStopped` and `OnBlur` listeners have run), so
`parent` and `ui` answer the new place: `ui` is undef in a removed
subtree. A call that moves several subtrees (replacing a row, say)
completes every move before the first hook runs. Each widget gets one
call per change: a [Clay::UI::Grid](../../Grid.md) builds a new row (or the wrapper
of a new cell) completely before it puts it into the grid, and only
then announces it. Reordering children
(["reorder\_rows" in Clay::UI::Grid](../../Grid.md#reorder_rows)) changes no place and calls nothing.

Every hook runs even if one dies; the method that changed the tree
then dies with the first error, the tree already changed. When a
release listener died as well, its error (the earlier one) is the one
rethrown and hook errors are dropped, as later listener errors are.
For a subclass of Clay::UI, the hooks of the root's subtree run while
`Clay::UI->new` is still building the UI, before the subclass's
own ADJUST blocks: a hook must not rely on what those set up.

Override it in a subclass with `:override` and call
`$self->SUPER::tree_changed`: an Object::Pad class cannot override
a method of a role it composes itself, so the override goes into a
subclass of the class that composes the role (as in the example, and
as for ["accepts\_focus" in Clay::UI::Role::Interaction::Focusable](../Interaction/Focusable.md#accepts_focus)).
`_set_parent` and `_detach_parent`, which set and clear the parent
slot, are private to Clay::UI; do not override them.

# ATTACHING AND REMOVING

A widget can be attached whenever it has no parent. Attaching (for
example ["add\_child" in Clay::UI::Role::Core::Container](../Core/Container.md#add_child)) sets its parent;
attaching a widget that still has one dies with
`Clay::UI: widget ... is still attached to a parent; remove it first`,
whether the new parent is another widget or the same one again.

Removing a widget (`remove_child`, `remove_child_with_id`,
`remove_children_with`,
`clear_children`, a removed or replaced row or cell of a
[Clay::UI::Grid](../../Grid.md), `remove_internal_children`) detaches it:

- its `parent` becomes undef and it is the `root` of its own subtree;
- `ui` returns undef for the whole subtree;
- hover, press and focus inside the subtree are released on the way out,
with the usual `OnHoverStopped` and `OnBlur` events, so the subtree
is idle when it comes back.

A detached widget, like one whose parent has been freed, can be
attached again, to its old parent or another one, or become the root of
a new [Clay::UI](../../../UI.md). Once attached, the next `render` lays it out, and
it can be hovered and pressed from the frame after that (the pointer is
tested against the previous frame's layout). Without an `id` it gets the id derived from
its new position (see ["resolve\_id" in Clay::UI::Role::Core::Element](../Core/Element.md#resolve_id)).

The root of a [Clay::UI](../../../UI.md) belongs to that UI as long as the UI exists:
it cannot become a child, and a second Clay::UI on the same root dies.
The root refers to its UI weakly, so once the Clay::UI object is freed
the root is free again (it can become a child or the root of a new
Clay::UI).

# SEE ALSO

["ATTACHING CHILDREN" in Clay::UI::Role::Core::Element](../Core/Element.md#attaching-children),
[Clay::UI::Role::Core::Container](../Core/Container.md), [Clay::UI](../../../UI.md).
