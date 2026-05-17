package Clay::UI::Events::OnScroll;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Events::Event;

our $VERSION = '0.01';

class Clay::UI::Events::OnScroll :isa(Clay::UI::Events::Event) {
	field $delta_x  :param :reader = 0;
	field $delta_y  :param :reader = 0;
	field $userdata :param :reader = undef;

	method event_name :common { 'OnScroll' }
}

1;

__END__

=head1 NAME

Clay::UI::Events::OnScroll - scroll-wheel/touch-scroll event

=head1 SYNOPSIS

	$panel->on('OnScroll', sub ($event) {
		shift_view_by($event->delta_x, $event->delta_y);
	});

=head1 FIELDS

=over 4

=item C<delta_x>, C<delta_y> (default 0)

Scroll delta in arbitrary user-driven units (pixels, ticks, etc.).

=item C<userdata> (default undef)

Opaque payload.

=back

C<name> defaults to C<'OnScroll'>; C<bubble_mode> defaults to
C<< Clay::UI::Enum::Bubble->IF_CONTINUE >>.

=cut
