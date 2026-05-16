package Clay::UI::Role::HasCornerRadius;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::HasCornerRadius {
	field $corner_radius :param :reader = undef;

	method contribute_corner_radius ($config) {
		return unless defined $corner_radius;

		$config->{corner_radius} = ref $corner_radius
			? $corner_radius
			: { top_left => $corner_radius, top_right => $corner_radius, bottom_left => $corner_radius, bottom_right => $corner_radius };
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::HasCornerRadius - corner-radius mixin for Clay::UI widgets

=head1 SYNOPSIS

	class My::Box :does(Clay::UI::Role::Element)
	              :does(Clay::UI::Role::HasCornerRadius)
	{}

	# Same radius on all four corners:
	My::Box->new( corner_radius => 6 );

	# Per-corner:
	My::Box->new(
		corner_radius => { top_left => 6, top_right => 6, bottom_left => 0, bottom_right => 0 },
	);

=head1 DESCRIPTION

Mixin role that contributes a C<cornerRadius> slice. Scalar shorthand
expands to a uniform hashref; pass a hashref for per-corner control.

=cut
