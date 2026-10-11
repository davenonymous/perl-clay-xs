# NAME

Clay::UI::Role::Style::HasBackground - background colour attribute for Clay::UI widgets

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Style::HasBackground;

class My::Panel :strict(params)
        :does(Clay::UI::Role::Core::Container)
        :does(Clay::UI::Role::Style::HasBackground)
{}

my $panel = My::Panel->new(background_color => [40, 50, 60, 255]);
$panel->background_color({ r => 200, g => 30, b => 30, a => 255 });
$panel->background_color(undef);    # no background
```

# DESCRIPTION

`Clay::UI::Role::Style::HasBackground` gives a widget the
`background_color` attribute: the colour the renderer fills the
element's box with. The widget adds it to its declaration (the hash of
settings Clay receives for the element) as `background_color`
(`backgroundColor` for Clay). [Clay::UI::Box](../../Box.md), [Clay::UI::Grid](../../Grid.md) and
[Clay::UI::Grid::Cell](../../Grid/Cell.md) compose it.

# ATTRIBUTES

## background\_color

```perl
my $color = $widget->background_color;    # read: a copy, or undef
$widget->background_color([40, 50, 60, 255]);
```

A constructor parameter and a read/write accessor. The value is undef
(no background) or a colour in one of two forms:

```perl
[$r, $g, $b, $a]                          # exactly four numbers
{ r => $r, g => $g, b => $b, a => $a }    # a channel left out is 0
```

The channels are numbers, by convention 0 to 255 (`a` 255 is opaque).
Clay passes them to the renderer unchanged and checks only that they
are finite numbers. With alpha 0 Clay emits no rectangle; mind that a
hash without `a` is fully transparent. See
["Clay\_Color" in Clay::XS::Structs](../../../XS/Structs.md#clay_color).

Default undef: the declaration gets no background colour and Clay
draws no rectangle for the element.

Reading returns a new copy (or undef); writing stores a copy of the
value, so changing the array or hash afterwards does not change the
widget. A write bumps the revision ([Clay::UI::Revision](../../Revision.md)), takes
effect at the next `render` and returns a copy of the new value.

The value is checked when it is set, at construction or by the
accessor. A bad value dies naming the attribute, for example:

```text
Clay::UI: 'background_color' expected an array of 4 numbers, got an array of 3 elements
Clay::UI: 'background_color' has unknown key 'x' (known keys: r, g, b, a)
Clay::UI: 'background_color' expected a hash or array reference, got 'red'
```

# METHODS

## contribute\_background

Adds `background_color` to the widget's declaration while the
attribute is set (see
["EXTENDING THE DECLARATION" in Clay::UI::Role::Core::Element](../Core/Element.md#extending-the-declaration)).

# SEE ALSO

["backgroundColor" in Clay::XS::Structs](../../../XS/Structs.md#backgroundcolor), [Clay::UI::Box](../../Box.md).
