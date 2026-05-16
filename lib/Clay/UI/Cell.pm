package Clay::UI::Cell;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Element;
use Clay::UI::Role::HasLayout;
use Clay::UI::Role::HasBackground;
use Clay::UI::Role::HasBorder;
use Clay::UI::Role::HasCornerRadius;

our $VERSION = '0.01';

class Clay::UI::Cell
	:does(Clay::UI::Role::Element)
	:does(Clay::UI::Role::HasLayout)
	:does(Clay::UI::Role::HasBackground)
	:does(Clay::UI::Role::HasBorder)
	:does(Clay::UI::Role::HasCornerRadius)
{}

1;

__END__

=head1 NAME

Clay::UI::Cell - styled single-cell container for Clay::UI::Grid

=head1 SYNOPSIS

	use Clay::UI::Cell;
	use Clay::UI::Grid;
	use Clay::UI::Text;

	my $grid = Clay::UI::Grid->new(
		id   => 'report',
		rows => [
			[
				Clay::UI::Cell->new(
					layout           => { padding => padding_all(8) },
					background_color => [55, 90, 140, 255],
					children         => [ Clay::UI::Text->new(text => 'Header') ],
				),
				Clay::UI::Cell->new(
					layout           => { padding => padding_all(8) },
					background_color => [55, 90, 140, 255],
					children         => [ Clay::UI::Text->new(text => 'Value') ],
				),
			],
			# ...more rows...
		],
	);

=head1 DESCRIPTION

A C<Clay::UI::Cell> is the styled container the Grid uses to carry one
visual cell. Functionally it is identical to L<Clay::UI::Box> without
clip/floating support; the distinction exists because the Grid widget
needs a container it can recognise and use directly rather than
re-wrapping.

When you build a Grid:

=over 4

=item *

Pass a C<Clay::UI::Cell> directly to control the cell's visual styling
(background, border, padding, corner radius). The Grid will set the
cell's C<width_group> / C<height_group> on this object so its rendered
box is exactly the equalized column width and row height.

=item *

Pass any other widget (a L<Clay::UI::Text>, L<Clay::UI::Box>, etc.) to
let the Grid wrap it in an unstyled C<Cell> automatically. The wrapped
cell takes the equalized dimensions but has no visible styling.

=back

The mixin composition gives Cell all of HasLayout, HasBackground,
HasBorder, HasCornerRadius. Pass any of their parameters to the
constructor. Sizing-group ids are inherited via
L<Clay::UI::Role::HasSizingGroup> (composed transitively through
L<Clay::UI::Role::Element>) and are normally set by the enclosing Grid
rather than the caller.

=cut
