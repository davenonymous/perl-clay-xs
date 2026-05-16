package Clay::UI::Events;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Exporter 'import';

use Clay::UI::Events::Bubble;
use Clay::UI::Events::Result;

our $VERSION = '0.01';

our @EXPORT_OK = qw(
	EVENT_HANDLED
	EVENT_CONTINUE
	BUBBLE_ALWAYS
	BUBBLE_IF_CONTINUE
	BUBBLE_NEVER
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

sub EVENT_HANDLED  () { Clay::UI::Events::Result->HANDLED }
sub EVENT_CONTINUE () { Clay::UI::Events::Result->CONTINUE }

sub BUBBLE_ALWAYS      () { Clay::UI::Events::Bubble->ALWAYS }
sub BUBBLE_IF_CONTINUE () { Clay::UI::Events::Bubble->IF_CONTINUE }
sub BUBBLE_NEVER       () { Clay::UI::Events::Bubble->NEVER }

1;

__END__

=head1 NAME

Clay::UI::Events - constants for the Clay::UI event system

=head1 SYNOPSIS

	use Clay::UI::Events qw(
		EVENT_HANDLED EVENT_CONTINUE
		BUBBLE_ALWAYS BUBBLE_IF_CONTINUE BUBBLE_NEVER
	);

	$widget->on('OnPress', sub ($event) {
		warn "pressed: ", $event->target->id;
		return EVENT_HANDLED;
	});

	$widget->fire_event(
		Clay::UI::Events::OnPress->new(bubble_mode => BUBBLE_IF_CONTINUE),
	);

=head1 DESCRIPTION

Convenience module exporting the singleton constants for the Clay::UI
event system. Two enums live behind these names:

=over 4

=item L<Clay::UI::Events::Bubble> - bubble-policy values
(C<BUBBLE_ALWAYS>, C<BUBBLE_IF_CONTINUE>, C<BUBBLE_NEVER>).

=item L<Clay::UI::Events::Result> - handler return values
(C<EVENT_HANDLED>, C<EVENT_CONTINUE>).

=back

Constants are singleton objects, not strings; compare them with C<==>.

=head1 LISTENER vs EMITTER

The event system is split into two roles:

=over 4

=item L<Clay::UI::Events::Listener>

Provides C<on($name, $handler)> and C<handlers_for($name)>. Composed
transitively into B<every> widget via L<Clay::UI::Role::Element> and
L<Clay::UI::Role::TextNode>, so anything can register a listener and be
a bubble target.

=item L<Clay::UI::Events::Emitter>

Provides C<fire_event($event)>. Composed only into widgets that
originate events (currently L<Clay::UI::Box> and L<Clay::UI::Button>).
Future emitting widgets opt in by adding
C<< :does(Clay::UI::Events::Emitter) >>.

=back

A non-emitting widget still participates in bubbling: the dispatcher
calls C<handlers_for> (a Listener method) on every ancestor regardless
of whether that ancestor is an Emitter.

=head1 EVENT FLOW

Build a typed event object (see L<Clay::UI::Events::Event> and the
concrete subclasses C<OnHoverStart>, C<OnHoverStopped>, C<OnPress>,
C<OnScroll>), then call
C<< $widget->fire_event($event) >>. The emitter:

=over 4

=item 1.

Stamps the firing widget into C<$event->target> (once; re-firing the
same event after dispatch raises an error).

=item 2.

For each ancestor visited, sets C<$event->current_target> to that node
and invokes every handler registered via C<on> at that node, in
registration order.

=item 3.

Decides whether to keep walking up the C<parent> chain based on the
event's C<bubble_mode>:

=over 4

=item *

C<BUBBLE_ALWAYS> walks every ancestor regardless of handler returns.

=item *

C<BUBBLE_IF_CONTINUE> stops as soon as any handler at the current node
returns anything other than C<EVENT_CONTINUE> (C<undef>,
C<EVENT_HANDLED>, or any unrelated value all stop propagation).

=item *

C<BUBBLE_NEVER> stops after the originating widget.

=back

=back

=head1 SEE ALSO

L<Clay::UI::Events::Emitter>, L<Clay::UI::Events::Event>,
L<Clay::UI::Events::OnHoverStart>, L<Clay::UI::Events::OnHoverStopped>,
L<Clay::UI::Events::OnPress>, L<Clay::UI::Events::OnScroll>.

=cut
