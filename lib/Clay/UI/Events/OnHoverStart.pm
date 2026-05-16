package Clay::UI::Events::OnHoverStart;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Events::Event;

our $VERSION = '0.01';

class Clay::UI::Events::OnHoverStart :isa(Clay::UI::Events::Event) {
	method event_name :common { 'OnHoverStart' }
}

1;

__END__

=head1 NAME

Clay::UI::Events::OnHoverStart - edge-triggered hover-entry event

=head1 SYNOPSIS

	$button->on('OnHoverStart', sub ($event) {
		warn "pointer entered ", $event->target->id;
	});

=head1 DESCRIPTION

Fired by L<Clay::UI::Role::Hoverable> on the frame the pointer first
moves over the widget. Pairs with L<Clay::UI::Events::OnHoverStopped>.
Carries no payload beyond the inherited C<target> / C<current_target>;
both expose the originating widget.

C<name> defaults to C<'OnHoverStart'>; C<bubble_mode> defaults to
C<BUBBLE_IF_CONTINUE> (inherited).

=cut
