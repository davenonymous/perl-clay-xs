package Clay::UI::Role::Interaction::Focusable;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Layout::HasParent;
use Clay::UI::Role::Events::Emitter;
use Clay::UI::Role::Style::HasStates;

our $VERSION = '0.01';

role Clay::UI::Role::Interaction::Focusable :does(Clay::UI::Role::Layout::HasParent)
                                            :does(Clay::UI::Role::Events::Emitter)
                                            :does(Clay::UI::Role::Style::HasStates) {
	# Whether the widget may take focus as far as its users are concerned;
	# can_focus also asks the widget's class and whether it is disabled.
	field $wants_focus :param(can_focus) = 1;

	ADJUST {
		$wants_focus = _focus_flag($wants_focus);
	}

	# The reader answers whether the widget can take focus now; the writer
	# records the wish. Not drawn, so a write does not bump the revision,
	# but a widget that can no longer take focus loses it at once.
	method can_focus (@new) {
		if (@new) {
			die "Clay::UI: 'can_focus' takes one value\n" unless @new == 1;
			$wants_focus = _focus_flag($new[0]);
			my $ui = $self->ui;
			$ui->interaction->release_ineligible($self) if defined $ui;
		}
		return 0 unless $wants_focus && $self->accepts_focus;
		return 0 if $self->DOES('Clay::UI::Role::Interaction::Disableable') && $self->disabled;
		return 1;
	}

	# Whether widgets of the class take focus at all; a subclass that never
	# does (a radio button whose group takes it) overrides this.
	method accepts_focus () {
		return 1;
	}

	sub _focus_flag ($value) {
		die "Clay::UI: 'can_focus' must be a plain boolean value\n" if ref $value;
		return $value ? 1 : 0;
	}

	method is_focused () {
		my $ui = $self->ui;
		return defined $ui ? $ui->interaction->is_focused($self) : 0;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Interaction::Focusable - role marking a widget as focusable

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Role::Core::Element;
	use Clay::UI::Role::Interaction::Focusable;
	use Clay::UI::Role::Interaction::Disableable;

	class My::TextInput :strict(params)
		:does(Clay::UI::Role::Core::Element)
		:does(Clay::UI::Role::Interaction::Focusable)
		:does(Clay::UI::Role::Interaction::Disableable)
	{}

	my $input = My::TextInput->new(id => 'name');
	$input->on('OnFocus', sub ($e) { warn "got focus" });
	$input->on('OnBlur',  sub ($e) { warn "lost focus" });

	# ... after attaching to a Clay::UI ...
	$ui->interaction->set_focused_widget($input);
	$input->is_focused;   # 1
	$input->disabled(1);  # OnBlur fires; can_focus is 0 until it is enabled

=head1 DESCRIPTION

Composed by widgets that participate in the focus system. The UI's
interaction tracker (L<Clay::UI::Interaction>) tracks which Focusable
is the currently focused widget; Focusable's job is to advertise eligibility
and let the widget query its own focus state.

Composes L<Clay::UI::Role::Layout::HasParent> (for the C<parent> chain
walk and the C<ui> back-reference to Clay::UI) and
L<Clay::UI::Role::Events::Emitter> (so OnFocus / OnBlur events can be
fired and bubble up the parent chain).

=head1 METHODS

=head2 can_focus, can_focus($bool)

Reads whether the widget can take the focus now, 1 or 0: it can when
its users want it to (the C<can_focus> named argument of the
constructor, default true, or the last value written), its class
accepts the focus (L</accepts_focus>), and it is not disabled, when it
composes L<Clay::UI::Role::Interaction::Disableable>.

Writing records what the users want, whatever the widget's state: a
widget written C<can_focus(1)> while disabled takes the focus once it
is enabled, and one built with C<< can_focus => 0 >> stays unfocusable
when it is enabled. A write takes any plain boolean value and dies for
a reference, returns what reading returns now, and does not bump the
revision, since nothing drawn depends on it. When the widget has the
focus and cannot take it any more, it loses it at once: the tracker
fires C<OnBlur> on it (see L<Clay::UI::Interaction/"release_ineligible($widget)">).

C<< $ui->interaction->set_focused_widget >>, C<focus_next>, and
C<focus_previous> all consult C<can_focus>; a widget that returns false is skipped by
the default focus chain, rejected (loud die) by direct
C<set_focused_widget> calls, and means "no change" when a
L<Clay::UI::Role::Interaction::HasFocusOrder> returns it.

=head2 accepts_focus

	method accepts_focus :override () { return 0 }

Whether widgets of the class take the focus at all; the default is 1.
A subclass of a class that composes Focusable overrides it when its
widgets never take the focus themselves, for example a radio button
whose group takes the focus for all its buttons. L</"can_focus, can_focus($bool)"> then
returns 0 whatever was written. Since a class cannot override a method
of a role it composes itself, the override belongs into a subclass.

=head2 is_focused

Returns C<1> when this widget is the one currently held in
C<< $self->ui->interaction->get_focused_widget >>, C<0> otherwise. Returns C<0>
when the widget has not yet been attached to a Clay::UI.

=cut
