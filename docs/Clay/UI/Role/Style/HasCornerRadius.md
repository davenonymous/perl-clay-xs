# NAME

Clay::UI::Role::Style::HasCornerRadius - corner radius attribute for Clay::UI widgets

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Style::HasCornerRadius;

class My::Panel :strict(params)
        :does(Clay::UI::Role::Core::Container)
        :does(Clay::UI::Role::Style::HasCornerRadius)
{}

# The same radius on all four corners:
my $card = My::Panel->new(corner_radius => 6);

# Per corner: rounded at the top only.
my $tab = My::Panel->new(
        corner_radius => {
                top_left    => 6, top_right    => 6,
                bottom_left => 0, bottom_right => 0,
        },
);
```

# DESCRIPTION

`Clay::UI::Role::Style::HasCornerRadius` gives a widget the
`corner_radius` attribute. The widget adds it to its declaration (the
hash of settings Clay receives for the element) as `corner_radius`
(`cornerRadius` for Clay). Clay does not use it for layout; it passes
it on in the element's `RECTANGLE`, `BORDER`, `IMAGE` and `CUSTOM`
render commands, for the renderer to round the corners.
[Clay::UI::Box](../../Box.md), [Clay::UI::Grid](../../Grid.md) and [Clay::UI::Grid::Cell](../../Grid/Cell.md) compose
it.

# ATTRIBUTES

## corner\_radius

```perl
my $radius = $widget->corner_radius;    # read: a copy, or undef
$widget->corner_radius(8);
$widget->corner_radius({ top_left => 8, bottom_right => 8 });
```

A constructor parameter and a read/write accessor. The value is one of:

- undef

    No corner radius (the default); the declaration gets no corner radius.

- a number

    The radius of all four corners. It becomes `{ top_left => N,
    top_right => N, bottom_left => N, bottom_right => N }` in the
    declaration. Reading returns the number.

- a hash

    Any of the keys `top_left`, `top_right`, `bottom_left` and
    `bottom_right` (or Clay's camelCase; reading returns snake\_case); a
    key left out is 0.

The radii are finite numbers; Clay::UI does not reject negative ones.
See ["cornerRadius" in Clay::XS::Structs](../../../XS/Structs.md#cornerradius).

Reading returns a new copy (or undef); writing stores a copy of the
value. A write bumps the revision ([Clay::UI::Revision](../../Revision.md)), takes effect
at the next `render` and returns a copy of the new value. The value is
checked when it is set; anything else dies naming the attribute, for
example `Clay::UI: 'corner_radius' has unknown key ...`.

# METHODS

## contribute\_corner\_radius

Adds `corner_radius` to the widget's declaration while the attribute
is set (see ["EXTENDING THE DECLARATION" in Clay::UI::Role::Core::Element](../Core/Element.md#extending-the-declaration)).

# SEE ALSO

["cornerRadius" in Clay::XS::Structs](../../../XS/Structs.md#cornerradius), [Clay::UI::Box](../../Box.md).
