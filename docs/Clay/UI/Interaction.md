# NAME

Clay::UI::Interaction - hover, press and focus state of a Clay::UI

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Role::Interaction::Pressable;
use Clay::UI::Role::Interaction::Focusable;

class My::Panel  :strict(params) :does(Clay::UI::Box) {}
class My::Button :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Pressable)
        :does(Clay::UI::Role::Interaction::Focusable)
{}

my $save   = My::Button->new(id => 'save');
my $cancel = My::Button->new(id => 'cancel');
my $root   = My::Panel->new(id => 'root');
$root->add_child($save, $cancel);
my $ui = Clay::UI->new(width => 400, height => 300, root => $root);

$save->on('OnRelease', sub ($event) { say 'save clicked'; return });

my $interaction = $ui->interaction;

# Synthetic input, for example in a test or for keyboard activation:
$interaction->update(over => [ $root, $save ], down => 1, x => 40, y => 12);
$interaction->update(over => [ $root, $save ], down => 0, x => 40, y => 12);

$interaction->is_hovered($save);    # 1, also $save->is_hovered
$interaction->is_pressed($save);    # 0: the button is up again
my $widgets = $interaction->under_pointer;   # [ $root, $save ]

# Focus, for example from a Tab key handler:
$interaction->focus_next;                    # focuses $save
$interaction->focus_next;                    # focuses $cancel
$interaction->set_focused_widget($save);
my $focused = $interaction->get_focused_widget;   # $save
$interaction->has_focus_within($root);       # 1: $save is below it
my @tab_stops = $interaction->focusables;    # ($save, $cancel)
```

# DESCRIPTION

Every [Clay::UI](../UI.md) owns one interaction tracker, returned by
`$ui->interaction`. The tracker holds:

- which widgets are _hovered_ ([Clay::UI::Role::Interaction::Hoverable](Role/Interaction/Hoverable.md)
widgets under the pointer),
- which are _armed_ ([Clay::UI::Role::Interaction::Pressable](Role/Interaction/Pressable.md) widgets
that were under the pointer when it went down, until it goes up),
- which are _pressed_ (armed, enabled, under the pointer, button down),
- and which widget has the _focus_
([Clay::UI::Role::Interaction::Focusable](Role/Interaction/Focusable.md)).

It turns pointer input into changes of these sets and fires the events
that go with them (`OnHoverStart`, `OnHoverStopped`, `OnPress`,
`OnRelease`, `OnScroll`, `OnFocus`, `OnBlur`; see
["EVENTS" in Clay::UI](../UI.md#events)). `$ui->render` passes it the real pointer
every frame through ["update"](#update); you may call `update` with synthetic
input between frames. Synthetic state lasts until the next `render`
reports where the real pointer is.

The widget readers `is_hovered`, `is_pressed` and `is_focused`, and
the derived `hovered`, `pressed` and `focused` states of
[Clay::UI::Role::Style::HasStates](Role/Style/HasStates.md), ask this object. Widgets hold no
interaction state of their own.

Whenever the hovered, armed, pressed or focused widgets change, the
tracker bumps the revision ([Clay::UI::Revision](Revision.md)), because widgets may
look different in those states.

# CONSTRUCTOR

## new

```perl
my $interaction = Clay::UI::Interaction->new(ui => $ui, tree_order => $sorter);
```

[Clay::UI](../UI.md) creates its tracker itself (read it with
["interaction" in Clay::UI](../UI.md#interaction)); you never need to. Both parameters are
required; unknown parameters die.

## ui

The [Clay::UI](../UI.md) the tracker belongs to. The tracker holds it weakly;
the methods that need it die once it is freed, with
`Clay::UI::Interaction::update: its Clay::UI no longer exists` (the
method's own name in place of `update`).

## tree\_order

A coderef called as `$sorter->(@widgets)` that returns the widgets
in the tree order of the last layout (depth-first pre-order). Events of
one kind fire in this order. Clay::UI passes a coderef that asks its
last completed frame. `new` dies with
`Clay::UI::Interaction: 'tree_order' must be a coderef` for anything
else.

# POINTER METHODS

## update

```perl
$interaction->update(
        over     => [ $panel, $button ],   # widgets under the pointer, topmost root first
        down     => 1,                     # button state
        x        => 40,                    # pointer position for OnPress / OnRelease
        y        => 12,
        scrolled => [ [ $list, 0, -30 ] ], # scroll containers that moved
);
```

Processes one pointer frame: changes the hovered, armed and pressed
widgets, then fires the events. ["render" in Clay::UI](../UI.md#render) calls it every
frame; call it yourself to feed synthetic input. Named arguments:

- over

    Required. Arrayref of the widgets under the pointer, in Clay's
    pointer-over order: the topmost floating element first, and each
    floating element (or the main tree) in depth-first pre-order. Within
    one such root, a later widget is therefore a descendant of an earlier
    one or drawn over it. Every widget must belong to this Clay::UI. Only
    Hoverable widgets become hovered and only Pressable widgets can be
    armed or pressed; ["under\_pointer"](#under_pointer) reports all of them.

- down

    Required. Whether the pointer button is down, a plain boolean. A change
    from up to down is a _press_, from down to up a _release_.

- x
- y

    Optional. The pointer position that `OnPress` and `OnRelease` carry;
    finite numbers, default 0.

- scrolled

    Optional. Arrayref of `[ $widget, $delta_x, $delta_y ]` entries, one
    per scroll container (a widget composing
    [Clay::UI::Role::Layout::HasScroll](Role/Layout/HasScroll.md)) that moved; each gets an
    `OnScroll` with those deltas. A widget may appear only once.

Order of work:

1. All state changes happen first: hover, arming, pressing (see
["PRESS AND RELEASE"](#press-and-release)), and the list behind ["under\_pointer"](#under_pointer).
2. Then the events fire in this order: every `OnHoverStopped`, every
`OnHoverStart`, `OnPress`, `OnRelease`, every `OnScroll`. Events of
one kind fire in tree order; widgets the last layout did not reach come
after the others, in the depth-first pre-order of the tree they are in
now.
3. Every event fires even if a listener dies; `update` then rethrows the
first error.

An event that an earlier listener of the same call made stale is
dropped: `OnPress`, `OnRelease` and `OnScroll` for a widget that has
left the tree, `OnHoverStart` for a widget that is no longer hovered,
`OnHoverStopped` for one that is hovered again. A widget gets
`OnHoverStopped` only after its `OnHoverStart`, and `OnBlur` only
after its `OnFocus`.

Listeners may change the tree and the focus, but may not call
`update` again, and that includes listeners of the events
`$ui->render` fires.

Returns nothing. Dies (all messages start with
`Clay::UI::Interaction::update:`) for an unknown argument, a missing
`over` or `down`, a reference as `down`, a non-finite `x` or `y`,
a widget in `over` or `scrolled` that does not belong to this
Clay::UI (`'over' must hold widgets of this Clay::UI`), a malformed
`scrolled` entry, a `scrolled` widget that is no scroll container, a
widget listed twice in `scrolled`, and a call from one of its own
listeners (`called from one of its own listeners`). Also dies with
`Clay::UI::Interaction::update: its Clay::UI no longer exists`.

## under\_pointer

```perl
my $widgets = $interaction->under_pointer;
```

Returns a new arrayref of the widgets of the last `update`'s `over`
(normally: under the pointer at the last `render`), in that order,
Hoverable or not. Widgets that have been freed or removed from the
tree since are left out.

## is\_hovered

```perl
my $bool = $interaction->is_hovered($widget);
```

Returns 1 while `$widget` is hovered, 0 otherwise.
["is\_hovered" in Clay::UI::Role::Interaction::Hoverable](Role/Interaction/Hoverable.md#is_hovered) asks this.

## is\_armed

```perl
my $bool = $interaction->is_armed($widget);
```

Returns 1 while `$widget` is armed (see ["PRESS AND RELEASE"](#press-and-release)), 0
otherwise.

## is\_pressed

```perl
my $bool = $interaction->is_pressed($widget);
```

Returns 1 while `$widget` is pressed, 0 otherwise.
["is\_pressed" in Clay::UI::Role::Interaction::Pressable](Role/Interaction/Pressable.md#is_pressed) asks this.

# PRESS AND RELEASE

Only enabled Pressables take part: a widget composing
[Clay::UI::Role::Interaction::Disableable](Role/Interaction/Disableable.md) that is disabled is never
armed or pressed, although it is still hovered. Below, _candidates_
are the enabled Pressables in `over`, in `over`'s order, unless the
Pressable the pointer lands on (the origin, chosen by the rule below
among all Pressables in `over`, enabled or not) is disabled: then there
are no candidates. A disabled widget absorbs the click, as a disabled
button does in HTML. Pressing a disabled button inside a pressable card
arms and presses nothing, and the card gets neither `OnPress` nor
`OnRelease`; dragging a pressed card onto its disabled button unpresses
the card. A disabled card around an enabled button does not stop the
button.

- Press

    On a press (`down` changes from false to true), every candidate
    becomes armed, and one of them gets `OnPress`: the _origin_.

- Origin

    Start with the first candidate. Walk through the remaining candidates
    in order; a candidate replaces the current pick unless it is an
    ancestor of the current pick, or it lies in a different _root_ than
    the first candidate. A widget's root is its nearest ancestor (or
    itself) that composes [Clay::UI::Role::Layout::HasFloating](Role/Layout/HasFloating.md) with a
    `floating` setting whose `attach_to` is not `CLAY_ATTACH_TO_NONE`;
    widgets without such an ancestor share the main root. The last pick is
    the origin.

    In effect: of nested Pressables the innermost one wins (a button inside
    a pressable card); of overlapping siblings, such as the children of a
    `CLAY_BACK_TO_FRONT` container, the later one wins; a Pressable inside
    a floating element beats every Pressable below that element, because
    Clay lists the topmost floating element first.

- Pressed

    After every `update`, a Pressable is pressed when it is armed, enabled
    and in `over`, and `down` is true. Dragging off an armed widget
    unpresses it; dragging back on (button still down) presses it again.
    Dragging onto a widget that was not armed does not press it.

- Release

    On a release (`down` changes from true to false), the origin is chosen
    again by the same rule, but only among the candidates that are armed.
    It gets `OnRelease`: a completed click. Then every widget is disarmed.
    A press on a button inside a pressable card that is dragged off the
    button and released over the card gives the card its `OnRelease`,
    because the press armed both. A release over no armed candidate fires
    nothing.

`OnPress` and `OnRelease` bubble with `IF_CONTINUE`
([Clay::UI::Enum::Bubble](Enum/Bubble.md)): the card in the example above sees the
button's `OnPress` only as a bubbled event, when the button has no
`OnPress` listener or all its listeners return
`Clay::UI::Enum::Result->CONTINUE`.

# FOCUS

The focus is held by at most one widget, a
[Clay::UI::Role::Interaction::Focusable](Role/Interaction/Focusable.md) of this UI. It changes only
through:

- ["set\_focused\_widget"](#set_focused_widget), ["focus\_next"](#focus_next) and ["focus\_previous"](#focus_previous);
- the removal of a subtree that holds the focused widget (it gets
`OnBlur`, see ["REMOVED WIDGETS"](#removed-widgets));
- the focused widget becoming unable to take the focus, through
`can_focus(0)` or by being disabled (it gets `OnBlur`, see
["release\_ineligible"](#release_ineligible)).

`render` never moves the focus. Event listeners, pointer listeners
included, may move it.

The focus follows the widget tree as it is now, while pointer events
follow the tree of the last layout: the focus must work before the
first `render` and right after the tree changed, whereas the pointer
was tested against the last layout.

["set\_focused\_widget"](#set_focused_widget), ["focus\_next"](#focus_next), ["focus\_previous"](#focus_previous),
["focusables"](#focusables), ["default\_next\_focus"](#default_next_focus) and ["default\_previous\_focus"](#default_previous_focus)
die with
`Clay::UI::Interaction::<method>: its Clay::UI no longer exists`
once the Clay::UI that owns this tracker has been freed.

## Focus scopes

["focusables"](#focusables), ["default\_next\_focus"](#default_next_focus) and ["default\_previous\_focus"](#default_previous_focus)
take an optional `within => $widget`: the _focus scope_, a
subtree of this UI (`$widget` and every widget below it in layout
pre-order, see ["descendants" in Clay::UI::Role::Core::Element](Role/Core/Element.md#descendants)). Without
it they cover the whole tree. A modal dialog keeps Tab inside itself
with a HasFocusOrder that steps within its own subtree (see
["default\_next\_focus" in Clay::UI::Role::Interaction::HasFocusOrder](Role/Interaction/HasFocusOrder.md#default_next_focus)).
`within` must be a widget of this UI; anything else dies with
`Clay::UI::Interaction::<method>: 'within' must be a widget of this Clay::UI`,
and another argument dies with
`Clay::UI::Interaction::<method>: unknown argument(s): ...`.

## get\_focused\_widget

```perl
my $widget = $interaction->get_focused_widget;
```

Returns the widget that has the focus, or `undef` when none has it (or
the focused widget has been freed; the tracker holds it weakly).

## is\_focused

```perl
my $bool = $interaction->is_focused($widget);
```

Returns 1 when `$widget` has the focus, 0 otherwise.
["is\_focused" in Clay::UI::Role::Interaction::Focusable](Role/Interaction/Focusable.md#is_focused) asks this.

## has\_focus\_within

```perl
my $bool = $interaction->has_focus_within($panel);
```

Returns 1 when the focused widget is `$panel` or below it (also below
an internal child), 0 otherwise, also when nothing is focused. Use it
to draw a panel differently while the keyboard is in it, or to close a
popup once the focus left it. Dies with
`Clay::UI::Interaction::has_focus_within: takes a widget, got ...` for
anything but a widget.

## focusables

```perl
my @widgets = $interaction->focusables;
my @inside  = $interaction->focusables(within => $dialog);
```

Returns the widgets of the scope (see ["Focus scopes"](#focus-scopes); the scope's
own widget included) that can take the focus now (["can\_take\_focus"](#can_take_focus)),
in depth-first pre-order of the current tree. Disabled widgets and
widgets whose `can_focus` is false are left out.

## can\_take\_focus

```perl
my $bool = $interaction->can_take_focus($widget);
```

Returns 1 when ["set\_focused\_widget"](#set_focused_widget) would accept `$widget` now: it
composes [Clay::UI::Role::Interaction::Focusable](Role/Interaction/Focusable.md), belongs to this UI
(and is not being removed), and its `can_focus` is true. Returns 0
otherwise, also for a non-widget. Use it to find a widget to focus, for
example the nearest ancestor of a clicked widget that can take the
focus:

```perl
my $target = $clicked;
$target = $target->parent until !defined $target || $interaction->can_take_focus($target);
$interaction->set_focused_widget($target) if defined $target;
```

## set\_focused\_widget

```perl
$interaction->set_focused_widget($widget);
$interaction->set_focused_widget(undef);     # clear the focus
```

Gives the focus to `$widget`, or clears it for `undef`. Focusing the
widget that already has the focus, or clearing an empty focus, does
nothing (no events).

The target is checked before anything changes. Dies with
`Clay::UI::Interaction::set_focused_widget: target` followed by
`must be a blessed widget`,
`must consume Clay::UI::Role::Interaction::Focusable`,
`does not belong to this Clay::UI` or
`is not currently focusable (can_focus returned false)`.

Then the focus moves (the derived `focused` state moves with it), the
revision is bumped, and [Clay::UI::Events::OnBlur](Events/OnBlur.md) fires at the widget
that had the focus (if any), then [Clay::UI::Events::OnFocus](Events/OnFocus.md) at the
new one (if any). Both fire even if the first listener dies; the first
error is rethrown afterwards, with the focus already moved. An
`OnBlur` listener may move the focus again; the `OnFocus` of this
call is then dropped, since its widget no longer has the focus.

## focus\_next

```perl
$interaction->focus_next;
```

Moves the focus to the next widget, for example on Tab. Returns
nothing.

- Default order

    The depth-first pre-order of the current tree (children before the
    next sibling), skipping widgets whose `can_focus` is false and
    wrapping around at the end. With nothing focused, the first widget that
    can take the focus gets it. Internal children of widgets count like
    children.

- Custom order

    If the focused widget or one of its ancestors composes
    [Clay::UI::Role::Interaction::HasFocusOrder](Role/Interaction/HasFocusOrder.md), the nearest such widget
    decides: its `get_next_focus` is called. With nothing focused, the root
    widget decides if it composes HasFocusOrder. Its result must be `undef`
    (the focus stays), or a Focusable widget of this UI, which gets the
    focus (or the focus stays, when its `can_focus` is false right now).
    Anything else dies with
    `Clay::UI::Interaction: <class> returned ...`, naming the
    HasFocusOrder class and what was wrong.

## focus\_previous

```perl
$interaction->focus_previous;
```

Moves the focus to the previous widget, for example on Shift+Tab: the
mirror of ["focus\_next"](#focus_next). With nothing focused, the last widget that
can take the focus gets it; a HasFocusOrder decides through its
`get_previous_focus`.

## default\_next\_focus

```perl
my $widget = $interaction->default_next_focus;
my $inside = $interaction->default_next_focus(within => $dialog);
```

Returns the widget the default order (see ["focus\_next"](#focus_next)) would focus
next, ignoring every HasFocusOrder, or `undef` when no widget can take
the focus. Changes nothing. A HasFocusOrder widget calls it to fall
back to the default order (see
["default\_next\_focus" in Clay::UI::Role::Interaction::HasFocusOrder](Role/Interaction/HasFocusOrder.md#default_next_focus)).

With `within` (see ["Focus scopes"](#focus-scopes)) only the scope's widgets count:
the next one after the focused widget, wrapping around inside the
scope, or the first one when the focus is outside the scope or nothing
is focused.

## default\_previous\_focus

```perl
my $widget = $interaction->default_previous_focus;
my $inside = $interaction->default_previous_focus(within => $dialog);
```

The mirror of ["default\_next\_focus"](#default_next_focus): with the focus outside the scope,
the last widget of the scope.

## release\_ineligible

```perl
$interaction->release_ineligible($widget);
```

Drops what `$widget` may no longer have, at once. A disabled widget
stops being armed and pressed. A focused widget whose `can_focus` is
now false loses the focus and gets `OnBlur` before this returns, as
from `set_focused_widget(undef)`. A widget that may keep everything is
left alone. Bumps the revision when a state changed.

The `disabled` writer of [Clay::UI::Role::Interaction::Disableable](Role/Interaction/Disableable.md),
the `can_focus` writer of [Clay::UI::Role::Interaction::Focusable](Role/Interaction/Focusable.md)
and its `focus_eligibility_changed` call it; a class whose
`accepts_focus` answer changes calls `focus_eligibility_changed`
rather than this.

# REMOVED WIDGETS

When a subtree leaves the tree, the tracker releases it at once, during
the removal:

1. Its hovered widgets stop being hovered, its armed and pressed widgets
are dropped, its widgets leave ["under\_pointer"](#under_pointer), and the focus is
cleared if a widget inside it has it. The revision is bumped when a
state changed.
2. The hovered widgets get `OnHoverStopped` (in tree order) and the
focused widget gets `OnBlur`. The removed widgets are still attached
to their parents while these events fire, so `OnBlur` bubbles through
the old ancestors and `$event->target->parent` still works.

Armed or pressed widgets get no event: a pending click is simply
dropped, and the next release fires nothing for them.

While these events fire, the subtree already counts as gone: a listener
cannot hover, press or focus a widget inside it (`update` and
`set_focused_widget` die as for a widget of another UI). Every event
fires even if a listener dies; the first error is rethrown after the
children are detached.

## release\_subtrees

```perl
$interaction->release_subtrees(@top_widgets);
```

Does the above for every widget in `@top_widgets` and everything below
them. The child methods of [Clay::UI::Role::Core::Element](Role/Core/Element.md) (and so of
[Clay::UI::Role::Core::Container](Role/Core/Container.md) and [Clay::UI::Grid](Grid.md)) call it once
per change, with all removed children, while the children are still
attached. A widget class that detaches children some other way must
call it too; otherwise you do not call it yourself.

# SEE ALSO

[Clay::UI](../UI.md) (["HOW A FRAME WORKS" in Clay::UI](../UI.md#how-a-frame-works), ["EVENTS" in Clay::UI](../UI.md#events)),
[Clay::UI::Role::Interaction::Hoverable](Role/Interaction/Hoverable.md),
[Clay::UI::Role::Interaction::Pressable](Role/Interaction/Pressable.md),
[Clay::UI::Role::Interaction::Focusable](Role/Interaction/Focusable.md),
[Clay::UI::Role::Interaction::Disableable](Role/Interaction/Disableable.md),
[Clay::UI::Role::Interaction::HasFocusOrder](Role/Interaction/HasFocusOrder.md), [Clay::Manual](../Manual.md).
