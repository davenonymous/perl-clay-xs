# NAME

Clay::UI::Role::Style::HasBorder - border attributes for Clay::UI widgets

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Style::HasBorder;

class My::Panel :strict(params)
        :does(Clay::UI::Role::Core::Container)
        :does(Clay::UI::Role::Style::HasBorder)
{}

# The same width on all four sides:
my $framed = My::Panel->new(border_color => [100, 100, 100, 255], border_width => 2);

# Per side, plus lines between the children:
my $list = My::Panel->new(
        border_color => [100, 100, 100, 255],
        border_width => {
                left => 1, right => 1, top => 0, bottom => 0,
                between_children => 1,
        },
);

$framed->border_width(undef);    # no border
```

# DESCRIPTION

`Clay::UI::Role::Style::HasBorder` gives a widget the `border_color`
and `border_width` attributes. The widget adds them to its declaration
(the hash of settings Clay receives for the element) as the `border`
part, `{ color => ..., width => ... }`. [Clay::UI::Box](../../Box.md),
[Clay::UI::Grid](../../Grid.md) and [Clay::UI::Grid::Cell](../../Grid/Cell.md) compose it.

Clay emits a border render command for the element when at least one
width is greater than 0, whatever the colour, even with an alpha of 0;
`border_color` alone draws nothing. To hide a border, set its widths to
0 (or `border_width` to undef), not the colour's alpha to 0. The
renderer draws the border inside the element's box. Lines between
children (`between_children`) are emitted as rectangles and only when
the colour's alpha is greater than 0. See ["border" in Clay::XS::Structs](../../../XS/Structs.md#border).

# ATTRIBUTES

Both attributes are constructor parameters and read/write accessors.
Reading returns a new copy (or undef); writing stores a copy of the
value, so changing the array or hash afterwards does not change the
widget. A write bumps the revision ([Clay::UI::Revision](../../Revision.md)), takes
effect at the next `render` and returns a copy of the new value.
Values are checked when they are set, at construction or by the
accessor; a bad value dies naming the attribute.

## border\_color

```perl
$widget->border_color([100, 100, 100, 255]);
$widget->border_color({ r => 100, g => 100, b => 100, a => 255 });
```

The border colour: undef (the default) or a colour, either `[$r, $g,
$b, $a]` (exactly four numbers) or `{ r, g, b, a }` (a channel
left out is 0). Channels are finite numbers, by convention 0 to 255.
Without a `border_color`, a border that has a width is drawn with the
colour `[0, 0, 0, 0]` (transparent black). Errors as for
["background\_color" in Clay::UI::Role::Style::HasBackground](HasBackground.md#background_color).

## border\_width

```perl
$widget->border_width(2);
$widget->border_width({ left => 2, bottom => 1 });
```

The border widths: undef (the default, no border), a number or a hash.

- a number

    The width of all four outer sides. It is an integer from 0 to 65535
    and becomes `{ left => N, right => N, top => N, bottom => N,
    between_children => 0 }` in the declaration. Reading returns the
    number.

- a hash

    Any of the keys below, each an integer from 0 to 65535; a key left out
    is 0.

    - left, right, top, bottom

        The width of that outer side.

    - between\_children

        `between_children` (camelCase `betweenChildren`, read back as
        `between_children`) draws a line of that
        width between neighbouring children, in the middle of the
        `child_gap`. These lines are emitted as rectangles and only when the
        colour's alpha is greater than 0.

Dies for anything else, for example
`Clay::UI: 'border_width' expected an integer in 0..65535, got '1.5'`.

# METHODS

## contribute\_border

Adds the `border` part to the widget's declaration while
`border_color` or `border_width` is set (see
["EXTENDING THE DECLARATION" in Clay::UI::Role::Core::Element](../Core/Element.md#extending-the-declaration)).

# SEE ALSO

["border" in Clay::XS::Structs](../../../XS/Structs.md#border), [Clay::UI::Box](../../Box.md).
