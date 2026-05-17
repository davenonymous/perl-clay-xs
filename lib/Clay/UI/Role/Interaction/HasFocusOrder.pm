package Clay::UI::Role::Interaction::HasFocusOrder;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Layout::HasParent;

our $VERSION = '0.01';

role Clay::UI::Role::Interaction::HasFocusOrder :does(Clay::UI::Role::Layout::HasParent) {
	method get_next_focus;
	method get_previous_focus;

	method default_next_focus () {
		my $ui = $self->ui;
		return undef unless defined $ui;
		return $ui->_compute_default_next_focus($ui->get_focused_widget);
	}

	method default_previous_focus () {
		my $ui = $self->ui;
		return undef unless defined $ui;
		return $ui->_compute_default_previous_focus($ui->get_focused_widget);
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Interaction::HasFocusOrder - container-level override of focus traversal

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Role::Core::Element;
	use Clay::UI::Role::Interaction::HasFocusOrder;

	class My::ToolbarFirst
		:does(Clay::UI::Role::Core::Element)
		:does(Clay::UI::Role::Interaction::HasFocusOrder)
	{
		field $toolbar :param :reader;

		method get_next_focus {
			# Always jump to the toolbar before anything else
			my $focused = $self->ui->get_focused_widget;
			return $toolbar if !defined($focused) || $focused != $toolbar;
			# After the toolbar, defer to the default order.
			return $self->default_next_focus;
		}

		method get_previous_focus { $self->default_previous_focus }
	}

=head1 DESCRIPTION

Composed by container widgets that want to override the default
depth-first focus traversal for a subtree. When
L<Clay::UI/focus_next> or L<Clay::UI/focus_previous> is called, the
controller walks up from the currently focused widget; the B<nearest>
ancestor (including the focused widget itself) that composes
HasFocusOrder takes over. Its C<get_next_focus> /
C<get_previous_focus> is called with no arguments and must return
either a Focusable widget belonging to the same tree, or C<undef> to
mean "no change".

HasFocusOrder does B<not> imply L<Clay::UI::Role::Interaction::Focusable>:
a container that orchestrates focus need not itself be a focus target.

=head1 REQUIRED METHODS

=head2 get_next_focus

Returns the widget to focus next, or C<undef>. Use
C<< $self->ui->get_focused_widget >> to know where focus currently is.

=head2 get_previous_focus

Mirror of C<get_next_focus> for reverse traversal.

=head1 HELPER METHODS

=head2 default_next_focus

Returns what the unmodified Clay::UI default focus order would pick as
the next widget, given the currently focused widget. Useful for
partial overrides: handle the special case yourself, then C<return
$self->default_next_focus> for everything else.

=head2 default_previous_focus

Mirror of C<default_next_focus>.

=cut
