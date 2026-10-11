# NAME

Clay::UI::Role::Layout::GridCell - mark a widget as a cell that Clay::UI::Grid uses as it is

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::XS qw(padding_all);
use Clay::UI::Box;
use Clay::UI::Grid;
use Clay::UI::Text;
use Clay::UI::Role::Layout::GridCell;

class My::Grid  :strict(params) :does(Clay::UI::Grid) {}
class My::Label :strict(params) :does(Clay::UI::Text) {}

# A cell class of your own: a Box (so it has floating and fire_event)
# that a Grid takes as the cell.
class My::Cell :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Layout::GridCell) {}

my $cell = My::Cell->new(
        background_color => [40, 40, 60, 255],
        layout           => { padding => padding_all(6) },
);
$cell->add_child(My::Label->new(text => 'styled'));

my $grid = My::Grid->new(id => 'table');
$grid->append_row([ $cell, My::Label->new(text => 'wrapped') ]);
```

# DESCRIPTION

[Clay::UI::Grid](../../Grid.md) sizes its columns and rows by giving every cell a
column `width_group` and a row `height_group` (see
[Clay::UI::Role::Layout::HasSizingGroup](HasSizingGroup.md)). A widget composing
`Clay::UI::Role::Layout::GridCell` becomes that cell itself: the grid
writes the group ids on it, so its box, background and border cover
exactly the column width and row height. Any other widget is first
wrapped in an unstyled [Clay::UI::Grid::Cell](../../Grid/Cell.md), and only the wrapper
gets the ids.

The role is a marker: it adds no attributes and implements no
methods. It requires Element's sizing-group methods (`width_group`,
`height_group` and the internal `_set_grid_groups`), which
[Clay::UI::Role::Core::Element](../Core/Element.md) provides, so the widget must compose
that role as well (directly, or through
[Clay::UI::Role::Core::Container](../Core/Container.md), [Clay::UI::Box](../../Box.md) or a superclass).
[Clay::UI::Grid::Cell](../../Grid/Cell.md) composes it.

Write a cell class of your own when [Clay::UI::Grid::Cell](../../Grid/Cell.md) does not
offer enough, for example `floating` and `fire_event` ([Clay::UI::Box](../../Box.md)
has both), an interaction role such as
[Clay::UI::Role::Interaction::Pressable](../Interaction/Pressable.md), or attributes your renderer
reads. The grid keeps the cell's
`layout` as it is:

- a `sizing_grow()` width makes its column take a share of the space
left in a grid that is wider than its columns;
- a `sizing_fit($min, $max)` width limits that cell only (text inside
wraps); the other cells of the column still widen the column, so give
every cell of the column the same maximum, or the column does not line
up;
- in a spanning row (see ["append\_spanning\_row" in Clay::UI::Grid](../../Grid.md#append_spanning_row)), give it
a `sizing_percent(1)` width to fill the row without widening the grid.

# SEE ALSO

[Clay::UI::Grid](../../Grid.md), [Clay::UI::Grid::Cell](../../Grid/Cell.md).
