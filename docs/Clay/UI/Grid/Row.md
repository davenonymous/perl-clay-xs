# NAME

Clay::UI::Grid::Row - row container that Clay::UI::Grid creates for each row

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::UI::Grid;
use Clay::UI::Text;

class My::Grid  :strict(params) :does(Clay::UI::Grid) {}
class My::Label :strict(params) :does(Clay::UI::Text) {}

my $grid = My::Grid->new(id => 'grid');
$grid->append_row([ map { My::Label->new(text => $_) } qw(a b c) ]);

# Rows are created by Clay::UI::Grid; you only meet them when you
# look at a grid's children.
for my $row (@{ $grid->children }) {
        say scalar @{ $row->children }, ' cells';
}
```

# DESCRIPTION

`Clay::UI::Grid::Row` is the container [Clay::UI::Grid](../Grid.md) creates for
every row: a left-to-right element whose children are the row's cells.
The grid sets its layout to a `sizing_grow()` width (every row is as
wide as the grid), a FIT height and `child_gap` equal to the grid's
`cell_gap`.

A row composes [Clay::UI::Role::Core::Element](../Role/Core/Element.md) and
[Clay::UI::Role::Layout::HasLayout](../Role/Layout/HasLayout.md) only. It has no `add_child` and
no other public way to change its children: the grid alone decides
which cells a row holds (through `append_row`, `insert_row`,
`replace_row`, `set_cell` and the other row methods of
[Clay::UI::Grid](../Grid.md)). Reading works as for any element widget:
`children`, `parent` (the grid), `layout`, and the two facts the
grid keeps on each row, ["spans"](#spans) and ["height\_id"](#height_id).

A row has no style of its own (no background, border or corner
radius). To colour a row, such as a header row, see
["STYLING A ROW" in Clay::UI::Grid](../Grid.md#styling-a-row).

Application code does not create rows. For a container of your own,
compose [Clay::UI::Box](../Box.md) in a class.

# CONSTRUCTOR PARAMETERS

[Clay::UI::Grid](../Grid.md) creates every row with these parameters, plus
`layout`. They are listed so that the readers below make sense; do not
create rows yourself.

## spans

True for a spanning row (one cell across all columns, see
["SPANNING ROWS" in Clay::UI::Grid](../Grid.md#spanning-rows)). Default 0.

## height\_id

The packed group id the grid gives the row's cells as their
`height_group` (see ["GROUP IDS" in Clay::UI::Grid](../Grid.md#group-ids)). Required.

# METHODS

## spans

```perl
my $is_spanning = $row->spans;    # 1 or 0
```

1 when the row is a spanning row, else 0. The grid changes it when
`replace_spanning_row` or `replace_row` turns a row into the other
kind; ["is\_spanning\_row" in Clay::UI::Grid](../Grid.md#is_spanning_row) answers the same by index.

## height\_id

```perl
my $height_id = $row->height_id;
```

The row's height group id. It stays the same for the life of the row,
also when its cells are replaced.

# SEE ALSO

[Clay::UI::Grid](../Grid.md), [Clay::UI::Grid::Cell](Cell.md).
