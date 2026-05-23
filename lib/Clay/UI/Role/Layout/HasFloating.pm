package Clay::UI::Role::Layout::HasFloating;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::Layout::HasFloating {
	field $floating :param :accessor = undef;

	method contribute_floating ($config) {
		return unless defined $floating;
		$config->{floating} = $floating;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Layout::HasFloating - floating-element mixin for Clay::UI widgets

=head1 SYNOPSIS

	class My::Tooltip :does(Clay::UI::Role::Core::Element)
	                  :does(Clay::UI::Role::Layout::HasFloating)
	{}

	My::Tooltip->new(
		floating => {
			attach_to     => CLAY_ATTACH_TO_PARENT,
			attach_points => { parent => CLAY_ATTACH_POINT_CENTER_BOTTOM, element => CLAY_ATTACH_POINT_CENTER_TOP },
		},
	);

=head1 DESCRIPTION

Mixin role that contributes a C<floating> slice to the Clay element
declaration. Pass any of Clay's floating-element fields; snake_case keys
are camelized by the walker.

C<floating> is a read/write accessor: call with no argument to read, with
one argument to write. A write takes effect on the next C<render>.

=cut
