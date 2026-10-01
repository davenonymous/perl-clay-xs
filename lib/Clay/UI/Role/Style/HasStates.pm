package Clay::UI::Role::Style::HasStates;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

# Derived states and the reader each one is answered by. A widget
# without the reader (no matching interaction role) never has the state.
my %DERIVED = (hovered => 'is_hovered', pressed => 'is_pressed', focused => 'is_focused');

role Clay::UI::Role::Style::HasStates {
	field %_states;

	sub _require_user_state ($name) {
		die "Clay::UI: state '$name' is derived from interaction and cannot be set\n" if exists $DERIVED{$name};
		return;
	}

	method add_state ($name) {
		_require_user_state($name);
		$_states{$name} = 1;
		return $self;
	}

	method remove_state ($name) {
		_require_user_state($name);
		delete $_states{$name};
		return $self;
	}

	method has_state ($name) {
		my $reader = $DERIVED{$name};
		return exists $_states{$name} unless defined $reader;
		return $self->can($reader) && $self->$reader ? 1 : 0;
	}

	method toggle_state ($name) {
		_require_user_state($name);
		if (exists $_states{$name}) {
			delete $_states{$name};
		} else {
			$_states{$name} = 1;
		}
		return $self;
	}

	# Clears the user states; derived states follow interaction.
	method clear_states {
		%_states = ();
		return $self;
	}

	method states {
		return keys(%_states), grep { $self->has_state($_) } sort keys %DERIVED;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Style::HasStates - free-form state-set mixin for Clay::UI widgets

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Role::Core::Element;
	use Clay::UI::Role::Style::HasStates;

	class My::Button :strict(params)
		:does(Clay::UI::Role::Core::Element)
		:does(Clay::UI::Role::Style::HasStates)
	{}

	my $btn = My::Button->new(id => 'go');
	$btn->add_state('disabled');
	$btn->has_state('disabled');   # 1
	$btn->remove_state('disabled');
	$btn->toggle_state('selected');
	my @active = $btn->states;     # list of active state names

=head1 DESCRIPTION

Mixin role that gives a widget a free-form set of state names. State
names are arbitrary strings; the set is unordered and de-duplicated.
Intended for tracking interactive and visual states such as
C<hovered>, C<pressed>, C<focused>, C<disabled>, C<selected>, so
themes and consumers have a single place to read "what is this widget
currently doing?".

=head1 DERIVED STATES

C<hovered>, C<pressed> and C<focused> are derived states: they are
never stored, but answered live by the widget's C<is_hovered>,
C<is_pressed> and C<is_focused> readers, which ask the UI's interaction
tracker (L<Clay::UI::Interaction>) and focus. A widget without the
matching interaction role never has the state. Derived states appear
in C<has_state> and C<states>, but cannot be written: C<add_state>,
C<remove_state> and C<toggle_state> die for them, and C<clear_states>
leaves them alone.

L<Clay::UI::Role::Interaction::Hoverable>,
L<Clay::UI::Role::Interaction::Pressable>, and
L<Clay::UI::Role::Interaction::Focusable> each compose HasStates, so
there is no need to compose it explicitly when an interaction role is
already on the widget; compose it directly only when a widget needs
user states without any interaction wiring.

=head1 METHODS

=over 4

=item C<add_state($name)>

Mark C<$name> as active. Idempotent. Returns C<$self>. Dies for a
derived state.

=item C<remove_state($name)>

Clear C<$name> from the set. Idempotent. Returns C<$self>. Dies for a
derived state.

=item C<has_state($name)>

True if C<$name> is currently active.

=item C<toggle_state($name)>

Flip C<$name>: add it if absent, remove it if present. Returns
C<$self>. Dies for a derived state.

=item C<clear_states>

Drop all user states; derived states keep following interaction.
Returns C<$self>.

=item C<states>

Returns the active state names, user and derived, as a list. Order is unspecified; use
list context only.

=back

=cut
