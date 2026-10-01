package Clay::UI::Role::Interaction::Hoverable;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Layout::HasParent;
use Clay::UI::Role::Events::Emitter;
use Clay::UI::Role::Style::HasStates;
use Clay::UI::Events::OnHoverStart;
use Clay::UI::Events::OnHoverStopped;

our $VERSION = '0.01';

role Clay::UI::Role::Interaction::Hoverable :does(Clay::UI::Role::Layout::HasParent)
                                            :does(Clay::UI::Role::Events::Emitter)
                                            :does(Clay::UI::Role::Style::HasStates) {
	ADJUST {
		die "Clay::UI: " . ref($self) . " composes Clay::UI::Role::Interaction::Hoverable on a text node;"
			. " Clay cannot report the pointer over text elements - wrap the text in an Element"
			if $self->DOES('Clay::UI::Role::Core::TextNode');
	}

	# The UI's interaction tracker owns the state; a widget outside a
	# UI is never hovered.
	method is_hovered () {
		my $ui = $self->ui;
		return defined $ui ? $ui->interaction->is_hovered($self) : 0;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Interaction::Hoverable - hover tracking with edge-triggered events

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Role::Core::Stateful;
	use Clay::UI::Role::Interaction::Hoverable;

	class My::HoverBox :strict(params)
		:does(Clay::UI::Role::Core::Stateful)
		:does(Clay::UI::Role::Interaction::Hoverable)
	{}

	my $box = My::HoverBox->new(id => 'tile');
	$box->on('OnHoverStart',   sub ($e) { warn "entered" });
	$box->on('OnHoverStopped', sub ($e) { warn "left" });

	# Later: $box->is_hovered returns the live boolean.

=head1 DESCRIPTION

Composing widgets get:

=over 4

=item C<is_hovered> (reader)

True while the pointer is over the widget, as of the last
L<Clay::UI/render> (or synthetic L<Clay::UI::Interaction/update>); 0
for a widget outside a Clay::UI. It asks the UI's interaction tracker,
as does the derived C<hovered> state of
L<Clay::UI::Role::Style::HasStates>.

=item Events

L<Clay::UI::Events::OnHoverStart> when the pointer enters the widget and
L<Clay::UI::Events::OnHoverStopped> when it leaves (or at once, when the
widget is removed from the tree while hovered). Like the DOM's C<mouseenter> /
C<mouseleave>, they do not bubble by default: every hovered widget -
nested ones included - gets its own event.

=back

The widget needs no wiring: L<Clay::UI/render> works out which widgets
are under the pointer from Clay's pointer-over list and fires the
events itself, before it lays out the frame (see
L<Clay::UI/POINTER EVENTS>). Listeners may therefore change the tree.

Hover tracking needs an element: composing Hoverable (or
L<Clay::UI::Role::Interaction::Pressable>) onto a text node dies at
construction, because Clay does not report the pointer over text
elements. Wrap the text in an Element and make that hoverable.

Hoverable composes L<Clay::UI::Role::Layout::HasParent>,
L<Clay::UI::Role::Events::Emitter> and
L<Clay::UI::Role::Style::HasStates> transitively.

=cut
