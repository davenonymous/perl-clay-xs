package Clay::UI::Role::Interaction::Pressable;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::XS qw(
	CLAY_POINTER_DATA_PRESSED
	CLAY_POINTER_DATA_PRESSED_THIS_FRAME
	CLAY_POINTER_DATA_RELEASED_THIS_FRAME
);

use Clay::UI::Role::Interaction::Hoverable;
use Clay::UI::Events::OnPress;
use Clay::UI::Events::OnRelease;

our $VERSION = '0.01';

role Clay::UI::Role::Interaction::Pressable :does(Clay::UI::Role::Interaction::Hoverable) {
	field $is_pressed :reader = 0;

	# Last pointer.state observed during this frame's Clay_OnHover
	# trampoline. The transition hook turns this into $is_pressed at
	# end-of-frame, which lets the reader stay valid between renders.
	field $_press_state_this_frame = undef;

	ADJUST {
		$self->_register_pointer_hook(sub ($pointer, $userdata) {
			$_press_state_this_frame = $pointer->{state};

			# Fire OnPress on the leading edge (PRESSED_THIS_FRAME from
			# a non-pressed state). is_pressed has not yet been updated
			# by the transition hook for this frame, so it still holds
			# the previous frame's value.
			my $pos = $pointer->{position} // { x => 0, y => 0 };
			if (!$is_pressed && $pointer->{state} == CLAY_POINTER_DATA_PRESSED_THIS_FRAME) {
				$self->fire_event(Clay::UI::Events::OnPress->new(
					x        => $pos->{x},
					y        => $pos->{y},
					userdata => $userdata,
				));
			} elsif ($is_pressed && $pointer->{state} == CLAY_POINTER_DATA_RELEASED_THIS_FRAME) {
				$self->fire_event(Clay::UI::Events::OnRelease->new(
					x        => $pos->{x},
					y        => $pos->{y},
					userdata => $userdata,
				));
			}
		});

		$self->_register_transition_hook(sub ($was_over) {
			if (!$was_over) {
				# Pointer not over this widget this frame: no callback
				# fired, so we can't be pressed on this element.
				$is_pressed = 0;
			} else {
				my $st = $_press_state_this_frame;
				$is_pressed = (defined $st
					&& ($st == CLAY_POINTER_DATA_PRESSED
					 || $st == CLAY_POINTER_DATA_PRESSED_THIS_FRAME)) ? 1 : 0;
			}
			$_press_state_this_frame = undef;
		});
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Interaction::Pressable - stateful press-tracking + OnPress event

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Role::Core::Element;
	use Clay::UI::Role::Interaction::Pressable;

	class My::Button
		:does(Clay::UI::Role::Core::Element)
		:does(Clay::UI::Role::Interaction::Pressable)
	{}

	my $btn = My::Button->new(id => 'go');
	$btn->on('OnPress', sub ($e) {
		warn sprintf "pressed at (%d,%d)", $e->x, $e->y;
	});

=head1 DESCRIPTION

Composed with L<Clay::UI::Role::Interaction::Hoverable> (so press-trackable widgets
are also hover-trackable). Adds:

=over 4

=item C<is_pressed> (reader)

Live boolean reflecting whether the pointer is currently down B<and>
over the widget. Goes back to 0 when either condition becomes false.

=back

Fires L<Clay::UI::Events::OnPress> on the leading edge of the
press-down state (Clay's C<CLAY_POINTER_DATA_PRESSED_THIS_FRAME>) and
L<Clay::UI::Events::OnRelease> on the matching release edge
(C<CLAY_POINTER_DATA_RELEASED_THIS_FRAME>) B<while still over the
widget>. Subsequent frames of held-down state do not refire OnPress;
release the pointer and press again to get another event.

The role intentionally does not fire its own synthetic "click" event:
combine OnPress and OnRelease however you like - short press, long
press, release-only, etc.

	# Short vs long press:
	my $down_at;
	$btn->on('OnPress',   sub ($e) { $down_at = time });
	$btn->on('OnRelease', sub ($e) {
		(time - $down_at) < 0.3 ? short_click() : long_click();
	});

	# Release-only behavior (fires only when pointer was pressed AND
	# released over the widget, i.e. a "successful click"):
	$btn->on('OnRelease', sub ($e) { activate() });

A release that happens after the pointer leaves the widget does not
fire OnRelease - the underlying Clay_OnHover callback runs only while
the pointer is over the element. Use that asymmetry for click-cancel
behavior.

Emitter is composed transitively (through Hoverable), so no extra
roles are needed on the consuming widget.

=cut
