package Clay::UI::Grid;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::XS qw(sizing_fit CLAY_LEFT_TO_RIGHT CLAY_TOP_TO_BOTTOM);
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
# free-list receives ids released by DESTROY so long-running programs that
# churn grids do not exhaust the namespace.
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

role Clay::UI::Grid
	:does(Clay::UI::Role::Core::Element)
	:does(Clay::UI::Role::Layout::HasLayout)
	:does(Clay::UI::Role::Style::HasBackground)
	:does(Clay::UI::Role::Style::HasBorder)
	:does(Clay::UI::Role::Style::HasCornerRadius)
{
	field $cell_gap :param = 0;
	field $row_gap  :param :accessor = 0;

	# Per-cell wrappers ([row][col]). For each input cell: if it is already a
	# Clay::UI::Grid::Cell, it is used directly (so the caller's styling
	# becomes the visible cell); otherwise the Grid wraps it in an unstyled
	# Cell. The wrapper is what Clay sees with the sizing-group ids set, so
	# its rendered box is exactly the equalized column-width x row-height.
	field $cell_wrappers :reader = [];

	# Per-Grid id allocation state.
	field $_grid_id;
	field $_next_width_local  = 1;
	field $_next_height_local = 1;
	field $_col_width_ids     = [];   # column index -> packed width-axis group id
	field $_row_height_ids    = [];   # row    index -> packed height-axis group id

	ADJUST {
		$_grid_id = _claim_grid_id();
	}

	method DESTROY {
		return if ${^GLOBAL_PHASE} eq 'DESTRUCT';
		return unless defined $_grid_id;
		_release_grid_id($_grid_id);
		$_grid_id = undef;
		return;
	}

	# Ensure $_col_width_ids covers at least $width columns; claim new ids
	# lazily for any column past the current cache length.
	method _ensure_col_width ($width) {
		while (scalar(@$_col_width_ids) < $width) {
			push @$_col_width_ids, _pack_group_id($_grid_id, $_next_width_local++);
		}
		return;
	}

	# Claim a fresh height-axis id for a new row.
	method _claim_row_height_id () {
		return _pack_group_id($_grid_id, $_next_height_local++);
	}

	# Wrap one input cell into a Clay::UI::Grid::Cell and stamp its
	# (column, row) group ids. Mirrors the constructor's wrap-or-use rule:
	# a Cell instance is used directly; anything else is wrapped unstyled.
	# If the wrapper already has a non-zero group on an axis (user-set for
	# cross-grid alignment), that axis is left alone.
	method _wrap_cell ($cell, $col_idx, $row_height_id) {
		my $wrapper;
		if ($cell->isa('Clay::UI::Grid::Cell')) {
			$wrapper = $cell;
		}
		else {
			$wrapper = Clay::UI::Grid::Cell->new(
				layout => { sizing => { width => sizing_fit(), height => sizing_fit() } },
			);
			$wrapper->add_child($cell);
		}
		$wrapper->width_group($_col_width_ids->[$col_idx]) if $wrapper->width_group  == 0;
		$wrapper->height_group($row_height_id)             if $wrapper->height_group == 0;
		return $wrapper;
	}

	# Build a row-Box for a row of input cells at row index $r. Updates
	# $cell_wrappers and $_row_height_ids; widens $_col_width_ids if needed.
	# Returns the new row-Box (unparented; caller is responsible for attaching).
	method _build_row_box ($r, $row_cells) {
		$self->_ensure_col_width(scalar @$row_cells);
		my $row_height_id = $self->_claim_row_height_id();
		$_row_height_ids->[$r] = $row_height_id;

		my @wrappers;
		for my $c (0 .. $#$row_cells) {
			push @wrappers, $self->_wrap_cell($row_cells->[$c], $c, $row_height_id);
		}
		$cell_wrappers->[$r] = \@wrappers;

		my $row_box = Clay::UI::Grid::Row->new(
			layout => {
				sizing           => { width => sizing_fit(), height => sizing_fit() },
				layout_direction => CLAY_LEFT_TO_RIGHT,
				child_gap        => $cell_gap,
			},
		);
		$row_box->add_child(@wrappers) if @wrappers;
		return $row_box;
	}

	# Combined read/write accessor for the inter-cell gap. Unlike row_gap
	# (re-read from contribute_grid_defaults on every render), cell_gap is
	# baked into each row Box's layout child_gap when the row is built
	# (_build_row_box and insert_row), so a write must rewrite every
	# existing row box in place. The Grid's children are exactly its row
	# boxes, so iterating children covers both build paths.
	method cell_gap (@v) {
		if (@v) {
			$cell_gap = $v[0];
			$_->layout->{child_gap} = $cell_gap for @{ $self->children };
		}
		return $cell_gap;
	}

	method row_count () { return scalar @$cell_wrappers; }

	method set_cell ($r, $c, $widget) {
		my $row_count = scalar @$cell_wrappers;
		die "Clay::UI::Grid: row index $r out of range 0.." . ($row_count - 1)
			unless $r >= 0 && $r < $row_count;
		my $current_row_len = scalar @{ $cell_wrappers->[$r] };
		die "Clay::UI::Grid: col index $c out of range 0.." . $current_row_len
			unless $c >= 0 && $c <= $current_row_len;

		$self->_ensure_col_width($c + 1);
		my $wrapper = $self->_wrap_cell($widget, $c, $_row_height_ids->[$r]);
		$cell_wrappers->[$r][$c] = $wrapper;

		my $row_box      = $self->children->[$r];
		my $row_children = $row_box->children;
		if ($c < scalar @$row_children) {
			$row_children->[$c] = $wrapper;
		}
		else {
			push @$row_children, $wrapper;
		}
		$wrapper->_set_parent($row_box);
		return $self;
	}

	method append_row ($row_cells) {
		die "Clay::UI::Grid: row must be an arrayref"
			unless ref $row_cells eq 'ARRAY';
		my $r = scalar @$cell_wrappers;
		my $row_box = $self->_build_row_box($r, $row_cells);
		$self->add_child($row_box);
		return $self;
	}

	method insert_row ($index, $row_cells) {
		die "Clay::UI::Grid: row must be an arrayref"
			unless ref $row_cells eq 'ARRAY';
		my $row_count = scalar @$cell_wrappers;
		die "Clay::UI::Grid: insert index $index out of range 0..$row_count"
			unless $index >= 0 && $index <= $row_count;

		# Build at the eventual index so $cell_wrappers / $_row_height_ids
		# get the right slot.
		$self->_ensure_col_width(scalar @$row_cells);
		my $row_height_id = $self->_claim_row_height_id();

		my @wrappers;
		for my $c (0 .. $#$row_cells) {
			push @wrappers, $self->_wrap_cell($row_cells->[$c], $c, $row_height_id);
		}

		my $row_box = Clay::UI::Grid::Row->new(
			layout => {
				sizing           => { width => sizing_fit(), height => sizing_fit() },
				layout_direction => CLAY_LEFT_TO_RIGHT,
				child_gap        => $cell_gap,
			},
		);
		$row_box->add_child(@wrappers) if @wrappers;

		splice @$cell_wrappers,   $index, 0, \@wrappers;
		splice @$_row_height_ids, $index, 0, $row_height_id;
		splice @{ $self->children }, $index, 0, $row_box;
		$row_box->_set_parent($self);
		return $self;
	}

	method remove_row ($index) {
		my $row_count = scalar @$cell_wrappers;
		die "Clay::UI::Grid: row index $index out of range 0.." . ($row_count - 1)
			unless $index >= 0 && $index < $row_count;
		splice @$cell_wrappers,   $index, 1;
		splice @$_row_height_ids, $index, 1;
		splice @{ $self->children }, $index, 1;
		return $self;
	}

	method replace_row ($index, $row_cells) {
		die "Clay::UI::Grid: row must be an arrayref"
			unless ref $row_cells eq 'ARRAY';
		my $row_count = scalar @$cell_wrappers;
		die "Clay::UI::Grid: row index $index out of range 0.." . ($row_count - 1)
			unless $index >= 0 && $index < $row_count;

		$self->_ensure_col_width(scalar @$row_cells);
		my $row_height_id = $_row_height_ids->[$index];

		my @wrappers;
		for my $c (0 .. $#$row_cells) {
			push @wrappers, $self->_wrap_cell($row_cells->[$c], $c, $row_height_id);
		}
		$cell_wrappers->[$index] = \@wrappers;

		my $row_box = $self->children->[$index];
		my $row_children = $row_box->children;
		@$row_children = ();
		push @$row_children, @wrappers;
		$_->_set_parent($row_box) for @wrappers;
		return $self;
	}

	method contribute_grid_defaults ($config) {
		# Provide a sensible default outer layout: TOP_TO_BOTTOM with optional
		# row_gap. Caller-supplied 'layout' via HasLayout wins because
		# contribute_layout runs after this (alphabetical method discovery
		# is not guaranteed, but the user's layout slice replaces this one
		# entirely if present).
		return if exists $config->{layout};
		$config->{layout} = {
			sizing           => { width => sizing_fit(), height => sizing_fit() },
			layout_direction => CLAY_TOP_TO_BOTTOM,
			child_gap        => $row_gap,
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

	class My::Grid :does(Clay::UI::Grid) {}
	class My::Text :does(Clay::UI::Text) {}

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
that would otherwise be unaware of each other.

The outer container is C<TOP_TO_BOTTOM>; each row is wrapped in a
C<LEFT_TO_RIGHT> L<Clay::UI::Box>. Pass C<cell_gap> to control the
horizontal gap between cells in a row; pass C<row_gap> for the vertical
gap between rows.

=head1 FIELDS

=head2 cell_gap (default 0)

Pixel gap between cells within a row. Forwarded to the row container's
C<child_gap>. Read/write accessor: C<< $grid->cell_gap >> reads,
C<< $grid->cell_gap($px) >> writes. Because the gap is baked into each
row box when the row is built, a write rewrites every existing row in
place so the change is visible on the next C<render>.

=head2 row_gap (default 0)

Pixel gap between rows. Used as the outer container's C<child_gap>.
Read/write accessor: C<< $grid->row_gap >> reads,
C<< $grid->row_gap($px) >> writes. It is re-read on every C<render>, so a
write takes effect immediately. Note C<row_gap> only applies to the
Grid's default outer layout; if a consumer passes an explicit C<layout>,
that layout's own C<child_gap> wins.

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
C<height_group>.

=head2 set_cell ($row, $col, $widget)

Replace the cell at C<($row, $col)>. Wrap-or-use rule: a
C<Clay::UI::Grid::Cell> is used directly, anything else is wrapped
unstyled. C<$col> may equal the current row length to extend the row;
C<$row> must reference an existing row.

=head2 append_row (\@cells)

Add a new row at the bottom. Allocates one new C<height_group>; widens
the column-id cache if the new row is longer than any previous row.

=head2 insert_row ($index, \@cells)

Insert a new row at C<$index> (C<0..row_count> inclusive at the upper
end). Same id-allocation as C<append_row>.

=head2 remove_row ($index)

Splice out the row at C<$index>. The row's C<height_group> id is
abandoned (not recycled into the local counter); the 20-bit local space
makes this harmless in practice.

=head2 replace_row ($index, \@cells)

Replace the row at C<$index> in place, reusing the row's existing
C<height_group> id. Widens the column-id cache if the new row is longer.

=head2 No widget reuse

Per L<Clay::UI::Role::Layout::HasParent/NO REPARENTING>, a widget's
parent is set exactly once. All mutators above expect freshly built
widgets; passing a widget that has already been attached anywhere
(including to this same grid) will die. Likewise, widgets removed via
C<remove_row> / C<replace_row> cannot be reattached.

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
or row claims the next local index in its axis.

=back

The pool supports up to 4095 concurrent grids. Destroying a Grid (via
normal Perl refcount destruction) returns its grid-id to a free-list,
so long-running programs that churn grids do not exhaust the namespace.
If the pool is genuinely full when a new Grid is constructed, the
constructor dies with a clear message.

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

Grid-assigned ids occupy values C<E<gt>= 2**20>, so any user-supplied
id below that bound is guaranteed not to collide with an id the Grid
itself would pick.

=cut
