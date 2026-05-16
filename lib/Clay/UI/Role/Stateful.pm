package Clay::UI::Role::Stateful;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::Stateful :does(Clay::UI::Role::Element) {
	ADJUST {
		die "Clay::UI::Role::Stateful: widget '" . (ref $self) . "' requires an explicit 'id'"
			unless defined $self->id;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Stateful - require an explicit id on a Clay::UI widget

=head1 SYNOPSIS

	class My::Toggle :does(Clay::UI::Role::Stateful) { ... }

	My::Toggle->new( id => 'main-toggle' );    # ok
	My::Toggle->new;                            # dies

=head1 DESCRIPTION

Marker role that extends L<Clay::UI::Role::Element> and asserts the
consumer supplied an explicit C<id> at construction. Use for widgets
whose Clay-side state (scroll offset, hover, focus) needs a stable
addressable id across frames.

=cut
