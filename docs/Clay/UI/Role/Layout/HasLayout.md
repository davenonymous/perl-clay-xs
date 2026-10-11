# NAME

Clay::UI::Role::Layout::HasLayout - layout attribute for Clay::UI widgets

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::XS qw(
        sizing_grow sizing_fixed padding_all CLAY_TOP_TO_BOTTOM CLAY_ALIGN_X_CENTER
);
use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Layout::HasLayout;

class My::Column :strict(params)
        :does(Clay::UI::Role::Core::Container)
        :does(Clay::UI::Role::Layout::HasLayout)
{}

my $column = My::Column->new(
        layout => {
                sizing           => { width => sizing_grow(), height => sizing_fixed(300) },
                padding          => padding_all(10),
                child_gap        => 4,
                child_alignment  => { x => CLAY_ALIGN_X_CENTER },
                layout_direction => CLAY_TOP_TO_BOTTOM,
        },
);

my $layout = $column->layout;                  # a copy
$layout->{child_gap} = 8;
$column->layout($layout);                      # write it back
```

# DESCRIPTION

`Clay::UI::Role::Layout::HasLayout` gives a widget the `layout`
attribute: how the element is sized, how much padding it has and how it
places its children. The widget adds it to its declaration (the hash of
settings Clay receives for the element) as the `layout` part.
[Clay::UI::Box](../../Box.md), [Clay::UI::Grid](../../Grid.md), [Clay::UI::Grid::Cell](../../Grid/Cell.md) and
[Clay::UI::Grid::Row](../../Grid/Row.md) compose it.

# ATTRIBUTES

## layout

```perl
my $layout = $widget->layout;           # read: a copy
$widget->layout({ child_gap => 8 });    # write: replaces the whole hash
$widget->layout({});                    # back to Clay's defaults
```

A constructor parameter and a read/write accessor. The value is a
hashref with any of these keys (snake\_case, or Clay's camelCase; the
reader returns snake\_case):

- `sizing`

    `{ width => $axis, height => $axis }`, each axis built with
    `sizing_fit`, `sizing_grow`, `sizing_fixed` or `sizing_percent`
    from [Clay::XS](../../../XS.md). An axis left out is FIT. A maximum of 0 means "no maximum",
    so `sizing_fixed(0)` does not make an element 0 wide: it behaves like
    FIT.

- `padding`

    `{ left, right, top, bottom }`, integers 0 to 65535;
    `padding_all($n)` from [Clay::XS](../../../XS.md) builds one. A single number dies.

- `child_gap`

    The space between children along the layout direction, an integer 0
    to 65535.

- `child_alignment`

    `{ x => CLAY_ALIGN_X_*, y => CLAY_ALIGN_Y_* }`.

- `layout_direction`

    `CLAY_LEFT_TO_RIGHT` (the default), `CLAY_TOP_TO_BOTTOM`,
    `CLAY_LEFT_TO_RIGHT_WRAP` (children flow into lines) or
    `CLAY_BACK_TO_FRONT` (children stacked on top of each other).

- `line_gap`

    For `CLAY_LEFT_TO_RIGHT_WRAP`: the space between lines, an integer 0
    to 65535.

- `line_sizing`

    For `CLAY_LEFT_TO_RIGHT_WRAP`: `CLAY_LINE_SIZING_FIT` or
    `CLAY_LINE_SIZING_GROW`.

See ["layout" in Clay::XS::Structs](../../../XS/Structs.md#layout) for what each field does in Clay.

Default `{}`: the declaration gets no `layout` part and Clay uses its
defaults (FIT on both axes, no padding, no gap, `CLAY_LEFT_TO_RIGHT`,
children at the left and top).

Reading returns a new deep copy; writing stores a deep copy of the
value, so changing a hash after passing it in, or one a read returned,
does not change the widget. A write replaces the whole hash (it does
not merge with the old one), bumps the revision
([Clay::UI::Revision](../../Revision.md)), takes effect at the next `render` and returns
a copy of the new value.

The value is checked when it is set, at construction or by the
accessor, and a bad value dies naming the attribute and the path inside
it, for example:

```text
Clay::UI: 'layout' has unknown key 'paddin' (known keys: sizing, padding, ...)
Clay::UI: 'layout.padding.left' expected an integer in 0..65535, got '-5'
Clay::UI: 'layout.padding' expected a hash reference, got '5' (padding_all(N) builds one)
Clay::UI: 'layout' must be defined
```

A key given in both spellings (`child_gap` and `childGap`) dies as
well.

# METHODS

## contribute\_layout

Adds the `layout` part to the widget's declaration (see
["EXTENDING THE DECLARATION" in Clay::UI::Role::Core::Element](../Core/Element.md#extending-the-declaration)). It writes
nothing while `layout` is empty. Otherwise it merges the widget's
`layout` over a `layout` part another role already wrote, one
top-level key at a time: [Clay::UI::Grid](../../Grid.md) supplies default keys that
way, and every key the user set wins. The merge is shallow: a `sizing`
you give replaces the whole default `sizing`.

# SEE ALSO

["layout" in Clay::XS::Structs](../../../XS/Structs.md#layout), [Clay::UI::Box](../../Box.md), [Clay::Manual](../../../Manual.md).
