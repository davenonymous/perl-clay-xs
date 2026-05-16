package Clay::UI::Role::HasClip;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::HasClip {
	field $clip :param :reader = undef;

	method contribute_clip ($config) {
		return unless defined $clip;
		$config->{clip} = $clip;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::HasClip - clip-region mixin for Clay::UI widgets

=head1 SYNOPSIS

	class My::ScrollBox :does(Clay::UI::Role::Element)
	                    :does(Clay::UI::Role::HasClip)
	{}

	My::ScrollBox->new(
		clip => { horizontal => 1, vertical => 1, child_offset => { x => 0, y => 0 } },
	);

=head1 DESCRIPTION

Mixin role that contributes a C<clip> slice to the Clay element
declaration. Use this for scrollable or clipped containers; pair with
L<Clay::UI::Role::Element>'s id mechanism if you need
C<Clay_GetScrollContainerData> support.

=cut
