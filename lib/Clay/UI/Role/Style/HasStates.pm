package Clay::UI::Role::Style::HasStates;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::Style::HasStates {
	field %_states;

	method add_state ($name) {
		$_states{$name} = 1;
		return $self;
	}

	method remove_state ($name) {
		delete $_states{$name};
		return $self;
	}

	method has_state ($name) {
		return exists $_states{$name};
	}

	method toggle_state ($name) {
		if (exists $_states{$name}) {
			delete $_states{$name};
		} else {
			$_states{$name} = 1;
		}
		return $self;
	}

	method clear_states {
		%_states = ();
		return $self;
	}

	method states {
		return keys %_states;
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

=head1 AUTO-SYNC FROM INTERACTION ROLES

L<Clay::UI::Role::Interaction::Hoverable>,
L<Clay::UI::Role::Interaction::Pressable>, and
L<Clay::UI::Role::Interaction::Focusable> each compose HasStates, so
any widget consuming one of those roles automatically gets the
C<hovered>, C<pressed>, and C<focused> state names pushed in on edge
transitions. There is no need to compose HasStates explicitly when an
interaction role is already on the widget; compose it directly only
when a widget needs the state set without any interaction wiring.

=head1 METHODS

=over 4

=item C<add_state($name)>

Mark C<$name> as active. Idempotent. Returns C<$self>.

=item C<remove_state($name)>

Clear C<$name> from the set. Idempotent. Returns C<$self>.

=item C<has_state($name)>

True if C<$name> is currently active.

=item C<toggle_state($name)>

Flip C<$name>: add it if absent, remove it if present. Returns
C<$self>.

=item C<clear_states>

Drop all active states. Returns C<$self>.

=item C<states>

Returns the active state names as a list. Order is unspecified; use
list context only.

=back

=cut
