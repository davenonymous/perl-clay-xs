package Clay::UI::Events::OnHoverStopped;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Enum::Bubble;
use Clay::UI::Events::Event;

our $VERSION = '0.01';

class Clay::UI::Events::OnHoverStopped :isa(Clay::UI::Events::Event) :strict(params) {
	method event_name :common { 'OnHoverStopped' }
	method default_bubble_mode :common { Clay::UI::Enum::Bubble->NEVER }
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

Fired by L<Clay::UI/render> on a L<Clay::UI::Role::Interaction::Hoverable>
widget in the frame the pointer leaves it after having been over it
(also when a hovered widget is removed from the tree). Pairs with
L<Clay::UI::Events::OnHoverStart>. Carries no payload beyond the
inherited C<target> / C<current_target>.

C<name> defaults to C<'OnHoverStopped'>; C<bubble_mode> defaults to
C<< Clay::UI::Enum::Bubble->NEVER >>: like the DOM's C<mouseenter> /
C<mouseleave>, hover events do not bubble, and every hovered widget
gets its own.

=cut
