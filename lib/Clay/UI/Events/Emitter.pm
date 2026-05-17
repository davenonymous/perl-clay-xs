package Clay::UI::Events::Emitter;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(blessed);

use Clay::UI::Events::Bubble;
use Clay::UI::Events::Result;

our $VERSION = '0.01';

role Clay::UI::Events::Emitter {
	# Listener half (handlers_for) is composed separately into every
	# widget through Role::Element / Role::TextNode; the bubble walk
	# below calls handlers_for on every ancestor regardless of whether
	# that ancestor is itself an Emitter. We just require both methods
	# so anything composing Emitter clearly states its expectations.
	method parent;
	method handlers_for;

	method fire_event ($event) {
		die "Clay::UI::Events::Emitter: fire_event needs a Clay::UI::Events::Event instance"
			unless blessed($event) && $event->isa('Clay::UI::Events::Event');

		$event->_set_target($self);  # dies on re-fire

		my $mode = $event->bubble_mode;
		my $always = Clay::UI::Events::Bubble->ALWAYS;
		my $never  = Clay::UI::Events::Bubble->NEVER;
		my $cont   = Clay::UI::Events::Result->CONTINUE;

		my $node = $self;
		while (defined $node) {
			$event->_set_current_target($node);
			my $list = $node->handlers_for($event->name);

			my $any_stop = 0;
			for my $handler (@$list) {
				my $result = $handler->($event);
				$any_stop = 1 unless defined($result) && blessed($result) && $result == $cont;
			}

			return if $mode == $never;
			return if $mode != $always && $any_stop;

			$node = $node->parent;
		}
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Events::Emitter - mixin role giving a widget fire_event()

=head1 SYNOPSIS

	# Composed into widgets that originate events (Box, Button, ...).
	# Listening is separately available on every widget via
	# Clay::UI::Events::Listener.

	$button->fire_event(
		Clay::UI::Events::OnPress->new(x => 10, y => 20),
	);

=head1 DESCRIPTION

The I<send> half of the Clay::UI event system. Composed only into widget
classes that originate events (currently L<Clay::UI::Box> and
L<Clay::UI::Button>; future widgets like a scroll-aware container would
add it too). The complementary I<receive> half lives in
L<Clay::UI::Events::Listener> and is composed transitively into every
widget via the structural roles, so any widget - emitter or not - can be
a bubble target.

=head1 METHODS

=head2 fire_event($event)

Dispatches a L<Clay::UI::Events::Event> instance. Stamps
C<< $event->target >> with C<$self> (raises if the event was already
dispatched), then walks handlers at the originating widget and,
according to C<< $event->bubble_mode >>, up the C<parent> chain.

The role itself does NOT compose L<Clay::UI::Role::HasParent> or
L<Clay::UI::Events::Listener>; it C<requires> the C<parent> and
C<handlers_for> methods. Consumers that already have HasParent +
Listener (every widget) satisfy both without a diamond.

=head1 BUBBLE MODES

All handlers registered at the current widget fire (in registration
order) before bubbling is reconsidered. The walk then chooses whether
to step to C<< $node->parent >> based on C<< $event->bubble_mode >>
(a L<Clay::UI::Events::Bubble> singleton):

=over 4

=item C<< Clay::UI::Events::Bubble->ALWAYS >>

Steps to the next ancestor regardless of any return value.

=item C<< Clay::UI::Events::Bubble->IF_CONTINUE >> (the default for new events)

Steps to the next ancestor only when B<every> handler at the current
node returned C<< Clay::UI::Events::Result->CONTINUE >>. A single
handler returning C<undef>, C<< Clay::UI::Events::Result->HANDLED >>,
or any unrelated value terminates the bubble walk B<after> the current
node finishes. Sibling handlers at the same node still all run; the
stop decision is per-node, not per-handler.

=item C<< Clay::UI::Events::Bubble->NEVER >>

Never steps. The originating widget is the only node that sees the
event.

=back

=cut
