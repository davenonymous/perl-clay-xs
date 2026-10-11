# NAME

Clay::UI::Role::Interaction::Hoverable - role for widgets that track the pointer hovering over them

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
use Clay::UI::Role::Interaction::Hoverable;

class My::Tile :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Interaction::Hoverable)
{}

my $tile = My::Tile->new(
        id     => 'tile',
        layout => { sizing => { width => sizing_grow(), height => sizing_grow() } },
);
$tile->on('OnHoverStart',   sub ($event) { say 'entered'; return });
$tile->on('OnHoverStopped', sub ($event) { say 'left';    return });

my $ui = Clay::UI->new(width => 100, height => 100, root => $tile);
$ui->render;
$ui->render(pointer_state => { x => 50, y => 50, down => 0 });     # entered
say $tile->is_hovered;                                             # 1
$ui->render(pointer_state => { x => 500, y => 500, down => 0 });   # left
```

# DESCRIPTION

A widget that composes this role is _hovered_ while the pointer is
over it, and receives:

- [Clay::UI::Events::OnHoverStart](../../Events/OnHoverStart.md) in the frame the pointer comes over
it;
- [Clay::UI::Events::OnHoverStopped](../../Events/OnHoverStopped.md) in the frame the pointer leaves it,
or at once when it is removed from the tree while hovered.

Neither event bubbles: every hovered widget, nested ones included, gets
its own. Widgets that do not compose Hoverable are never hovered and get
no hover events, although ["under\_pointer" in Clay::UI::Interaction](../../Interaction.md#under_pointer) lists
them.

No wiring is needed: ["render" in Clay::UI](../../../UI.md#render) finds the widgets under the
pointer and fires the events before it lays out the frame (see
["HOW A FRAME WORKS" in Clay::UI](../../../UI.md#how-a-frame-works)), so listeners may change the tree. The
pointer is tested against the previous frame's layout, so a widget can
be hovered from the frame after the one that first lays it out.

Hovering needs an element: composing Hoverable (or
[Clay::UI::Role::Interaction::Pressable](Pressable.md)) into a text widget dies at
construction with
`Clay::UI: <class> composes Clay::UI::Role::Interaction::Hoverable on a text node;
Clay cannot report the pointer over text elements - wrap the text in an Element`.
Make the element around the text hoverable instead.

The role composes [Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md),
[Clay::UI::Role::Events::Emitter](../Events/Emitter.md) and
[Clay::UI::Role::Style::HasStates](../Style/HasStates.md), which provides the derived state
`hovered`.

# METHODS

## is\_hovered

```perl
my $over = $widget->is_hovered;
```

Returns 1 while the pointer is over the widget, as of the last
["render" in Clay::UI](../../../UI.md#render) (or synthetic ["update" in Clay::UI::Interaction](../../Interaction.md#update)), and
0 otherwise. Returns 0 for a widget that does not belong to a
Clay::UI. A disabled widget ([Clay::UI::Role::Interaction::Disableable](Disableable.md))
is still hovered.

# SEE ALSO

[Clay::UI::Events::OnHoverStart](../../Events/OnHoverStart.md), [Clay::UI::Events::OnHoverStopped](../../Events/OnHoverStopped.md),
[Clay::UI::Role::Interaction::Pressable](Pressable.md), [Clay::UI::Interaction](../../Interaction.md).
