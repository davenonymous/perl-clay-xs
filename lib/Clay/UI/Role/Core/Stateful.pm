package Clay::UI::Role::Core::Stateful;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::Core::Stateful :does(Clay::UI::Role::Core::Element) {
	ADJUST {
		die "Clay::UI::Role::Core::Stateful: widget '" . (ref $self) . "' requires an explicit 'id'"
			unless defined $self->id;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Core::Stateful - require an explicit id on a Clay::UI widget

=head1 SYNOPSIS

	class My::Toggle :strict(params) :does(Clay::UI::Role::Core::Stateful) { ... }

	My::Toggle->new( id => 'main-toggle' );    # ok
	My::Toggle->new;                            # dies

=head1 DESCRIPTION

Marker role that extends L<Clay::UI::Role::Core::Element> and asserts the
consumer supplied an explicit C<id> at construction. Use for widgets
whose Clay-side state needs a stable addressable id across frames, such
as a scroll container's scroll offset
(L<Clay::UI::Role::Layout::HasScroll> composes it). Hover, press and
focus do not need one: L<Clay::UI::Interaction> tracks widgets by
reference.

=cut
