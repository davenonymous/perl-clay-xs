package Clay::UI::Role::Interaction::Pressable;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Interaction::Hoverable;
use Clay::UI::Events::OnPress;
use Clay::UI::Events::OnRelease;

our $VERSION = '0.01';

role Clay::UI::Role::Interaction::Pressable :does(Clay::UI::Role::Interaction::Hoverable) {
	field $is_pressed :reader = 0;

	# Set when a press starts over the widget, cleared by any release. Only
	# an armed widget can receive OnRelease.
	field $_armed = 0;

	method _is_armed () { $_armed }

	method _set_armed ($armed) {
		$_armed = $armed ? 1 : 0;
		return;
	}

	# Set by Clay::UI while it dispatches pointer input; keeps the
	# 'pressed' state in step with is_pressed.
	method _set_pressed ($pressed) {
		$is_pressed = $pressed ? 1 : 0;
		$pressed ? $self->add_state('pressed') : $self->remove_state('pressed');
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Interaction::Pressable - press tracking with OnPress / OnRelease

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Role::Core::Stateful;
	use Clay::UI::Role::Interaction::Pressable;

	class My::Button :strict(params)
		:does(Clay::UI::Role::Core::Stateful)
		:does(Clay::UI::Role::Interaction::Pressable)
	{}

	my $btn = My::Button->new(id => 'go');
	$btn->on('OnPress', sub ($e) {
		warn sprintf "pressed at (%d,%d)", $e->x, $e->y;
	});

=head1 DESCRIPTION

Composed with L<Clay::UI::Role::Interaction::Hoverable> (so press-trackable
widgets are also hover-trackable). Adds:

=over 4

=item C<is_pressed> (reader)

True while a press that started on the widget is held with the pointer
over it, as of the last L<Clay::UI/render>. The C<pressed> state follows
it. Dragging off the widget clears it; dragging back on (still held)
sets it again.

=back

L<Clay::UI/render> fires the events, in the frame in which it sees the
pointer go down or up (see L<Clay::UI/POINTER EVENTS> for the full
rules):

=over 4

=item L<Clay::UI::Events::OnPress>

When the pointer goes down, on exactly one widget: the innermost
Pressable under the pointer (a button inside a pressable card gets the
press, not the card). Every Pressable under the pointer becomes
I<armed>.

=item L<Clay::UI::Events::OnRelease>

When the pointer goes up, on the innermost I<armed> Pressable still
under the pointer - that is a completed click. Releasing off the widget
(press, drag off, release) or releasing over a widget the press did not
start on (press elsewhere, drag in, release) fires nothing. Every
release disarms all widgets.

=back

Both events bubble with C<IF_CONTINUE>: an ancestor sees the event only
if the widget's handlers return C<< Clay::UI::Enum::Result->CONTINUE >>,
and it sees the bubbled event, never a second event of its own.

The role does not fire a synthetic "click" event: combine OnPress and
OnRelease however you like.

	# Short vs long press:
	my $down_at;
	$btn->on('OnPress',   sub ($e) { $down_at = time });
	$btn->on('OnRelease', sub ($e) {
		(time - $down_at) < 0.3 ? short_click() : long_click();
	});

	# A completed click (pressed and released over the button):
	$btn->on('OnRelease', sub ($e) { activate() });

=cut
