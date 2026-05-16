package Clay::UI::Box;

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
use Clay::UI::Role::HasClip;
use Clay::UI::Role::HasFloating;

our $VERSION = '0.01';

class Clay::UI::Box
	:does(Clay::UI::Role::Element)
	:does(Clay::UI::Role::HasLayout)
	:does(Clay::UI::Role::HasBackground)
	:does(Clay::UI::Role::HasBorder)
	:does(Clay::UI::Role::HasCornerRadius)
	:does(Clay::UI::Role::HasClip)
	:does(Clay::UI::Role::HasFloating)
{}

1;

__END__

=head1 NAME

Clay::UI::Box - styled container widget for Clay::UI

=head1 SYNOPSIS

	use Clay::UI::Box;

	my $box = Clay::UI::Box->new(
		id               => 'sidebar',
		layout           => { sizing => { width => sizing_fixed(200), height => sizing_grow() } },
		background_color => [40, 50, 60, 255],
		corner_radius    => 6,
		border_color     => [80, 80, 80, 255],
		border_width     => 1,
		children         => [ ... ],
	);

=head1 DESCRIPTION

The workhorse styled container. Composes L<Clay::UI::Role::Element>
with every property mixin: L<HasLayout|Clay::UI::Role::HasLayout>,
L<HasBackground|Clay::UI::Role::HasBackground>,
L<HasBorder|Clay::UI::Role::HasBorder>,
L<HasCornerRadius|Clay::UI::Role::HasCornerRadius>,
L<HasClip|Clay::UI::Role::HasClip>,
L<HasFloating|Clay::UI::Role::HasFloating>. Pass any combination of
the mixin parameters to the constructor; the inherited C<to_config>
collects every active slice.

=cut
