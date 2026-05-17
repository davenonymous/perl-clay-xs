package Clay::UI::Events::Event;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(blessed weaken);

use Clay::UI::Events::Bubble;

our $VERSION = '0.01';

class Clay::UI::Events::Event {
	field $name        :param :reader = undef;
	field $bubble_mode :param :reader = Clay::UI::Events::Bubble->IF_CONTINUE;

	field $target         :reader = undef;
	field $current_target :reader = undef;
	field $_dispatched           = 0;

	# Subclasses override this to declare their default event name so
	# callers can `Clay::UI::Events::OnPress->new` without passing name.
	method event_name :common { 'Event' }

	ADJUST {
		$name //= (ref $self)->event_name;
		die "Clay::UI::Events::Event: 'name' must be a non-empty string"
			unless defined $name && length $name;
		die "Clay::UI::Events::Event: 'bubble_mode' must be a Clay::UI::Events::Bubble value"
			unless blessed($bubble_mode) && $bubble_mode->isa('Clay::UI::Events::Bubble');
	}

	# Set by Clay::UI::Events::Emitter at the start of dispatch. Refuses to
	# overwrite an already-set target so a single event object cannot be
	# silently re-fired with a different originator.
	method _set_target ($widget) {
		die "Clay::UI::Events::Event: event already dispatched; build a fresh event to fire again"
			if $_dispatched;
		$target = $widget;
		weaken $target;
		$_dispatched = 1;
		return;
	}

	method _set_current_target ($widget) {
		$current_target = $widget;
		weaken $current_target;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Events::Event - base class for Clay::UI events

=head1 SYNOPSIS

	use Clay::UI::Events::Event;
	use Clay::UI::Events::Bubble;

	my $event = Clay::UI::Events::Event->new(
		name        => 'MyCustom',
		bubble_mode => Clay::UI::Events::Bubble->ALWAYS,
	);

=head1 DESCRIPTION

Base class every concrete event derives from. Provides the four fields
the dispatcher cares about:

=over 4

=item C<name> (optional)

The string the listener registers against via
C<< $widget->on($name, $sub) >>. Falls back to whatever
C<< $class->event_name >> returns when omitted; the base class returns
C<'Event'>, and concrete sub-classes override the C<:common> method to
return their canonical name (C<'OnHover'>, C<'OnPress'>, ...).

=item C<bubble_mode> (default C<BUBBLE_IF_CONTINUE>)

A L<Clay::UI::Events::Bubble> singleton selecting the propagation
policy. See L<Clay::UI::Events::Emitter/BUBBLE MODES>.

=item C<target> (set by the emitter)

The widget on which C<fire_event> was originally invoked. Stays
constant across bubbling.

=item C<current_target> (set by the emitter)

The widget currently dispatching handlers. Equal to C<target> on the
first hop; equals the bubble cursor on subsequent hops. Both are weak
references so a fired event never holds the tree alive.

=back

Sub-classes typically just declare extra payload fields (pointer
position, scroll delta, key modifiers, ...) and override
C<event_name :common>. See L<Clay::UI::Events::OnHover>,
L<Clay::UI::Events::OnPress>, L<Clay::UI::Events::OnScroll>.

=head1 RE-FIRING

An event object is single-use. The first call to C<fire_event> stamps
the target; any subsequent firing raises an exception. Build a fresh
event per dispatch.

=cut
