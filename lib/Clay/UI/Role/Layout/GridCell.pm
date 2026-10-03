package Clay::UI::Role::Layout::GridCell;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

# A marker: Clay::UI::Grid lays out a widget composing this role as the
# cell itself, stamping the column and row sizing groups on it, instead of
# wrapping it in an unstyled Clay::UI::Grid::Cell. The methods it needs
# come from Clay::UI::Role::Core::Element (HasSizingGroup).
role Clay::UI::Role::Layout::GridCell {
	method width_group;
	method height_group;
	method _set_grid_groups;
}

1;

__END__

=head1 NAME

Clay::UI::Role::Layout::GridCell - mark a widget as a cell Clay::UI::Grid uses as it is

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Box;
	use Clay::UI::Role::Layout::GridCell;

	# A styled container of your own that a Grid takes as a cell.
	class My::Cell :strict(params) :does(Clay::UI::Box) :does(Clay::UI::Role::Layout::GridCell) {}

	my $cell = My::Cell->new(background_color => [40, 40, 60, 255]);
	$cell->add_child($label);
	$grid->append_row([ $cell, $other_widget ]);

=head1 DESCRIPTION

L<Clay::UI::Grid> sizes its columns and rows by giving every cell a
column C<width_group> and a row C<height_group> (see
L<Clay::UI::Role::Layout::HasSizingGroup>). A widget that composes this
role is that cell: the Grid stamps the group ids on it, so its box,
background and border cover exactly the equalized column width and row
height. Any other widget is wrapped in an unstyled
L<Clay::UI::Grid::Cell> first, and only the wrapper gets the ids.

The role is a marker: it adds no fields and no methods. It requires the
sizing-group methods of L<Clay::UI::Role::Core::Element>, so the
widget must compose that role (directly, through
L<Clay::UI::Role::Core::Container> or L<Clay::UI::Box>, or through a
superclass). L<Clay::UI::Grid::Cell> composes it.

Use it for a cell class of your own when the cells need more than
L<Clay::UI::Grid::Cell> offers, for example events or a renderer's own
border styles. The cell's C<layout> is kept as it is: give it
C<sizing_grow()> width to make its column take the space left in the
grid, or a C<sizing_fit($min, $max)> width to limit the column.

=head1 SEE ALSO

L<Clay::UI::Grid>, L<Clay::UI::Grid::Cell>.

=cut
