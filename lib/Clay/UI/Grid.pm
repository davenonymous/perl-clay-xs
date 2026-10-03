package Clay::UI::Grid;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::XS qw(sizing_fit sizing_grow sizing_percent CLAY_LEFT_TO_RIGHT CLAY_TOP_TO_BOTTOM);
use Clay::UI::_validate qw(required clay_field);
use Clay::UI::Revision qw(bump_revision);
use Clay::UI::Grid::Row;
use Clay::UI::Grid::Cell;
use Clay::UI::Role::Core::Element;
use Clay::UI::Role::Layout::GridCell;
use Clay::UI::Role::Layout::HasLayout;
use Clay::UI::Role::Style::HasBackground;
use Clay::UI::Role::Style::HasBorder;
use Clay::UI::Role::Style::HasCornerRadius;

our $VERSION = '0.01';

# Group-id encoding: (grid_id << 20) | local_index.
#   - grid_id in 1..4095     -> 12 bits, one slot per live id space
#   - local  in 1..1048575   -> 20 bits, one slot per axis-bucket within it
# Width-axis and height-axis ids share the local space because Clay equalizes
# per-axis only (width vs height live in separate equality buckets).
use constant {
	_GRID_ID_BITS  => 12,
	_LOCAL_BITS    => 20,
	_GRID_ID_MAX   => (1 << 12) - 1,   # 4095
	_LOCAL_MAX     => (1 << 20) - 1,   # 1048575
};

# Process-global pool of 12-bit grid-ids. Monotonic counter for fresh ids;
# the free-list receives ids released when an id space is destroyed, so
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

# Cells leaving a grid drop the group ids it stamped, so a cell attached
# elsewhere afterwards is no longer sized with this grid's columns and rows.
sub _drop_grid_groups (@wrappers) {
	for my $wrapper (@wrappers) {
		my ($width, $height) = ($wrapper->width_group, $wrapper->height_group);
		$wrapper->_set_grid_groups(
			_is_grid_owned_group($width)  ? 0 : $width,
			_is_grid_owned_group($height) ? 0 : $height,
			undef,
		);
	}
	return;
}

# Holds one grid id and returns it to the pool when the last holder is
# freed: the id space, and every cell that still carries ids packed with
# it (a cell kept after its Grid is gone must not share ids with the next
# Grid). It also knows whether its id space still exists: ids packed for
# grids that are all freed size nothing (see
# Clay::UI::Role::Layout::HasSizingGroup). Keeping the id in its own
# object leaves DESTROY free for classes that consume the Grid role.
package Clay::UI::Grid::_IdLease {
	use Scalar::Util qw(weaken);

	sub new ($class, $owner) {
		my $self = bless { id => Clay::UI::Grid::_claim_grid_id(), owner => $owner }, $class;
		weaken $self->{owner};
		return $self;
	}

	sub id ($self) { $self->{id} }

	# True while the id space that claimed the id exists.
	sub is_live ($self) { defined $self->{owner} }

	# True for a group id packed with this lease's grid id.
	sub owns_group ($self, $group) { ($group >> Clay::UI::Grid::_LOCAL_BITS) == $self->{id} }

	sub DESTROY ($self) {
		return if ${^GLOBAL_PHASE} eq 'DESTRUCT';
		Clay::UI::Grid::_release_grid_id($self->{id});
		return;
	}
}

# The group ids of one Grid, or of several Grids that share their columns:
# one grid id (the lease), the width id of every column and the height id
# of every row. Grids sharing an id space give their column N the same
# width id, so Clay sizes those columns together, and never give two rows
# the same height id. Every Grid holds its id space; the lease only
# references it weakly.
class Clay::UI::Grid::_IdSpace :strict(params) {
	field $lease;
	field $next_width_local  = 1;
	field $next_height_local = 1;
	field @free_height_ids;
	field @col_width_ids;    # column index -> packed width-axis group id
	field $grids_width_id;   # the width id of the grids themselves, once they share

	ADJUST {
		$lease = Clay::UI::Grid::_IdLease->new($self);
	}

	method lease () { return $lease }

	# The width id that makes the grids sharing this space as wide as each
	# other.
	method grids_width_id () {
		return $grids_width_id //= Clay::UI::Grid::_pack_group_id($lease->id, $next_width_local++);
	}

	# Width ids for columns 0..$width-1. Ids for new columns are only
	# computed here; commit_col_ids records them once nothing can fail.
	method col_ids_for ($width) {
		my @ids  = @col_width_ids;
		my $next = $next_width_local;
		push @ids, Clay::UI::Grid::_pack_group_id($lease->id, $next++) while @ids < $width;
		return (\@ids, $next);
	}

	method commit_col_ids ($ids, $next) {
		@col_width_ids    = @$ids;
		$next_width_local = $next;
		return;
	}

	# Height id for a new row: a released one first, else a fresh one.
	method claim_row_height_id () {
		return pop @free_height_ids if @free_height_ids;
		my $id = Clay::UI::Grid::_pack_group_id($lease->id, $next_height_local);
		$next_height_local++;
		return $id;
	}

	method release_row_height_id ($id) {
		push @free_height_ids, $id;
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
	use Scalar::Util qw(blessed);

	field $cell_gap :param = 0;
	field $row_gap  :param = 0;

	# Per-row cell wrappers ([row][col]). For each input cell: a widget
	# composing Clay::UI::Role::Layout::GridCell is used directly (so the
	# caller's styling becomes the visible cell); anything else is wrapped
	# in an unstyled Clay::UI::Grid::Cell. The wrapper is what Clay sees
	# with the sizing-group ids set, so its rendered box is exactly the
	# equalized column-width x row-height. A spanning row has one wrapper.
	field @_cell_wrappers;
	field @_row_spans;        # row index -> 1 when the row spans all columns
	field @_row_height_ids;   # row index -> packed height-axis group id
	field $_ids;              # the Clay::UI::Grid::_IdSpace

	ADJUST :params ( :$share_columns_with = undef ) {
		$cell_gap = required(clay_field('Clay_LayoutConfig', 'childGap'), cell_gap => $cell_gap);
		$row_gap  = required(clay_field('Clay_LayoutConfig', 'childGap'), row_gap  => $row_gap);
		$_ids     = defined $share_columns_with
			? _id_space_of($share_columns_with)
			: Clay::UI::Grid::_IdSpace->new;
		if (defined $share_columns_with) {
			my $width_id = $_ids->grids_width_id;
			$_->_take_shared_width($width_id) for $share_columns_with, $self;
		}
		undef $share_columns_with;    # ADJUST's pad would keep the other grid alive
	}

	# Grids sharing columns are as wide as the widest of them, so a grid
	# whose rows all span (an empty body below a header) is still as wide
	# as the columns. A width group the user gave the grid stays.
	method _take_shared_width ($width_id) {
		my $width = $self->width_group;
		return unless $width == 0 || _is_grid_owned_group($width);
		$self->_set_grid_groups($width_id, $self->height_group, $_ids->lease);
		return;
	}

	sub _id_space_of ($grid) {
		die "Clay::UI::Grid: share_columns_with must be a Clay::UI::Grid, got "
			. (blessed $grid ? ref $grid : defined $grid ? "'$grid'" : 'undef')
			unless blessed $grid && $grid->DOES('Clay::UI::Grid');
		return $grid->_id_space;
	}

	method _id_space () { return $_ids }

	method cell_wrappers () {
		return [ map { [ @$_ ] } @_cell_wrappers ];
	}

	method row_count () { return scalar @_cell_wrappers; }

	method is_spanning_row ($index) {
		$self->_check_row_index($index);
		return $_row_spans[$index];
	}

	method row_gap (@new) {
		return $row_gap unless @new;
		$row_gap = required(clay_field('Clay_LayoutConfig', 'childGap'), row_gap => @new);
		bump_revision();
		return $row_gap;
	}

	# The inter-cell gap is baked into each row's layout when the row is
	# built, so a write updates every existing row as well.
	method cell_gap (@new) {
		return $cell_gap unless @new;
		$cell_gap = required(clay_field('Clay_LayoutConfig', 'childGap'), cell_gap => @new);
		$_->layout({ %{ $_->layout }, child_gap => $cell_gap }) for @{ $self->children };
		bump_revision();
		return $cell_gap;
	}

	# Validates widgets that end up below this grid as a whole (the grid
	# is the anchor for the cycle check).
	method _validate_cells (@cells) {
		Clay::UI::Role::Core::Element::_validate_attachment($self, @cells);
		return;
	}

	method _validate_row ($row_cells) {
		die "Clay::UI::Grid: row must be an arrayref" unless ref $row_cells eq 'ARRAY';
		$self->_validate_cells(@$row_cells);
		return;
	}

	sub _is_grid_cell ($widget) {
		return $widget->DOES('Clay::UI::Role::Layout::GridCell');
	}

	# Stamps the grid's group ids on a wrapper. An axis whose group was set
	# by the user (a cross-grid alignment id below 2**20) is left alone; an
	# undef id clears an axis the grid owns (a spanning row belongs to no
	# column).
	method _stamp ($wrapper, $width_id, $height_id) {
		my $width  = $wrapper->width_group;
		my $height = $wrapper->height_group;
		my $stamp_width  = $width  == 0 || _is_grid_owned_group($width);
		my $stamp_height = $height == 0 || _is_grid_owned_group($height);
		$wrapper->_set_grid_groups(
			$stamp_width  ? $width_id // 0 : $width,
			$stamp_height ? $height_id     : $height,
			($stamp_width || $stamp_height) ? $_ids->lease : undef,
		);
		return $wrapper;
	}

	# Wraps one validated input cell into a cell the grid lays out (see
	# @_cell_wrappers) and stamps its (column, row) group ids.
	method _wrap_cell ($cell, $width_id, $height_id) {
		my $wrapper = $cell;
		unless (_is_grid_cell($cell)) {
			$wrapper = Clay::UI::Grid::Cell->new(
				layout => { sizing => { width => sizing_fit(), height => sizing_fit() } },
			);
			$wrapper->add_child($cell);
		}
		return $self->_stamp($wrapper, $width_id, $height_id);
	}

	# The single cell of a spanning row: it belongs to no column and is
	# as wide as the grid without widening it (a wrapper the grid makes is
	# 100% wide, which Clay does not count when it fits the grid to its
	# rows; a cell of your own keeps its layout).
	method _wrap_spanning_cell ($cell, $height_id) {
		my $wrapper = $cell;
		unless (_is_grid_cell($cell)) {
			$wrapper = Clay::UI::Grid::Cell->new(
				layout => { sizing => { width => sizing_percent(1), height => sizing_fit() } },
			);
			$wrapper->add_child($cell);
		}
		return $self->_stamp($wrapper, undef, $height_id);
	}

	method _wrap_row ($row_cells, $col_ids, $height_id) {
		return map { $self->_wrap_cell($row_cells->[$_], $col_ids->[$_], $height_id) } 0 .. $#$row_cells;
	}

	# Rows stretch to the grid's width, so cells with a grow width share
	# the space left in the grid. Unstyled rows paint nothing either way.
	method _new_row (@wrappers) {
		my $row = Clay::UI::Grid::Row->new(
			layout => {
				sizing           => { width => sizing_grow(), height => sizing_fit() },
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
		$self->_validate_row($row_cells);
		my ($col_ids, $next_width_local) = $_ids->col_ids_for(scalar @$row_cells);
		my $height_id = $_ids->claim_row_height_id;

		$_ids->commit_col_ids($col_ids, $next_width_local);
		my @wrappers = $self->_wrap_row($row_cells, $col_ids, $height_id);
		$self->_insert_row_record($index, \@wrappers, 0, $height_id);
		return;
	}

	method _insert_new_spanning_row ($index, $cell) {
		$self->_validate_cells($cell);
		my $height_id = $_ids->claim_row_height_id;
		my $wrapper   = $self->_wrap_spanning_cell($cell, $height_id);
		$self->_insert_row_record($index, [ $wrapper ], 1, $height_id);
		return;
	}

	method _insert_row_record ($index, $wrappers, $spans, $height_id) {
		splice @_cell_wrappers,  $index, 0, [ @$wrappers ];
		splice @_row_spans,      $index, 0, $spans;
		splice @_row_height_ids, $index, 0, $height_id;
		$self->_splice_children($index, 0, $self->_new_row(@$wrappers));
		return;
	}

	method _check_row_index ($index) {
		my $row_count = scalar @_cell_wrappers;
		die "Clay::UI::Grid: row index " . ($index // 'undef') . " out of range 0.." . ($row_count - 1)
			unless defined $index && $index =~ /\A[0-9]+\z/ && $index < $row_count;
		return;
	}

	method _check_insert_index ($index) {
		my $row_count = scalar @_cell_wrappers;
		die "Clay::UI::Grid: insert index " . ($index // 'undef') . " out of range 0..$row_count"
			unless defined $index && $index =~ /\A[0-9]+\z/ && $index <= $row_count;
		return;
	}

	method append_row ($row_cells) {
		$self->_insert_new_row(scalar @_cell_wrappers, $row_cells);
		return $self;
	}

	method insert_row ($index, $row_cells) {
		$self->_check_insert_index($index);
		$self->_insert_new_row($index, $row_cells);
		return $self;
	}

	method append_spanning_row ($cell) {
		$self->_insert_new_spanning_row(scalar @_cell_wrappers, $cell);
		return $self;
	}

	method insert_spanning_row ($index, $cell) {
		$self->_check_insert_index($index);
		$self->_insert_new_spanning_row($index, $cell);
		return $self;
	}

	method remove_row ($index) {
		$self->_check_row_index($index);
		my ($height_id) = splice @_row_height_ids, $index, 1;
		my ($wrappers)  = splice @_cell_wrappers, $index, 1;
		splice @_row_spans, $index, 1;
		$_ids->release_row_height_id($height_id);
		_drop_grid_groups(@$wrappers);
		$self->_splice_children($index, 1);
		return $self;
	}

	method clear_rows () {
		my @wrappers = map { @$_ } @_cell_wrappers;
		$_ids->release_row_height_id($_) for @_row_height_ids;
		@_cell_wrappers = @_row_spans = @_row_height_ids = ();
		_drop_grid_groups(@wrappers);
		$self->_splice_children(0, scalar @{ $self->children });
		return $self;
	}

	method replace_row ($index, $row_cells) {
		$self->_check_row_index($index);
		$self->_validate_row($row_cells);
		my ($col_ids, $next_width_local) = $_ids->col_ids_for(scalar @$row_cells);

		$_ids->commit_col_ids($col_ids, $next_width_local);
		my @wrappers = $self->_wrap_row($row_cells, $col_ids, $_row_height_ids[$index]);
		$self->_replace_row_record($index, \@wrappers, 0);
		return $self;
	}

	method replace_spanning_row ($index, $cell) {
		$self->_check_row_index($index);
		$self->_validate_cells($cell);
		my $wrapper = $self->_wrap_spanning_cell($cell, $_row_height_ids[$index]);
		$self->_replace_row_record($index, [ $wrapper ], 1);
		return $self;
	}

	method _replace_row_record ($index, $wrappers, $spans) {
		_drop_grid_groups(@{ $_cell_wrappers[$index] });
		$_cell_wrappers[$index] = [ @$wrappers ];
		$_row_spans[$index]     = $spans;
		my $row = $self->children->[$index];
		$row->_splice_children(0, scalar @{ $row->children }, @$wrappers);
		return;
	}

	method set_cell ($r, $c, $widget) {
		$self->_check_row_index($r);
		die "Clay::UI::Grid: row $r spans all columns; use replace_spanning_row or replace_row"
			if $_row_spans[$r];
		my $current_row_len = scalar @{ $_cell_wrappers[$r] };
		die "Clay::UI::Grid: col index " . ($c // 'undef') . " out of range 0.." . $current_row_len
			unless defined $c && $c =~ /\A[0-9]+\z/ && $c <= $current_row_len;
		$self->_validate_cells($widget);
		my ($col_ids, $next_width_local) = $_ids->col_ids_for($c + 1);

		$_ids->commit_col_ids($col_ids, $next_width_local);
		my $wrapper  = $self->_wrap_cell($widget, $col_ids->[$c], $_row_height_ids[$r]);
		my $replaced = $c < $current_row_len ? 1 : 0;
		_drop_grid_groups($_cell_wrappers[$r][$c]) if $replaced;
		$_cell_wrappers[$r][$c] = $wrapper;
		$self->children->[$r]->_splice_children($c, $replaced, $wrapper);
		return $self;
	}

	# Puts the rows in a new order without detaching any of them: row $k
	# becomes the row that was at $order->[$k]. The cells keep their
	# parents, focus and hover.
	method reorder_rows ($order) {
		$self->_reorder_children($order);
		@_cell_wrappers  = @_cell_wrappers[@$order];
		@_row_spans      = @_row_spans[@$order];
		@_row_height_ids = @_row_height_ids[@$order];
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

	# A row that spans all columns, for example a group heading:
	$grid->insert_spanning_row(1, My::Text->new(text => 'Administrators'));

	# Mutate further:
	$grid->set_cell(0, 2, My::Text->new(text => 'Title'));
	$grid->reorder_rows([ 0, 2, 1 ]);
	$grid->remove_row(1);

	# A second grid whose columns line up with the first one, for example
	# a scrolling body below a fixed header:
	my $body = My::Grid->new(id => 'body', share_columns_with => $grid);

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

Every row is as wide as the grid (its width is C<sizing_grow>). In a
grid that fits its content this changes nothing, because all rows are
as wide as the widest one anyway; in a grid that is wider than its
columns (a C<layout> with a C<sizing_grow> or C<sizing_fixed> width),
cells whose own width is C<sizing_grow> share the space left over.
Since every column starts from the same equalized width in every row,
those columns stay aligned.

The Grid also composes L<Clay::UI::Role::Layout::HasLayout>,
L<Clay::UI::Role::Style::HasBackground>,
L<Clay::UI::Role::Style::HasBorder> and
L<Clay::UI::Role::Style::HasCornerRadius>. A C<layout> you pass is merged
over the Grid's default outer layout key by key (shallow): for example
C<< layout => { padding => padding_all(8) } >> keeps the rows stacked
C<TOP_TO_BOTTOM> with C<row_gap> between them, while
C<< layout => { child_gap => 10 } >> replaces C<row_gap>.

=head1 CONSTRUCTOR PARAMETERS

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

=head2 share_columns_with (default undef)

Another Grid (any widget composing C<Clay::UI::Grid>) whose columns this
grid shares: column N of both grids is one column for Clay, as wide as
the widest cell of column N in either grid. The grids may be anywhere
in the tree, for example a header grid above a scroll container that
holds the body grid, so the body scrolls while the header stays and the
columns stay aligned. Any number of grids may share the columns of one
grid; they all draw their group ids from the same id space (see
L</ID NAMESPACING>), so their rows never share a height. The grids
themselves get a common C<width_group> as well (unless one was given
to them), so they are as wide as the widest of them: a grid whose rows
all span the columns (see L</append_spanning_row>), or that has no
rows, is still as wide as the columns of the others. Give the
grids the same C<cell_gap>, or the columns drift apart by the
difference. Anything but a Grid dies. The grid does not keep a
reference to the other grid; the shared id space lives as long as any
of the grids does.

=head1 METHODS

=head2 row_count

The number of rows.

=head2 cell_wrappers

Returns a new C<[row][col]> array of the cells the Grid lays out (your
cells composing L<Clay::UI::Role::Layout::GridCell>, such as
L<Clay::UI::Grid::Cell>, or the unstyled Cells it wrapped other widgets
in). A spanning row has one cell. Changing the returned arrays does not
change the Grid.

=head2 is_spanning_row ($index)

True when the row at C<$index> spans all columns (see
L</append_spanning_row>). Dies for an index out of range.

=head1 STYLING CELLS

Pass widgets composing L<Clay::UI::Role::Layout::GridCell> - instances
of L<Clay::UI::Grid::Cell>, or of a cell class of your own - to
L</append_row> / L</insert_row> / L</set_cell> to control each cell's
appearance. The Grid recognises them and uses them as the per-cell
wrapper, so their background / border / padding / corner radius render
exactly at the equalized column-width x row-height. Their C<layout> is
kept: a C<sizing_grow()> width makes the column take a share of the
space left in a wide grid, a C<sizing_fit($min, $max)> width limits the
column (text in it wraps).

Any other widget (Text, Box, etc.) is wrapped in an unstyled Cell
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

Row indices count from 0; an index out of range dies.

=head2 set_cell ($row, $col, $widget)

Replace the cell at C<($row, $col)>. Wrap-or-use rule: a widget
composing L<Clay::UI::Role::Layout::GridCell> is used directly,
anything else is wrapped unstyled. C<$col> may equal the current row
length to extend the row; C<$row> must reference an existing row that
does not span the columns. The replaced cell is detached.

=head2 append_row (\@cells)

Add a new row at the bottom. Allocates one C<height_group> (reusing one
released by C<remove_row> when available); widens the column-id cache if
the new row is longer than any previous row.

=head2 insert_row ($index, \@cells)

Insert a new row at C<$index> (C<0..row_count> inclusive at the upper
end). Same id-allocation as C<append_row>.

=head2 append_spanning_row ($widget)

Add a row at the bottom that holds one cell as wide as the whole grid,
for example a heading for the rows below it. The cell belongs to no
column: it does not widen any column, and the columns do not size it.
Anything that is not a cell (see L</STYLING CELLS>) is wrapped in an
unstyled cell with a C<sizing_percent(1)> width: it is as wide as the
grid, and Clay does not count it when it fits the grid to its rows, so
a long heading wraps instead of widening the grid. A widget composing
L<Clay::UI::Role::Layout::GridCell> is used as the cell as it is; give
it a C<sizing_percent(1)> width for the same effect (a
C<sizing_grow()> width fills the row too, but its content widens a grid
that fits its rows). A spanning row is sized to its own content height
and gets a C<height_group> like any row.

=head2 insert_spanning_row ($index, $widget)

Insert a spanning row at C<$index> (C<0..row_count>).

=head2 remove_row ($index)

Remove the row at C<$index> and detach it. Its C<height_group> id goes
back to the free list for the next new row.

=head2 clear_rows

Remove all rows, as C<remove_row> would one by one.

=head2 replace_row ($index, \@cells)

Replace the cells of the row at C<$index>, keeping the row's
C<height_group> id. Widens the column-id cache if the new row is longer.
A spanning row becomes a normal row. The replaced cells are detached.

=head2 replace_spanning_row ($index, $widget)

Replace the row at C<$index> with a spanning row holding C<$widget>,
keeping the row's C<height_group> id. The replaced cells are detached.

=head2 reorder_rows (\@order)

Put the rows in a new order: row C<$k> becomes the row that was at
C<< $order->[$k] >>. C<\@order> must hold every row index exactly once;
anything else dies and changes nothing. No row is detached, so the
cells keep their parents and the focus and hover stay where they were,
which is what sorting a table needs. Returns the grid.

=head2 Reusing widgets

Per L<Clay::UI::Role::Layout::HasParent/ATTACHING AND REMOVING>, a
widget can be attached whenever it has no parent. All mutators above die
for a widget that is still attached somewhere, including in this same
grid. Widgets removed via C<remove_row>, C<clear_rows>, C<replace_row>,
C<replace_spanning_row> or C<set_cell> can be attached again, to this
grid or anywhere else; a cell leaving the grid also drops the column
and row group ids the grid gave it. A cell of a removed row, and a
widget the grid wrapped in a Cell of its own, stay children of that row
or wrapper until it is freed, which happens as soon as the grid lets go
of it unless you keep a reference to it (from C<children> or
C<cell_wrappers>).

=head1 ID NAMESPACING

Each Grid claims one 12-bit grid-id from a process-global pool on
construction; grids made with C<share_columns_with> use the grid-id of
the grid they share with instead. Cell C<width_group> and
C<height_group> values are packed as C<< (grid_id << 20) | local_index >>,
where C<local_index> is allocated lazily per axis from a counter that
grids sharing a grid-id share as well. This guarantees:

=over 4

=item *

Different Grids never collide, including nested grids, unless they
share columns on purpose; even then their rows never share a height. A
Cell that still carries a grid's ids (one you kept after the grid was
freed, for example) holds that grid id until it is freed or put into
another grid, so no new Grid can share its ids; and once every grid
using those ids is freed, they size nothing (the cell's C<width_group>
and C<height_group> read 0 there), so cells kept from one grid are not
equalized with each other.

=item *

The grid never needs to renumber its cells when it grows: a new column
or row claims the next local index in its axis, or a row index released
by C<remove_row>.

=back

The pool supports up to 4095 concurrent grid-ids. The grid-id is held
by a small internal object that returns it to the pool when every Grid
using it and every Cell still carrying its ids are garbage-collected,
so long-running programs that churn grids do not exhaust the namespace,
and classes consuming the Grid role remain free to define their own
C<DESTROY>. If the pool is genuinely full when a new Grid is
constructed, the constructor dies with a clear message.

Group ids are process-local and not stable across runs. This is fine for
layout (Clay only inspects group equality within a single frame) but
means group ids should not be serialized.

=head1 OVERRIDING GROUP IDS

If a cell already has a non-zero C<width_group> or C<height_group> when
the Grid receives it (set via the C<HasSizingGroup> field, exposed on
every widget), the Grid leaves that axis's id alone. This allows
participation in cross-grid alignment groups: place a cell in your
grid and also assign it a global C<width_group> shared with another
widget elsewhere in the UI. For grids that should share all their
columns, use L</share_columns_with> instead.

Grid-assigned ids occupy values C<E<gt>= 2**20>. User-supplied ids are
restricted to C<0 .. 2**20 - 1> (the C<width_group> / C<height_group>
accessors die otherwise), so they never collide with an id a Grid
picks.

=cut
