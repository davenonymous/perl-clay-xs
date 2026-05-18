package Clay::UI::Role::Events::Emitter;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(blessed);

use Clay::UI::Enum::Bubble;
use Clay::UI::Enum::Result;
use Clay::UI::Role::Layout::HasParent;
use Clay::UI::Role::Events::Listener;

our $VERSION = '0.01';

role Clay::UI::Role::Events::Emitter :does(Clay::UI::Role::Layout::HasParent)
                                     :does(Clay::UI::Role::Events::Listener) {
	method fire_event ($event) {
		die "Clay::UI::Role::Events::Emitter: fire_event needs a Clay::UI::Events::Event instance"
			unless blessed($event) && $event->isa('Clay::UI::Events::Event');

		$event->_set_target($self);  # dies on re-fire

		my $mode = $event->bubble_mode;
		my $always = Clay::UI::Enum::Bubble->ALWAYS;
		my $never  = Clay::UI::Enum::Bubble->NEVER;
		my $cont   = Clay::UI::Enum::Result->CONTINUE;

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

Clay::UI::Role::Events::Emitter - mixin role giving a widget fire_event()

=head1 SYNOPSIS

	# Composed into widgets that originate events (Box, ...).
	# Listening is separately available on every widget via
	# Clay::UI::Role::Events::Listener.

	$button->fire_event(
		Clay::UI::Events::OnPress->new(x => 10, y => 20),
	);

=head1 DESCRIPTION

The I<send> half of the Clay::UI event system. Composed into widget
classes that originate events (currently L<Clay::UI::Box>; future
widgets like a scroll-aware container would add it too). The
complementary I<receive> half lives in
L<Clay::UI::Role::Events::Listener> and is composed transitively into
every widget via the structural roles, so any widget - emitter or not -
can be a bubble target.

Emitter itself composes L<Clay::UI::Role::Layout::HasParent> and
L<Clay::UI::Role::Events::Listener> so the C<parent> chain walk and
C<handlers_for> lookup it relies on are always available, regardless
of what else the consuming widget composes.

=head1 METHODS

=head2 fire_event($event)

Dispatches a L<Clay::UI::Events::Event> instance. Stamps
C<< $event->target >> with C<$self> (raises if the event was already
dispatched), then walks handlers at the originating widget and,
according to C<< $event->bubble_mode >>, up the C<parent> chain.

=head1 BUBBLE MODES

All handlers registered at the current widget fire (in registration
order) before bubbling is reconsidered. The walk then chooses whether
to step to C<< $node->parent >> based on C<< $event->bubble_mode >>
(a L<Clay::UI::Enum::Bubble> singleton):

=over 4

=item C<< Clay::UI::Enum::Bubble->ALWAYS >>

Steps to the next ancestor regardless of any return value.

=item C<< Clay::UI::Enum::Bubble->IF_CONTINUE >> (the default for new events)

Steps to the next ancestor only when B<every> handler at the current
node returned C<< Clay::UI::Enum::Result->CONTINUE >>. A single
handler returning C<undef>, C<< Clay::UI::Enum::Result->HANDLED >>,
or any unrelated value terminates the bubble walk B<after> the current
node finishes. Sibling handlers at the same node still all run; the
stop decision is per-node, not per-handler.

=item C<< Clay::UI::Enum::Bubble->NEVER >>

Never steps. The originating widget is the only node that sees the
event.

=back

=cut
