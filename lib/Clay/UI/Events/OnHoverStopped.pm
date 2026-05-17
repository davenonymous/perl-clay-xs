package Clay::UI::Events::OnHoverStopped;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Events::Event;

our $VERSION = '0.01';

class Clay::UI::Events::OnHoverStopped :isa(Clay::UI::Events::Event) {
	method event_name :common { 'OnHoverStopped' }
}

1;

__END__

=head1 NAME

Clay::UI::Events::OnHoverStopped - edge-triggered hover-exit event

=head1 SYNOPSIS

	$button->on('OnHoverStopped', sub ($event) {
		warn "pointer left ", $event->target->id;
	});

=head1 DESCRIPTION

Fired by L<Clay::UI::Role::Interaction::Hoverable> on the frame the pointer first
leaves the widget after having been over it. Pairs with
L<Clay::UI::Events::OnHoverStart>. Carries no payload beyond the
inherited C<target> / C<current_target>.

C<name> defaults to C<'OnHoverStopped'>; C<bubble_mode> defaults to
C<< Clay::UI::Enum::Bubble->IF_CONTINUE >> (inherited).

=cut
