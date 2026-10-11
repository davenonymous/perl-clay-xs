# NAME

Clay::UI::Role::Interaction::Pressable - role for widgets that can be pressed and clicked

# SYNOPSIS

```perl
use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad;
use Clay::XS qw(sizing_grow);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Role::Interaction::Pressable;

class My::Button :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Pressable)
{}

my $button = My::Button->new(
        id     => 'go',
        layout => { sizing => { width => sizing_grow(), height => sizing_grow() } },
);
$button->on('OnPress', sub ($event) {
        say 'pressed at ', $event->x, ',', $event->y;
        return;
});
$button->on('OnRelease', sub ($event) { say 'clicked'; return });

my $ui = Clay::UI->new(width => 100, height => 100, root => $button);
$ui->render;
$ui->render(pointer_state => { x => 20, y => 30, down => 1 });   # pressed at 20,30
say $button->is_pressed;                                         # 1
$ui->render(pointer_state => { x => 20, y => 30, down => 0 });   # clicked
```

# DESCRIPTION

A widget that composes this role can be pressed. Pressable composes
[Clay::UI::Role::Interaction::Hoverable](Hoverable.md), so a Pressable is also
hovered and gets the hover events.

The UI's interaction tracker fires the press events in the frame in
which it sees the pointer button go down or up; the full rules are in
["PRESS AND RELEASE" in Clay::UI::Interaction](../../Interaction.md#press-and-release):

- [Clay::UI::Events::OnPress](../../Events/OnPress.md)

    When the button goes down, at exactly one widget: the enabled
    Pressable under the pointer that is drawn on top. A button inside a
    pressable card gets the press, not the card; of two overlapping
    siblings, the later one gets it. Every enabled Pressable under the
    pointer becomes _armed_.

- [Clay::UI::Events::OnRelease](../../Events/OnRelease.md)

    When the button goes up, at the topmost armed Pressable still under the
    pointer: a completed click. A press on a button inside a pressable card
    that is dragged off the button and released over the card gives the
    card its `OnRelease`, since the press armed both. Releasing over no
    armed widget (press, drag off everything, release; or press elsewhere,
    drag in, release) fires nothing. Every release disarms all widgets.

Both events bubble with `IF_CONTINUE`: an ancestor sees the event
when the widget has no listener for it or all its listeners return
`Clay::UI::Enum::Result->CONTINUE`, and it sees the bubbled event,
never a second event of its own.

A Pressable that also composes
[Clay::UI::Role::Interaction::Disableable](Disableable.md) takes no part while
disabled: it is never armed or pressed and gets neither event. A press
over a disabled Pressable is absorbed, as in HTML: a pressable card
around a disabled button gets no `OnPress` either (see
["PRESS AND RELEASE" in Clay::UI::Interaction](../../Interaction.md#press-and-release)).

Clay::UI has no separate click event; combine `OnPress` and
`OnRelease` as you need:

```perl
# A completed click (pressed and released over the button):
$button->on('OnRelease', sub ($event) { activate(); return });

# Short click or long press:
my $down_at;
$button->on('OnPress',   sub ($event) { $down_at = time; return });
$button->on('OnRelease', sub ($event) {
        (time - $down_at) < 1 ? short_click() : long_press();
        return;
});
```

The role composes [Clay::UI::Role::Interaction::Hoverable](Hoverable.md) (and
through it [Clay::UI::Role::Events::Emitter](../Events/Emitter.md) and
[Clay::UI::Role::Style::HasStates](../Style/HasStates.md), which provides the derived state
`pressed`).

# METHODS

## is\_pressed

```perl
my $down = $widget->is_pressed;
```

Returns 1 while the widget is pressed: armed by a press, enabled, under
the pointer, and the button still down, as of the last
["render" in Clay::UI](../../../UI.md#render) (or synthetic ["update" in Clay::UI::Interaction](../../Interaction.md#update)).
Dragging off the widget clears it; dragging back on, with the button
still down, sets it again; removing the widget from the tree drops it.
Returns 0 otherwise, and for a widget that does not belong to a
Clay::UI.

# SEE ALSO

[Clay::UI::Events::OnPress](../../Events/OnPress.md), [Clay::UI::Events::OnRelease](../../Events/OnRelease.md),
["PRESS AND RELEASE" in Clay::UI::Interaction](../../Interaction.md#press-and-release),
[Clay::UI::Role::Interaction::Hoverable](Hoverable.md).
