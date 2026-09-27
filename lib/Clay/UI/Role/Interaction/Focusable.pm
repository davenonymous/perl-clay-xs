package Clay::UI::Role::Interaction::Focusable;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(blessed refaddr);

use Clay::UI::Role::Layout::HasParent;
use Clay::UI::Role::Events::Emitter;
use Clay::UI::Role::Style::HasStates;

our $VERSION = '0.01';

role Clay::UI::Role::Interaction::Focusable :does(Clay::UI::Role::Layout::HasParent)
                                            :does(Clay::UI::Role::Events::Emitter)
                                            :does(Clay::UI::Role::Style::HasStates) {
	field $can_focus :param :accessor = 1;

	method is_focused () {
		my $ui = $self->ui;
		return 0 unless defined $ui;
		my $focused = $ui->get_focused_widget;
		return 0 unless defined $focused;
		return refaddr($focused) == refaddr($self) ? 1 : 0;
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

	class My::TextInput :strict(params)
		:does(Clay::UI::Role::Core::Element)
		:does(Clay::UI::Role::Interaction::Focusable)
	{
		field $disabled :param :reader = 0;
		ADJUST { $self->can_focus(0) if $disabled }
	}

	my $input = My::TextInput->new(id => 'name');
	$input->on('OnFocus', sub ($e) { warn "got focus" });
	$input->on('OnBlur',  sub ($e) { warn "lost focus" });

	# ... after attaching to a Clay::UI ...
	$ui->set_focused_widget($input);
	$input->is_focused;   # 1

=head1 DESCRIPTION

Composed by widgets that participate in the focus system. The
companion controller (L<Clay::UI>) tracks which Focusable is the
currently focused widget; Focusable's job is to advertise eligibility
and let the widget query its own focus state.

Composes L<Clay::UI::Role::Layout::HasParent> (for the C<parent> chain
walk and the C<ui> back-reference to Clay::UI) and
L<Clay::UI::Role::Events::Emitter> (so OnFocus / OnBlur events can be
fired and bubble up the parent chain).

=head1 METHODS

=head2 can_focus, can_focus($bool)

Read or write the per-instance focusability flag. Defaults to true; pass
the C<can_focus> named argument to the constructor (e.g.
C<< My::Input->new(id => 'x', can_focus => 0) >>) to start disabled, or
toggle it later with C<< $widget->can_focus(0) >>.

For widgets whose focusability is derived from other state (a
C<$disabled> field, an externally-supplied predicate, ...), drive the
accessor from an C<ADJUST> block or any state-mutating method:

	field $disabled :param :reader = 0;
	ADJUST { $self->can_focus(0) if $disabled }

C<< $ui->set_focused_widget >>, C<focus_next>, and C<focus_previous>
all consult C<can_focus>; a widget that returns false is skipped by
the default focus chain, rejected (loud die) by direct
C<set_focused_widget> calls, and means "no change" when a
L<Clay::UI::Role::Interaction::HasFocusOrder> returns it. Turning
C<can_focus> off does not blur a widget that already has the focus;
C<focus_next> and C<focus_previous> move on from its position.

=head2 is_focused

Returns C<1> when this widget is the one currently held in
C<< $self->ui->get_focused_widget >>, C<0> otherwise. Returns C<0>
when the widget has not yet been attached to a Clay::UI.

=cut
