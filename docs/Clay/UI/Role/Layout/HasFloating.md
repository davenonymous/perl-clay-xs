# NAME

Clay::UI::Role::Layout::HasFloating - floating attribute for Clay::UI widgets

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::XS qw(
        CLAY_ATTACH_TO_PARENT CLAY_ATTACH_POINT_CENTER_BOTTOM CLAY_ATTACH_POINT_CENTER_TOP
);
use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Layout::HasFloating;

class My::Tooltip :strict(params)
        :does(Clay::UI::Role::Core::Container)
        :does(Clay::UI::Role::Layout::HasFloating)
{}

# Below the parent, centred, 4 units lower, drawn above its siblings.
my $tooltip = My::Tooltip->new(
        floating => {
                attach_to     => CLAY_ATTACH_TO_PARENT,
                attach_points => {
                        parent  => CLAY_ATTACH_POINT_CENTER_BOTTOM,
                        element => CLAY_ATTACH_POINT_CENTER_TOP,
                },
                offset        => { x => 0, y => 4 },
                z_index       => 10,
        },
);

$tooltip->floating(undef);    # back to normal layout
```

# DESCRIPTION

`Clay::UI::Role::Layout::HasFloating` gives a widget the `floating`
attribute. A floating element is taken out of its parent's layout and
placed relative to another element (its parent, an element with a
given id, or the root), for tooltips, menus, popups and overlays. The
widget adds the value to its declaration (the hash of settings Clay
receives for the element) as the `floating` part.
[Clay::UI::Box](../../Box.md) composes this role.

# ATTRIBUTES

## floating

```perl
my $floating = $widget->floating;    # read: a copy, or undef
$widget->floating({ attach_to => CLAY_ATTACH_TO_ROOT, offset => { x => 10, y => 10 } });
$widget->floating(undef);            # not floating
```

A constructor parameter and a read/write accessor. The value is undef
(not floating) or a hashref with any of these keys (snake\_case, or
Clay's camelCase; the reader returns snake\_case):

- `attach_to`

    What the element is attached to: `CLAY_ATTACH_TO_NONE`,
    `CLAY_ATTACH_TO_PARENT`, `CLAY_ATTACH_TO_ELEMENT_WITH_ID` (the
    element named by `parent_id`) or `CLAY_ATTACH_TO_ROOT`. **The element
    floats only when `attach_to` is set to something other than
    `CLAY_ATTACH_TO_NONE`**, which is what an omitted `attach_to` means.

- `parent_id`

    For `CLAY_ATTACH_TO_ELEMENT_WITH_ID`: a numeric element id or an id
    hash from `Clay_GetElementId` (for a widget with an `id`,
    `Clay_GetElementId($widget->id)`).

- `attach_points`

    `{ element => CLAY_ATTACH_POINT_*, parent => CLAY_ATTACH_POINT_* }`:
    which point of the floating element is placed on which point of the
    element it is attached to. Both default to `CLAY_ATTACH_POINT_LEFT_TOP`.

- `offset`

    `{ x, y }` or `[x, y]`: moves the element from its attach point.

- `expand`

    `{ width, height }` or `[width, height]`: enlarges the box of
    the floating element by `width` on the left and on the right and by
    `height` at the top and at the bottom. Its render commands and
    ["bounding\_box" in Clay::UI](../../../UI.md#bounding_box) report the enlarged box, and its children are
    placed from the enlarged box's top-left corner (see
    ["expand" in Clay::XS::Structs](../../../XS/Structs.md#expand)).

- `z_index`

    An integer -32768 to 32767 for the element and everything inside it.
    Clay sorts floating elements by ascending `z_index`, so higher values
    are drawn later (on top).

- `pointer_capture_mode`

    `CLAY_POINTER_CAPTURE_MODE_CAPTURE` (the default; the element blocks
    pointer hits below it) or `CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH`.

- `clip_to`

    `CLAY_CLIP_TO_NONE` (the default; the element is not clipped by the
    scroll containers around it) or `CLAY_CLIP_TO_ATTACHED_PARENT`
    (clipped like the element it is attached to).

See ["floating" in Clay::XS::Structs](../../../XS/Structs.md#floating) for the exact Clay semantics.

Default undef: the declaration gets no `floating` part.

Reading returns a new deep copy (or undef); writing stores a deep copy
of the value, so changing a hash after passing it in, or one a read
returned, does not change the widget. A write replaces the whole hash,
bumps the revision ([Clay::UI::Revision](../../Revision.md)), takes effect at the next
`render` and returns a copy of the new value.

The value is checked when it is set, at construction or by the accessor:
anything but undef or a hashref of the keys above with values of the
right shape dies, naming the attribute and the key, for example
`Clay::UI: 'floating.z_index' expected an integer in -32768..32767, got '99999'`
or `Clay::UI: 'floating' has unknown key ...`.

# METHODS

## contribute\_floating

Adds the `floating` part (a new hash) to the widget's declaration
while `floating` is set (see
["EXTENDING THE DECLARATION" in Clay::UI::Role::Core::Element](../Core/Element.md#extending-the-declaration)).

# SEE ALSO

["floating" in Clay::XS::Structs](../../../XS/Structs.md#floating), [Clay::UI::Box](../../Box.md), [Clay::Manual](../../../Manual.md),
[Clay::Cookbook](../../../Cookbook.md).
