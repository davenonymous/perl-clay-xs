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
	use Clay::UI;
	use Clay::UI::Role::Core::Container;
	use Clay::UI::Role::Interaction::Focusable;
	use Clay::UI::Role::Interaction::HasFocusOrder;

	class My::Input :strict(params)
		:does(Clay::UI::Role::Core::Container)
		:does(Clay::UI::Role::Interaction::Focusable)
	{}

	class My::ToolbarFirst :strict(params)
		:does(Clay::UI::Role::Core::Container)
		:does(Clay::UI::Role::Interaction::HasFocusOrder)
	{
		field $toolbar :param :reader;

		method get_next_focus {
			# The first focus_next (nothing focused yet; this widget is the
			# root of the Clay::UI) goes to the toolbar ...
			return $toolbar unless defined $self->ui->get_focused_widget;
			# ... after that the default order applies.
			return $self->default_next_focus;
		}

		method get_previous_focus { $self->default_previous_focus }
	}

	my $toolbar = My::Input->new(id => 'toolbar');
	my $root    = My::ToolbarFirst->new(id => 'root', toolbar => $toolbar);
	$root->add_child(My::Input->new(id => 'name'), My::Input->new(id => 'email'), $toolbar);
	my $ui = Clay::UI->new(root => $root, width => 400, height => 300);
	$ui->focus_next;    # toolbar
	$ui->focus_next;    # name, then email, toolbar, name, ...

=head1 DESCRIPTION

Composed by container widgets that want to override the default
depth-first focus traversal for a subtree. When
L<Clay::UI/focus_next> or L<Clay::UI/focus_previous> is called, the
controller walks up from the currently focused widget; the B<nearest>
ancestor (including the focused widget itself) that composes
HasFocusOrder takes over. With nothing focused, the root of the
L<Clay::UI> takes over if it composes HasFocusOrder.

The chosen widget's C<get_next_focus> / C<get_previous_focus> is called
with no arguments and must return one of:

=over 4

=item C<undef>

Focus does not change.

=item a Focusable widget of the same Clay::UI

It gets the focus - unless its C<can_focus> is false at that moment, in
which case focus does not change either.

=back

Anything else - a non-widget, a widget that does not compose
L<Clay::UI::Role::Interaction::Focusable>, a widget of another
Clay::UI or one that is not attached - is a bug in the composing class:
C<focus_next> / C<focus_previous> dies naming that class and the
problem.

HasFocusOrder does B<not> imply L<Clay::UI::Role::Interaction::Focusable>:
a container that orchestrates focus need not itself be a focus target.

=head1 REQUIRED METHODS

=head2 get_next_focus

Returns the widget to focus next, or C<undef>. Use
C<< $self->ui->get_focused_widget >> to know where focus currently is
(C<undef> when nothing is focused).

=head2 get_previous_focus

Mirror of C<get_next_focus> for reverse traversal.

=head1 HELPER METHODS

=head2 default_next_focus

Returns what the default Clay::UI focus order would pick as the next
widget, given the currently focused widget, without consulting any
HasFocusOrder. Useful for partial overrides: handle the special case
yourself, then C<< return $self->default_next_focus >> for everything
else. Returns C<undef> while the widget is not part of a Clay::UI.

=head2 default_previous_focus

Mirror of C<default_next_focus>.

=cut
