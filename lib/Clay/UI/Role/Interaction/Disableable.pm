package Clay::UI::Role::Interaction::Disableable;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Revision qw(bump_revision);
use Clay::UI::Role::Layout::HasParent;
use Clay::UI::Role::Style::HasStates;

our $VERSION = '0.01';

role Clay::UI::Role::Interaction::Disableable :does(Clay::UI::Role::Layout::HasParent)
                                              :does(Clay::UI::Role::Style::HasStates) {
	field $disabled :param = 0;

	ADJUST {
		$disabled = _disabled_flag($disabled);
	}

	sub _disabled_flag ($value) {
		die "Clay::UI: 'disabled' must be a plain boolean value\n" if ref $value;
		return $value ? 1 : 0;
	}

	# A widget that becomes disabled loses its focus, arming and press at
	# once, through the tracker.
	method disabled (@new) {
		return $disabled unless @new;
		die "Clay::UI: 'disabled' takes one value\n" unless @new == 1;
		my $value = _disabled_flag($new[0]);
		return $disabled if $value == $disabled;
		$disabled = $value;
		bump_revision();
		my $ui = $self->ui;
		$ui->interaction->release_ineligible($self) if defined $ui;
		return $disabled;
	}

	method is_enabled () {
		return $disabled ? 0 : 1;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Interaction::Disableable - role for widgets that can be
disabled

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Role::Core::Element;
	use Clay::UI::Role::Interaction::Focusable;
	use Clay::UI::Role::Interaction::Pressable;
	use Clay::UI::Role::Interaction::Disableable;

	class My::Button :strict(params)
		:does(Clay::UI::Role::Core::Element)
		:does(Clay::UI::Role::Interaction::Focusable)
		:does(Clay::UI::Role::Interaction::Pressable)
		:does(Clay::UI::Role::Interaction::Disableable)
	{}

	my $button = My::Button->new( id => 'save', disabled => 1 );
	$button->can_focus;      # 0 while disabled
	$button->disabled(0);    # enabled again: can take the focus, can be pressed
	$button->is_enabled;     # 1

=head1 DESCRIPTION

A widget that composes this role can be switched off. While it is
disabled:

=over 4

=item *

it cannot take the focus: L<Clay::UI::Role::Interaction::Focusable/"can_focus, can_focus($bool)">
returns 0, so Tab skips it and C<set_focused_widget> rejects it, while
the widget's own C<can_focus> wish is kept for when it is enabled again;

=item *

it is never armed or pressed (L<Clay::UI::Interaction/"update(%args)">): a press
over it fires no C<OnPress>, a release no C<OnRelease>, and C<is_pressed>
stays 0, although it is still hovered;

=item *

it has the derived state C<disabled> (see
L<Clay::UI::Role::Style::HasStates/DERIVED STATES>).

=back

Disabling a widget that has the focus, or that is armed or pressed,
drops that at once: the interaction tracker fires C<OnBlur> on it right
away (see L<Clay::UI::Interaction/"release_ineligible($widget)">).

Composes L<Clay::UI::Role::Layout::HasParent> (for the C<ui>
back-reference) and L<Clay::UI::Role::Style::HasStates>.

=head1 METHODS

=head2 disabled, disabled($bool)

Reads or writes whether the widget is disabled, 1 or 0. The named
argument C<disabled> of the constructor sets it at first (default 0).
Both take any plain boolean value and die for a reference. A write that
changes the value bumps the revision (L<Clay::UI::Revision>) and lets
the interaction tracker release the widget; it returns the new value.

=head2 is_enabled

1 while the widget is not disabled, 0 while it is.

=cut
