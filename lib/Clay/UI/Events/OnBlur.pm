package Clay::UI::Events::OnBlur;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Events::Event;

our $VERSION = '0.01';

class Clay::UI::Events::OnBlur :isa(Clay::UI::Events::Event) :strict(params) {
	method event_name :common { 'OnBlur' }
}

1;

__END__

=head1 NAME

Clay::UI::Events::OnBlur - edge-triggered focus-lost event

=head1 SYNOPSIS

	$input->on('OnBlur', sub ($event) {
		warn "focus left ", $event->target->id;
	});

=head1 DESCRIPTION

Fired by L<Clay::UI> on the widget that just lost focus, immediately
before the new focus target gets its L<Clay::UI::Events::OnFocus>.
Pairs with L<Clay::UI::Events::OnFocus>. Carries no payload beyond the
inherited C<target> / C<current_target>.

C<name> defaults to C<'OnBlur'>; C<bubble_mode> defaults to
C<< Clay::UI::Enum::Bubble->IF_CONTINUE >> (inherited).

=cut
