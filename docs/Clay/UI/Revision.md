# NAME

Clay::UI::Revision - process-wide counter that grows whenever a Clay::UI frame would look different

# SYNOPSIS

```perl
use v5.22;
use warnings;

use Object::Pad;
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Revision qw(current_revision);

class My::Panel :strict(params) :does(Clay::UI::Box) {}

my $root = My::Panel->new(id => 'root', background_color => [40, 50, 60, 255]);
my $ui   = Clay::UI->new(width => 800, height => 600, root => $root);

my $drawn;    # the revision of the frame on screen
for my $frame (1 .. 3) {
        # render runs every frame: input reaches the widgets only through it.
        my $commands = $ui->render(pointer_state => { x => 10, y => 10, down => 0 });
        next if defined $drawn && $drawn == $ui->laid_out_revision;
        $drawn = $ui->laid_out_revision;
        say "frame $frame: drawing ", scalar @$commands, ' commands';
}
$root->background_color([0, 0, 0, 255]);      # a change ...
say 'stale' if current_revision() != $drawn;   # ... makes the drawn frame stale
```

# DESCRIPTION

The _revision_ is a non-negative integer that grows whenever something
that a frame lays out or draws has changed. A renderer remembers the
revision of the frame it drew and skips drawing while the revision is
still the same. It still calls ["render" in Clay::UI](../UI.md#render) every frame: pointer
and scroll input reach the widgets only through `render`, and the
changes they cause (hover states, scrolling) bump the revision there.
["laid\_out\_revision" in Clay::UI](../UI.md#laid_out_revision) tells which revision a frame shows.

These bump the revision:

- every widget setter that changes what a frame lays out or draws:
attributes (`layout`, `background_color`, `text`, ...), the children
of a widget, user states (`add_state` and friends), `disabled`;
- the `width`, `height` and `measure_text` writers of a [Clay::UI](../UI.md);
- a change of the hovered, armed, pressed or focused widgets in a
[Clay::UI::Interaction](Interaction.md), because they drive the derived `hovered`,
`pressed` and `focused` states;
- a scroll container moving inside `render` (wheel input, drag
scrolling or the momentum after drag scrolling), ["scroll\_to" in Clay::UI](../UI.md#scroll_to) and
["set\_scroll\_position" in Clay::XS](../XS.md#set_scroll_position);
- `mark_changed` (["mark\_changed" in Clay::UI::Role::Core::Element](Role/Core/Element.md#mark_changed)), which
widget classes that keep state of their own call from their setters,
and `request_prepare` ([Clay::UI::Role::Core::Preparable](Role/Core/Preparable.md)).
- every frame in which Clay runs a transition handler
(["transition" in Clay::XS::Structs](../XS/Structs.md#transition)), that is, animates an element: its
render commands differ from the frame before, and the frame after the
last step shows the final state. The counting happens in [Clay::XS](../XS.md),
so the revision moves during `render`, after ["laid\_out\_revision" in Clay::UI](../UI.md#laid_out_revision)
was recorded; the next frame then shows a new revision.

Reading an attribute never bumps the revision; neither does writing
`can_focus`, which changes nothing drawn (unless it takes the focus
away).

There is one revision for the whole process, shared by every
Clay::UI: a change in any of them makes every renderer draw again. Only
equality is meaningful. The value starts at 0 and only grows, but how
far it grows per change is unspecified (one write may bump it more than
once).

# FUNCTIONS

Nothing is exported by default; import the functions by name.

## current\_revision

```perl
my $revision = current_revision();
```

Returns the current revision.

## bump\_revision

```perl
my $revision = bump_revision();
```

Increments the revision and returns the new value. Widget code calls it
from setters that change what a frame shows; most widget classes call
`$widget->mark_changed` instead, which does the same.

# SEE ALSO

["laid\_out\_revision" in Clay::UI](../UI.md#laid_out_revision), [Clay::UI](../UI.md), [Clay::Manual](../Manual.md).
