# NAME

Clay::UI::Role::Layout::HasSizingGroup - give unrelated widgets a common width or height

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::XS qw(padding_all CLAY_TOP_TO_BOTTOM);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;

class My::Box   :strict(params) :does(Clay::UI::Box) {}
class My::Label :strict(params) :does(Clay::UI::Text) {}

# Form labels in different rows, all as wide as the widest one.
my $form = My::Box->new(id => 'form', layout => { layout_direction => CLAY_TOP_TO_BOTTOM });
for my $caption ('Name', 'E-mail address', 'Phone') {
        my $row   = My::Box->new;
        my $label = My::Box->new(width_group => 1, layout => { padding => padding_all(4) });
        $label->add_child(My::Label->new(text => $caption));
        $row->add_child($label, My::Label->new(text => '...'));
        $form->add_child($row);
}

my $ui = Clay::UI->new(width => 800, height => 600, root => $form);
my $commands = $ui->render;
```

# DESCRIPTION

`Clay::UI::Role::Layout::HasSizingGroup` gives a widget the
`width_group` and `height_group` attributes. Every element widget has
them: [Clay::UI::Role::Core::Element](../Core/Element.md) composes this role.

Elements with the same non-zero `width_group` get the same width,
wherever they are in the tree: the width of the widest member. The same
holds for `height_group` and heights. Clay first sizes each element to
its content, then raises every member of a group to the largest size in
the group, before it hands out space to GROW elements. The width and
height ids are separate: width group 1 and height group 1 have nothing
to do with each other.

Typical uses are form labels of a common width and buttons of a common
height in different containers. [Clay::UI::Grid](../../Grid.md) sizes its columns and
rows with sizing groups and assigns the ids itself; use this role
directly for alignment a grid does not cover.

Sizing groups are a feature of the `clay.h` shipped with this
distribution (a patch to upstream Clay); see
["sizingGroup" in Clay::XS::Structs](../../../XS/Structs.md#sizinggroup).

## How sizing types take part

- FIT and GROW members are equalized. For GROW members, the group size
is computed from their content (FIT) size, before GROW space is shared
out.
- FIXED and PERCENT members are ignored: their size does not depend on
their content, so they neither raise the group size nor are raised.
- A member never exceeds its own maximum: with `sizing_fit(0, 50)` it
stays at most 50 wide even if another member is wider.
- Groups may nest: a member may contain members of other groups (a grid
inside a grid cell). Clay repeats the equalization until the sizes
settle. Groups that contain each other on the same axis are a cycle,
reported as the Clay error `CLAY_ERROR_TYPE_SIZING_GROUP_CYCLE`.
- Members share the group's largest _minimum_ as well (for text, its
longest word), so a parent that is too small compresses them like any
other children, down to that minimum, and text inside them wraps.
Members stay aligned as long as their parents compress alike (the rows
of a grid do); members in differently sized parents may end up with
different widths. Give members a maximum (`sizing_fit(0, 200)`,
`sizing_grow(0, 200)`) or a fixed width to wrap text at a chosen
width instead.

# ATTRIBUTES

## width\_group

```perl
my $group = $widget->width_group;    # 0: no group
$widget->width_group(17);
```

The width group of the widget: an integer from 0 to 2\*\*20 - 1
(1048575). `0`, the default, means no group. A constructor parameter
and a read/write accessor; a write of another group bumps the revision
([Clay::UI::Revision](../../Revision.md); writing the current group back changes nothing),
takes effect at the next `render` and returns the group in effect.

Dies with
`Clay::UI: 'width_group' must be an integer in 0..1048575 (larger ids are reserved for Clay::UI::Grid)`
for anything else.

Ids above that range belong to [Clay::UI::Grid](../../Grid.md), which writes them on
the cells it lays out (see ["GROUP IDS" in Clay::UI::Grid](../../Grid.md#group-ids)). On such a
cell:

- reading returns the grid's id; writing that same value back is allowed
and changes nothing, writing another id above the range dies;
- the grid's id is in effect while the grid (or a grid sharing its
columns) exists; on a cell kept after every such grid is freed it reads
`0` and the cell is sized alone;
- a cell removed from its grid drops the grid's ids (they become `0`);
an id you set yourself stays.

## height\_group

```perl
$widget->height_group(3);
```

The height group of the widget; the same rules as ["width\_group"](#width_group).

# METHODS

## contribute\_sizing\_group

Adds the `sizing_group` part (`{ width => ..., height => ... }`)
to the widget's declaration while at least one of the two groups in
effect is non-zero (see
["EXTENDING THE DECLARATION" in Clay::UI::Role::Core::Element](../Core/Element.md#extending-the-declaration)).

# SEE ALSO

[Clay::UI::Grid](../../Grid.md), ["sizingGroup" in Clay::XS::Structs](../../../XS/Structs.md#sizinggroup), [Clay::Manual](../../../Manual.md).
