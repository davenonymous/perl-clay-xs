package Clay::UI::Grid::Cell;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Layout::HasLayout;
use Clay::UI::Role::Style::HasBackground;
use Clay::UI::Role::Style::HasBorder;
use Clay::UI::Role::Style::HasCornerRadius;

our $VERSION = '0.01';

class Clay::UI::Grid::Cell :strict(params)
	:does(Clay::UI::Role::Core::Container)
	:does(Clay::UI::Role::Layout::HasLayout)
	:does(Clay::UI::Role::Style::HasBackground)
	:does(Clay::UI::Role::Style::HasBorder)
	:does(Clay::UI::Role::Style::HasCornerRadius)
{}

1;

__END__

=head1 NAME

Clay::UI::Grid::Cell - styled single-cell container for Clay::UI::Grid

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Grid;
	use Clay::UI::Grid::Cell;
	use Clay::UI::Text;

	class My::Grid :strict(params) :does(Clay::UI::Grid) {}
	class My::Text :strict(params) :does(Clay::UI::Text) {}

	my $grid = My::Grid->new(id => 'report');

	use Clay::XS qw(padding_all);

	my $header_cell = Clay::UI::Grid::Cell->new(
		layout           => { padding => padding_all(8) },
		background_color => [55, 90, 140, 255],
	);
	$header_cell->add_child(My::Text->new(text => 'Header'));

	my $value_cell = Clay::UI::Grid::Cell->new(
		layout           => { padding => padding_all(8) },
		background_color => [55, 90, 140, 255],
	);
	$value_cell->add_child(My::Text->new(text => 'Value'));

	$grid->append_row([ $header_cell, $value_cell ]);
	# ...more rows...

=head1 DESCRIPTION

A C<Clay::UI::Grid::Cell> is the styled container the Grid uses to carry
one visual cell. It composes L<Clay::UI::Role::Core::Container> (so
C<add_child> puts content into it), L<Clay::UI::Role::Layout::HasLayout>,
L<Clay::UI::Role::Style::HasBackground>,
L<Clay::UI::Role::Style::HasBorder> and
L<Clay::UI::Role::Style::HasCornerRadius> - but not floating or events.
The distinct class exists because the Grid needs a container it can
recognise and use directly rather than re-wrapping.

When you build a Grid:

=over 4

=item *

Pass a C<Clay::UI::Grid::Cell> directly to control the cell's visual
styling (background, border, padding, corner radius). The Grid will set
the cell's C<width_group> / C<height_group> on this object so its
rendered box is exactly the equalized column width and row height.

=item *

Pass any other widget (a L<Clay::UI::Text>, L<Clay::UI::Box>, etc.) to
let the Grid wrap it in an unstyled C<Cell> automatically. The wrapped
cell takes the equalized dimensions but has no visible styling.

=back

The mixin composition gives Cell all of HasLayout, HasBackground,
HasBorder, HasCornerRadius. Pass any of their parameters to the
constructor. Sizing-group ids are inherited via
L<Clay::UI::Role::Layout::HasSizingGroup> (composed transitively through
L<Clay::UI::Role::Core::Element>) and are normally set by the enclosing Grid
rather than the caller.

=cut
