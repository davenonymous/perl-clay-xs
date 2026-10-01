package Clay::UI::Grid;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::XS qw(sizing_fit CLAY_LEFT_TO_RIGHT CLAY_TOP_TO_BOTTOM);
use Clay::UI::_validate qw(required clay_field);
use Clay::UI::Grid::Row;
use Clay::UI::Grid::Cell;
use Clay::UI::Role::Core::Element;
use Clay::UI::Role::Layout::HasLayout;
use Clay::UI::Role::Style::HasBackground;
use Clay::UI::Role::Style::HasBorder;
use Clay::UI::Role::Style::HasCornerRadius;

our $VERSION = '0.01';

# Group-id encoding: (grid_id << 20) | local_index.
#   - grid_id in 1..4095     -> 12 bits, one slot per live Grid instance
#   - local  in 1..1048575   -> 20 bits, one slot per axis-bucket within a Grid
# Width-axis and height-axis ids share the local space because Clay equalizes
# per-axis only (width vs height live in separate equality buckets).
use constant {
	_GRID_ID_BITS  => 12,
	_LOCAL_BITS    => 20,
	_GRID_ID_MAX   => (1 << 12) - 1,   # 4095
	_LOCAL_MAX     => (1 << 20) - 1,   # 1048575
};

# Process-global pool of 12-bit grid-ids. Monotonic counter for fresh ids;
# the free-list receives ids released when a grid is destroyed, so
# long-running programs that churn grids do not exhaust the namespace.
my @_FREE_GRID_IDS;
my $_NEXT_GRID_ID = 1;

sub _claim_grid_id {
	return shift @_FREE_GRID_IDS if @_FREE_GRID_IDS;
	die "Clay::UI::Grid: grid-id pool exhausted (max " . _GRID_ID_MAX . " live grids)"
		if $_NEXT_GRID_ID > _GRID_ID_MAX;
	return $_NEXT_GRID_ID++;
}

sub _release_grid_id ($id) {
	push @_FREE_GRID_IDS, $id;
	return;
}

sub _pack_group_id ($grid_id, $local) {
	die "Clay::UI::Grid: grid_id $grid_id out of range 1.." . _GRID_ID_MAX
		unless $grid_id >= 1 && $grid_id <= _GRID_ID_MAX;
	die "Clay::UI::Grid: local index $local out of range 1.." . _LOCAL_MAX
		unless $local >= 1 && $local <= _LOCAL_MAX;
	return ($grid_id << _LOCAL_BITS) | $local;
}

sub _is_grid_owned_group ($group_id) {
	return $group_id > _LOCAL_MAX;
}

# Holds one grid id for the lifetime of a Grid and returns it to the pool
# when the grid is freed. Keeping the id in its own object leaves DESTROY
# free for classes that consume the Grid role.
package Clay::UI::Grid::_IdLease {
	sub new ($class) {
		my $id = Clay::UI::Grid::_claim_grid_id();
		return bless \$id, $class;
	}

	sub id ($self) { $$self }

	sub DESTROY ($self) {
		return if ${^GLOBAL_PHASE} eq 'DESTRUCT';
		Clay::UI::Grid::_release_grid_id($$self);
		return;
	}
}

role Clay::UI::Grid
	:does(Clay::UI::Role::Core::Element)
	:does(Clay::UI::Role::Layout::HasLayout)
	:does(Clay::UI::Role::Style::HasBackground)
	:does(Clay::UI::Role::Style::HasBorder)
	:does(Clay::UI::Role::Style::HasCornerRadius)
{
	field $cell_gap :param = 0;
	field $row_gap  :param = 0;

	# Per-cell wrappers ([row][col]). For each input cell: if it is already a
	# Clay::UI::Grid::Cell, it is used directly (so the caller's styling
	# becomes the visible cell); otherwise the Grid wraps it in an unstyled
	# Cell. The wrapper is what Clay sees with the sizing-group ids set, so
	# its rendered box is exactly the equalized column-width x row-height.
	field @_cell_wrappers;

	# Per-Grid id allocation state.
	field $_grid_lease;
	field $_next_width_local  = 1;
	field $_next_height_local = 1;
	field @_free_height_locals;
	field @_col_width_ids;    # column index -> packed width-axis group id
	field @_row_height_ids;   # row    index -> packed height-axis group id

	ADJUST {
		$cell_gap    = required(clay_field('Clay_LayoutConfig', 'childGap'), cell_gap => $cell_gap);
		$row_gap     = required(clay_field('Clay_LayoutConfig', 'childGap'), row_gap  => $row_gap);
		$_grid_lease = Clay::UI::Grid::_IdLease->new;
	}

	method cell_wrappers () {
		return [ map { [ @$_ ] } @_cell_wrappers ];
	}

	method row_count () { return scalar @_cell_wrappers; }

	method row_gap (@new) {
		return $row_gap unless @new;
		return $row_gap = required(clay_field('Clay_LayoutConfig', 'childGap'), row_gap => @new);
	}

	# The inter-cell gap is baked into each row's layout when the row is
	# built, so a write updates every existing row as well.
	method cell_gap (@new) {
		return $cell_gap unless @new;
		$cell_gap = required(clay_field('Clay_LayoutConfig', 'childGap'), cell_gap => @new);
		$_->layout({ %{ $_->layout }, child_gap => $cell_gap }) for @{ $self->children };
		return $cell_gap;
	}

	# Width-axis ids for columns 0..$width-1. Ids for new columns are only
	# computed here; _commit_col_ids records them once nothing can fail.
	method _col_ids_for ($width) {
		my @ids = @_col_width_ids;
		my $next = $_next_width_local;
		push @ids, _pack_group_id($_grid_lease->id, $next++) while @ids < $width;
		return (\@ids, $next);
	}

	method _commit_col_ids ($ids, $next) {
		@_col_width_ids    = @$ids;
		$_next_width_local = $next;
		return;
	}

	# Height-axis id for a new row: a released one first, else a fresh one.
	method _claim_row_height_id () {
		return pop @_free_height_locals if @_free_height_locals;
		my $id = _pack_group_id($_grid_lease->id, $_next_height_local);
		$_next_height_local++;
		return $id;
	}

	method _release_row_height_id ($id) {
		push @_free_height_locals, $id;
		return;
	}

	# Validates a row of input cells as a whole (they all end up below this
	# grid, so the grid is the anchor for the cycle check).
	method _validate_cells ($row_cells) {
		die "Clay::UI::Grid: row must be an arrayref" unless ref $row_cells eq 'ARRAY';
		Clay::UI::Role::Core::Element::_validate_attachment($self, @$row_cells);
		return;
	}

	# Wraps one validated input cell into a Clay::UI::Grid::Cell and stamps
	# its (column, row) group ids. A Cell instance is used directly;
	# anything else is wrapped in an unstyled Cell. An axis whose group was
	# set by the user (a cross-grid alignment id below 2**20) is left alone.
	method _wrap_cell ($cell, $width_id, $height_id) {
		my $wrapper = $cell;
		unless ($cell->isa('Clay::UI::Grid::Cell')) {
			$wrapper = Clay::UI::Grid::Cell->new(
				layout => { sizing => { width => sizing_fit(), height => sizing_fit() } },
			);
			$wrapper->add_child($cell);
		}
		my $width  = $wrapper->width_group;
		my $height = $wrapper->height_group;
		$wrapper->_set_grid_groups(
			($width  == 0 || _is_grid_owned_group($width))  ? $width_id  : $width,
			($height == 0 || _is_grid_owned_group($height)) ? $height_id : $height,
		);
		return $wrapper;
	}

	method _wrap_row ($row_cells, $col_ids, $height_id) {
		return map { $self->_wrap_cell($row_cells->[$_], $col_ids->[$_], $height_id) } 0 .. $#$row_cells;
	}

	method _new_row (@wrappers) {
		my $row = Clay::UI::Grid::Row->new(
			layout => {
				sizing           => { width => sizing_fit(), height => sizing_fit() },
				layout_direction => CLAY_LEFT_TO_RIGHT,
				child_gap        => $cell_gap,
			},
		);
		$row->_attach_children(@wrappers);
		return $row;
	}

	# Builds a complete row for index $index. Everything that can fail
	# (validation, id allocation) happens before the grid changes.
	method _insert_new_row ($index, $row_cells) {
		$self->_validate_cells($row_cells);
		my ($col_ids, $next_width_local) = $self->_col_ids_for(scalar @$row_cells);
		my $height_id = $self->_claim_row_height_id;

		$self->_commit_col_ids($col_ids, $next_width_local);
		my @wrappers = $self->_wrap_row($row_cells, $col_ids, $height_id);
		splice @_cell_wrappers,  $index, 0, [ @wrappers ];
		splice @_row_height_ids, $index, 0, $height_id;
		$self->_splice_children($index, 0, $self->_new_row(@wrappers));
		return;
	}

	method _check_row_index ($index) {
		my $row_count = scalar @_cell_wrappers;
		die "Clay::UI::Grid: row index $index out of range 0.." . ($row_count - 1)
			unless $index =~ /\A[0-9]+\z/ && $index < $row_count;
		return;
	}

	method append_row ($row_cells) {
		$self->_insert_new_row(scalar @_cell_wrappers, $row_cells);
		return $self;
	}

	method insert_row ($index, $row_cells) {
		my $row_count = scalar @_cell_wrappers;
		die "Clay::UI::Grid: insert index $index out of range 0..$row_count"
			unless $index =~ /\A[0-9]+\z/ && $index <= $row_count;
		$self->_insert_new_row($index, $row_cells);
		return $self;
	}

	method remove_row ($index) {
		$self->_check_row_index($index);
		my ($height_id) = splice @_row_height_ids, $index, 1;
		splice @_cell_wrappers, $index, 1;
		$self->_release_row_height_id($height_id);
		$self->_splice_children($index, 1);
		return $self;
	}

	method replace_row ($index, $row_cells) {
		$self->_check_row_index($index);
		$self->_validate_cells($row_cells);
		my ($col_ids, $next_width_local) = $self->_col_ids_for(scalar @$row_cells);

		$self->_commit_col_ids($col_ids, $next_width_local);
		my @wrappers = $self->_wrap_row($row_cells, $col_ids, $_row_height_ids[$index]);
		$_cell_wrappers[$index] = [ @wrappers ];
		my $row = $self->children->[$index];
		$row->_splice_children(0, scalar @{ $row->children }, @wrappers);
		return $self;
	}

	method set_cell ($r, $c, $widget) {
		$self->_check_row_index($r);
		my $current_row_len = scalar @{ $_cell_wrappers[$r] };
		die "Clay::UI::Grid: col index $c out of range 0.." . $current_row_len
			unless $c =~ /\A[0-9]+\z/ && $c <= $current_row_len;
		$self->_validate_cells([ $widget ]);
		my ($col_ids, $next_width_local) = $self->_col_ids_for($c + 1);

		$self->_commit_col_ids($col_ids, $next_width_local);
		my ($wrapper) = $self->_wrap_row([ $widget ], [ $col_ids->[$c] ], $_row_height_ids[$r]);
		$_cell_wrappers[$r][$c] = $wrapper;
		my $replaced = $c < $current_row_len ? 1 : 0;
		$self->children->[$r]->_splice_children($c, $replaced, $wrapper);
		return $self;
	}

	# The default outer layout (rows stacked TOP_TO_BOTTOM, row_gap between
	# them), merged under any layout slice already present so keys from the
	# user's 'layout' win one by one, whatever order contributors run in.
	method contribute_grid_defaults ($config) {
		$config->{layout} = {
			sizing           => { width => sizing_fit(), height => sizing_fit() },
			layout_direction => CLAY_TOP_TO_BOTTOM,
			child_gap        => $row_gap,
			%{ $config->{layout} // {} },
		};
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Grid - auto-sized grid/table widget for Clay::UI

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Grid;
	use Clay::UI::Text;

	class My::Grid :strict(params) :does(Clay::UI::Grid) {}
	class My::Text :strict(params) :does(Clay::UI::Text) {}

	my $grid = My::Grid->new(
		id       => 'data',
		cell_gap => 8,
		row_gap  => 4,
	);

	$grid->append_row([
		My::Text->new(text => 'Name'),
		My::Text->new(text => 'Email'),
		My::Text->new(text => 'Role'),
	]);
	$grid->append_row([
		My::Text->new(text => 'Alice'),
		My::Text->new(text => 'alice@example.com'),
		My::Text->new(text => 'Admin'),
	]);

	# Mutate further:
	$grid->set_cell(0, 2, My::Text->new(text => 'Title'));
	$grid->remove_row(1);

=head1 DESCRIPTION

Builds a row-major grid where each column is sized to its widest cell
and each row is sized to its tallest cell, all in a single layout pass.
The auto-sizing is implemented via Clay's sizing-group feature (vendored
patch C<patches/0001-clay-sizing-groups.patch>): the Grid assigns each
cell a per-column C<width_group> and per-row C<height_group> so Clay's
layout pass equalizes column widths and row heights across siblings
that would otherwise be unaware of each other. Grids nest: a cell may
hold another grid.

The Grid composes L<Clay::UI::Role::Core::Element> (not
L<Clay::UI::Role::Core::Container>): its children are its rows, and only
the row methods below change them. Each row is a C<LEFT_TO_RIGHT>
L<Clay::UI::Grid::Row>; the rows are stacked C<TOP_TO_BOTTOM>. Pass
C<cell_gap> to control the horizontal gap between cells in a row; pass
C<row_gap> for the vertical gap between rows.

The Grid also composes L<Clay::UI::Role::Layout::HasLayout>,
L<Clay::UI::Role::Style::HasBackground>,
L<Clay::UI::Role::Style::HasBorder> and
L<Clay::UI::Role::Style::HasCornerRadius>. A C<layout> you pass is merged
over the Grid's default outer layout key by key (shallow): for example
C<< layout => { padding => padding_all(8) } >> keeps the rows stacked
C<TOP_TO_BOTTOM> with C<row_gap> between them, while
C<< layout => { child_gap => 10 } >> replaces C<row_gap>.

=head1 FIELDS

=head2 cell_gap (default 0)

Pixel gap between cells within a row. Forwarded to the row container's
C<child_gap>. Read/write accessor: C<< $grid->cell_gap >> reads,
C<< $grid->cell_gap($px) >> writes. Because the gap is baked into each
row when the row is built, a write updates every existing row so the
change is visible on the next C<render>.

=head2 row_gap (default 0)

Pixel gap between rows. Used as the outer container's C<child_gap>
unless the Grid's C<layout> sets C<child_gap> itself.
Read/write accessor: C<< $grid->row_gap >> reads,
C<< $grid->row_gap($px) >> writes. It is re-read on every C<render>, so a
write takes effect immediately.

=head2 row_count

The number of rows.

=head2 cell_wrappers

Returns a new C<[row][col]> array of the L<Clay::UI::Grid::Cell> objects
the Grid lays out (your Cells, or the unstyled Cells it wrapped other
widgets in). Changing the returned arrays does not change the Grid.

=head1 STYLING CELLS

Pass L<Clay::UI::Grid::Cell> instances to L</append_row> / L</insert_row>
/ L</set_cell> to control each cell's appearance. The Grid recognises
Cell objects and uses them as the per-cell wrapper, so their background
/ border / padding / corner radius render exactly at the equalized
column-width x row-height.

Any non-Cell widget (Text, Box, etc.) is wrapped in an unstyled Cell
automatically; the wrapper still gets the sizing-group ids, but has no
visible styling. Use this when you only care about layout, not
appearance.

=head1 MUTATION

A Grid is constructed empty and populated via the mutators below. All
mutators preserve column/row equalization: cells in the same column
continue to share a C<width_group>, cells in the same row a
C<height_group>. Each mutator validates all of its input (see
L<Clay::UI::Role::Core::Element/ATTACHING CHILDREN>) and allocates its
ids before it changes anything, so a call that dies on invalid input
leaves the Grid as it was. The one exception is an C<OnBlur> listener
that dies when a removed cell held the focus: the change is complete
(the cell is detached and blurred) and the call then dies with the
listener's error.

=head2 set_cell ($row, $col, $widget)

Replace the cell at C<($row, $col)>. Wrap-or-use rule: a
C<Clay::UI::Grid::Cell> is used directly, anything else is wrapped
unstyled. C<$col> may equal the current row length to extend the row;
C<$row> must reference an existing row. The replaced cell is detached.

=head2 append_row (\@cells)

Add a new row at the bottom. Allocates one C<height_group> (reusing one
released by C<remove_row> when available); widens the column-id cache if
the new row is longer than any previous row.

=head2 insert_row ($index, \@cells)

Insert a new row at C<$index> (C<0..row_count> inclusive at the upper
end). Same id-allocation as C<append_row>.

=head2 remove_row ($index)

Remove the row at C<$index> and detach it. Its C<height_group> id goes
back to the Grid's free list for the next new row.

=head2 replace_row ($index, \@cells)

Replace the cells of the row at C<$index>, keeping the row's
C<height_group> id. Widens the column-id cache if the new row is longer.
The replaced cells are detached.

=head2 No widget reuse

Per L<Clay::UI::Role::Layout::HasParent/NO REPARENTING>, a widget is
attached at most once. All mutators above expect freshly built widgets;
passing a widget that has already been attached anywhere (including to
this same grid, or to a grid that has since been freed) dies. Widgets
removed via C<remove_row>, C<replace_row> or C<set_cell> cannot be
reattached.

=head1 ID NAMESPACING

Each Grid instance claims one 12-bit grid-id from a process-global pool
on construction. Cell C<width_group> and C<height_group> values are
packed as C<< (grid_id << 20) | local_index >>, where C<local_index> is
allocated lazily per axis from a per-Grid counter. This guarantees:

=over 4

=item *

Different Grid instances never collide, including nested grids.

=item *

The grid never needs to renumber its cells when it grows: a new column
or row claims the next local index in its axis, or a row index released
by C<remove_row>.

=back

The pool supports up to 4095 concurrent grids. The grid-id is held by a
small internal object that returns it to the pool when the Grid is
garbage-collected, so long-running programs that churn grids do not
exhaust the namespace, and classes consuming the Grid role remain free
to define their own C<DESTROY>. If the pool is genuinely full when a new
Grid is constructed, the constructor dies with a clear message.

Group ids are process-local and not stable across runs. This is fine for
layout (Clay only inspects group equality within a single frame) but
means group ids should not be serialized.

=head1 OVERRIDING GROUP IDS

If a cell already has a non-zero C<width_group> or C<height_group> when
the Grid receives it (set via the C<HasSizingGroup> field, exposed on
every widget), the Grid leaves that axis's id alone. This allows
participation in cross-grid alignment groups: place a cell in your
grid and also assign it a global C<width_group> shared with another
widget elsewhere in the UI.

Grid-assigned ids occupy values C<E<gt>= 2**20>. User-supplied ids are
restricted to C<0 .. 2**20 - 1> (the C<width_group> / C<height_group>
accessors die otherwise), so they never collide with an id a Grid
picks.

=cut
