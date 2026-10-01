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
	# The UI's interaction tracker owns the state; a widget outside a
	# UI is never pressed.
	method is_pressed () {
		my $ui = $self->ui;
		return defined $ui ? $ui->interaction->is_pressed($self) : 0;
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
over it, as of the last L<Clay::UI/render> (or synthetic
L<Clay::UI::Interaction/update>); 0 for a widget outside a Clay::UI.
It asks the UI's interaction tracker, as does the derived C<pressed>
state. Dragging off the widget clears it; dragging back on (still held)
sets it again; removing the widget from the tree drops it.

=back

The UI's interaction tracker fires the events, in the frame in which it
sees the pointer go down or up (see L<Clay::UI/POINTER EVENTS> for the full
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
