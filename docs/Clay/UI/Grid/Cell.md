# NAME

Clay::UI::Grid::Cell - styled cell container for Clay::UI::Grid

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::XS qw(padding_all CLAY_ALIGN_X_RIGHT);
use Clay::UI;
use Clay::UI::Grid;
use Clay::UI::Grid::Cell;
use Clay::UI::Text;

class My::Grid  :strict(params) :does(Clay::UI::Grid) {}
class My::Label :strict(params) :does(Clay::UI::Text) {}

my $header = Clay::UI::Grid::Cell->new(
        layout           => { padding => padding_all(8) },
        background_color => [55, 90, 140, 255],
);
$header->add_child(My::Label->new(text => 'Total'));

my $value = Clay::UI::Grid::Cell->new(
        layout => {
                padding         => padding_all(8),
                child_alignment => { x => CLAY_ALIGN_X_RIGHT },
        },
        background_color => [30, 30, 30, 255],
);
$value->add_child(My::Label->new(text => '1,234.00'));

my $grid = My::Grid->new(id => 'report');
$grid->append_row([ $header, $value ]);

my $ui = Clay::UI->new(width => 800, height => 600, root => $grid);
my $commands = $ui->render;
```

# DESCRIPTION

`Clay::UI::Grid::Cell` is a ready-to-use class (not a role) for one
cell of a [Clay::UI::Grid](../Grid.md). Pass it in a row to style the cell or to
align its content; the grid uses it as the cell itself and writes the
column and row group ids on it, so its background, border and padding
cover exactly the column width and the row height. See
["CELLS AND WRAPPED WIDGETS" in Clay::UI::Grid](../Grid.md#cells-and-wrapped-widgets).

The grid also creates unstyled `Clay::UI::Grid::Cell` objects itself,
around every widget you pass that is not a cell.

A cell is a container with layout and style, but without floating and
without `fire_event`. It composes:

- [Clay::UI::Role::Core::Container](../Role/Core/Container.md): `add_child` and the other child
methods put content into it (and through it
[Clay::UI::Role::Core::Element](../Role/Core/Element.md): `id`, `children`, `width_group`,
`height_group`, `parent`, `on`, ...);
- [Clay::UI::Role::Layout::HasLayout](../Role/Layout/HasLayout.md): `layout`;
- [Clay::UI::Role::Style::HasBackground](../Role/Style/HasBackground.md): `background_color`;
- [Clay::UI::Role::Style::HasBorder](../Role/Style/HasBorder.md): `border_color`, `border_width`;
- [Clay::UI::Role::Style::HasCornerRadius](../Role/Style/HasCornerRadius.md): `corner_radius`;
- [Clay::UI::Role::Layout::GridCell](../Role/Layout/GridCell.md): the marker that makes a grid use
it as the cell.

For a cell with more abilities (floating, events, interaction), write a
class of your own that composes [Clay::UI::Role::Layout::GridCell](../Role/Layout/GridCell.md).

# CONSTRUCTOR PARAMETERS

The class is `:strict(params)`: an unknown parameter dies.

## layout

How the cell sizes itself and places its content; see
["layout" in Clay::UI::Role::Layout::HasLayout](../Role/Layout/HasLayout.md#layout). Default `{}` (FIT on both
axes). The width sizing changes the column; see
["CELLS AND WRAPPED WIDGETS" in Clay::UI::Grid](../Grid.md#cells-and-wrapped-widgets).

## background\_color

See ["background\_color" in Clay::UI::Role::Style::HasBackground](../Role/Style/HasBackground.md#background_color).

## border\_color

See ["border\_color" in Clay::UI::Role::Style::HasBorder](../Role/Style/HasBorder.md#border_color).

## border\_width

See ["border\_width" in Clay::UI::Role::Style::HasBorder](../Role/Style/HasBorder.md#border_width).

## corner\_radius

See ["corner\_radius" in Clay::UI::Role::Style::HasCornerRadius](../Role/Style/HasCornerRadius.md#corner_radius).

## id

See ["id" in Clay::UI::Role::Core::Element](../Role/Core/Element.md#id).

## width\_group

Normally left alone: the grid writes its column id here. A non-zero
id you give stays, and the cell then takes part in your group instead
of the column; see ["Overriding group ids" in Clay::UI::Grid](../Grid.md#overriding-group-ids) and
["width\_group" in Clay::UI::Role::Layout::HasSizingGroup](../Role/Layout/HasSizingGroup.md#width_group).

## height\_group

Like ["width\_group"](#width_group), for the row.

All of them are read/write accessors as well, as documented in the
linked roles.

# SEE ALSO

[Clay::UI::Grid](../Grid.md), [Clay::UI::Role::Layout::GridCell](../Role/Layout/GridCell.md),
[Clay::UI::Box](../Box.md).
