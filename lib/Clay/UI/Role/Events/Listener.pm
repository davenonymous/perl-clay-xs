package Clay::UI::Role::Events::Listener;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::Events::Listener {
	field %_handlers;

	method on ($event_name, $handler) {
		die "Clay::UI::Role::Events::Listener: event name must be a non-empty string"
			unless defined $event_name && length $event_name;
		die "Clay::UI::Role::Events::Listener: handler must be a coderef"
			unless ref $handler eq 'CODE';
		push @{ $_handlers{$event_name} }, $handler;
		return $self;
	}

	method handlers_for ($event_name) {
		return [] unless exists $_handlers{$event_name};
		return [ @{ $_handlers{$event_name} } ];  # defensive copy
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Events::Listener - mixin role giving every Clay::UI widget on()

=head1 SYNOPSIS

	# Composed automatically into every widget via Role::Element and
	# Role::TextNode; you never compose it directly.

	$box->on('OnPress', sub ($event) {
		warn "saw a press at ", $event->target->id;
	});

=head1 DESCRIPTION

Mixin role composed transitively into every Clay::UI widget (through
L<Clay::UI::Role::Core::Element> and L<Clay::UI::Role::Core::TextNode>). Provides
the I<receive> half of the event system - registration of handlers and
read-back of the per-widget handler list.

The complementary I<send> half (C<fire_event>) lives in
L<Clay::UI::Role::Events::Emitter> and is composed only into widgets that
originate events (e.g. L<Clay::UI::Box>).
A non-emitting widget can still be a bubble target: when an Emitter
fires an event, the dispatcher walks up the parent chain and calls
C<handlers_for> on every ancestor, regardless of whether each ancestor
is itself an Emitter.

=head1 METHODS

=head2 on($event_name, $handler)

Registers C<$handler> (a coderef receiving the dispatched event object)
as a listener for events whose C<name> equals C<$event_name>. Multiple
handlers can be registered against the same name; they fire in
registration order. Returns C<$self> for chaining.

=head2 handlers_for($event_name)

Returns an arrayref (a fresh shallow copy) of registered handlers for
C<$event_name>. Useful for introspection and tests, and called by
L<Clay::UI::Role::Events::Emitter/fire_event> during the bubble walk.

=cut
