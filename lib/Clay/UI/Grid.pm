package Clay::UI::Grid;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::XS qw(sizing_fit CLAY_LEFT_TO_RIGHT CLAY_TOP_TO_BOTTOM);
use Clay::UI::Box;
use Clay::UI::Grid::Cell;
use Clay::UI::Role::Core::Element;
use Clay::UI::Role::Layout::HasLayout;
use Clay::UI::Role::Style::HasBackground;
use Clay::UI::Role::Style::HasBorder;
use Clay::UI::Role::Style::HasCornerRadius;

our $VERSION = '0.01';

# Per-process counter that hands out a unique non-zero base id to each Grid
# instance so its column/row group ids never collide with another grid's.
# Each grid claims a contiguous range [base .. base + col_count + row_count).
my $NEXT_GROUP_BASE = 1;

class Clay::UI::Grid
	:does(Clay::UI::Role::Core::Element)
	:does(Clay::UI::Role::Layout::HasLayout)
	:does(Clay::UI::Role::Style::HasBackground)
	:does(Clay::UI::Role::Style::HasBorder)
	:does(Clay::UI::Role::Style::HasCornerRadius)
{
	field $rows :param :reader;
	field $cell_gap :param = 0;
	field $row_gap  :param = 0;
	# Per-cell wrappers ([row][col]). For each input cell: if it is already a
	# Clay::UI::Grid::Cell, it is used directly (so the caller's styling
	# becomes the visible cell); otherwise the Grid wraps it in an unstyled
	# Cell. The wrapper is what Clay sees with the sizing-group ids set, so
	# its rendered box is exactly the equalized column-width x row-height.
	field $cell_wrappers :reader = [];

	ADJUST {
		die "Clay::UI::Grid: 'rows' must be an arrayref"
			unless ref $rows eq 'ARRAY';

		my $row_count = scalar @$rows;
		my $col_count = 0;
		for my $row (@$rows) {
			die "Clay::UI::Grid: each row must be an arrayref"
				unless ref $row eq 'ARRAY';
			$col_count = scalar @$row if scalar @$row > $col_count;
		}

		my $col_base = $NEXT_GROUP_BASE;
		my $row_base = $col_base + $col_count;
		$NEXT_GROUP_BASE = $row_base + $row_count;

		my @row_boxes;
		for my $r (0 .. $row_count - 1) {
			my $row = $rows->[$r];
			my @wrapped_cells;
			my @wrapper_row;
			for my $c (0 .. $#$row) {
				my $cell    = $row->[$c];
				my $wrapper = $cell->isa('Clay::UI::Grid::Cell')
					? $cell
					: Clay::UI::Grid::Cell->new(
						layout   => { sizing => { width => sizing_fit(), height => sizing_fit() } },
						children => [ $cell ],
					);
				$wrapper->width_group($col_base + $c)  if $wrapper->width_group  == 0;
				$wrapper->height_group($row_base + $r) if $wrapper->height_group == 0;
				push @wrapped_cells, $wrapper;
				push @wrapper_row,   $wrapper;
			}
			push @{ $cell_wrappers }, \@wrapper_row;
			push @row_boxes, Clay::UI::Box->new(
				layout => {
					sizing           => { width => sizing_fit(), height => sizing_fit() },
					layout_direction => CLAY_LEFT_TO_RIGHT,
					child_gap        => $cell_gap,
				},
				children => \@wrapped_cells,
			);
		}

		$self->clear_children;
		$self->add_child(@row_boxes);
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

	use Clay::UI::Grid;
	use Clay::UI::Text;

	my $grid = Clay::UI::Grid->new(
		id   => 'data',
		rows => [
			[ Clay::UI::Text->new(text => 'Name'),
			  Clay::UI::Text->new(text => 'Email'),
			  Clay::UI::Text->new(text => 'Role') ],
			[ Clay::UI::Text->new(text => 'Alice'),
			  Clay::UI::Text->new(text => 'alice@example.com'),
			  Clay::UI::Text->new(text => 'Admin') ],
			[ Clay::UI::Text->new(text => 'Bob'),
			  Clay::UI::Text->new(text => 'bob@example.com'),
			  Clay::UI::Text->new(text => 'User') ],
		],
		cell_gap => 8,
		row_gap  => 4,
	);

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

=head2 rows (required)

Arrayref of arrayrefs. Each inner arrayref is one row of widget
instances. Rows may have different lengths (the grid is laid out
row-major; group ids are still assigned by column index, so column
N's width equals the widest cell in column N across all rows that
have a cell at index N).

=head2 cell_gap (default 0)

Pixel gap between cells within a row. Forwarded to the row container's
C<child_gap>.

=head2 row_gap (default 0)

Pixel gap between rows. Used as the outer container's C<child_gap>.

=head1 STYLING CELLS

Pass L<Clay::UI::Grid::Cell> instances directly in C<rows> to control
each cell's appearance. The Grid recognises Cell objects and uses them as
the per-cell wrapper, so their background / border / padding / corner
radius render exactly at the equalized column-width x row-height.

Any non-Cell widget (Text, Box, etc.) is wrapped in an unstyled Cell
automatically; the wrapper still gets the sizing-group ids, but has no
visible styling. Use this when you only care about layout, not
appearance.

=head1 ID NAMESPACING

Each Grid instance claims a unique contiguous range of sizing-group ids
from a process-global counter (starting at 1). Column ids occupy
C<[base .. base + col_count)>; row ids occupy
C<[base + col_count .. base + col_count + row_count)>. Different Grid
instances therefore never collide, including nested grids.

Note that the counter is process-local and not stable across runs.
This is fine for layout (Clay only inspects group equality within a
single frame) but means group ids should not be serialized.

=head1 OVERRIDING GROUP IDS

If a cell already has a non-zero C<width_group> or C<height_group> when
the Grid receives it (set via the C<HasSizingGroup> field, exposed on
every widget), the Grid leaves that axis's id alone. This allows
participation in cross-grid alignment groups: place a cell in your
grid and also assign it a global C<width_group> shared with another
widget elsewhere in the UI.

=cut
