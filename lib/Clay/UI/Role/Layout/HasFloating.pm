package Clay::UI::Role::Layout::HasFloating;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::_validate qw(optional clay_struct);
use Clay::UI::Revision qw(bump_revision);

our $VERSION = '0.01';

role Clay::UI::Role::Layout::HasFloating {
	field $floating :param = undef;

	ADJUST {
		$floating = optional(clay_struct('Clay_FloatingElementConfig'), floating => $floating);
	}

	method floating (@new) {
		return $floating unless @new;
		$floating = optional(clay_struct('Clay_FloatingElementConfig'), floating => @new);
		bump_revision();
		return $floating;
	}

	method contribute_floating ($config) {
		return unless defined $floating;
		$config->{floating} = { %$floating };
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Layout::HasFloating - floating-element mixin for Clay::UI widgets

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::XS qw(CLAY_ATTACH_TO_PARENT CLAY_ATTACH_POINT_CENTER_BOTTOM CLAY_ATTACH_POINT_CENTER_TOP);
	use Clay::UI::Role::Core::Element;
	use Clay::UI::Role::Layout::HasFloating;

	class My::Tooltip :strict(params) :does(Clay::UI::Role::Core::Element)
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
one argument to write. A write takes effect on the next C<render>. The
value must be a hashref using the keys Clay reads (C<offset>, C<expand>,
C<parent_id>, C<z_index>, C<attach_points>, C<pointer_capture_mode>,
C<attach_to>, C<clip_to>) with values of the right shape; C<parent_id> is
a numeric element id or an id hash from C<Clay_GetElementId>. Anything
else dies when set.

=cut
