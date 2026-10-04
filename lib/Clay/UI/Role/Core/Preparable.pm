package Clay::UI::Role::Core::Preparable;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(refaddr weaken);

use Clay::UI::Revision qw(bump_revision);
use Clay::UI::_error qw(croak_ui);

our $VERSION = '0.01';

# Process-wide, like the revision: refaddr => the widget (weak), for every
# widget whose prepare_layout is due before its UI's next layout pass.
my %_pending;

# Calls prepare_layout on the pending widgets that belong to $ui, until
# none is left (a preparation may request another one). Widgets of other
# UIs, or of none yet, stay pending. Dies when preparations keep
# requesting new ones.
#
# A dying prepare_layout does not stop the round: the other due widgets
# are still prepared (as the remaining events still fire after a listener
# error), then the first error is rethrown. Whatever that round queued
# stays pending for the next render.
use constant _MAX_ROUNDS => 100;

sub _prepare_pending ($ui) {
	for my $round (1 .. _MAX_ROUNDS) {
		my @due = grep { _belongs_to($_, $ui) } map { $_pending{$_} } sort keys %_pending;
		return unless @due;
		delete $_pending{ refaddr $_ } for @due;
		my $first_error;
		for my $widget (@due) {
			local $@;
			eval { $widget->prepare_layout; 1 } or $first_error //= $@ || 'unknown prepare_layout error';
		}
		die $first_error if defined $first_error;
	}
	croak_ui "Clay::UI: widgets kept requesting preparation; " . _MAX_ROUNDS . " rounds of prepare_layout did not settle";
}

sub _belongs_to ($widget, $ui) {
	return 0 unless defined $widget;
	my $owner = $widget->ui;
	return defined $owner && refaddr($owner) == refaddr($ui) ? 1 : 0;
}

role Clay::UI::Role::Core::Preparable {
	# Brings the widget's subtree up to date; called by Clay::UI::render
	# after the frame's events, before the layout pass.
	method prepare_layout;

	method request_prepare () {
		my $address = refaddr $self;
		unless (defined $_pending{$address}) {
			$_pending{$address} = $self;
			weaken $_pending{$address};
		}
		bump_revision();
		return $self;
	}

	method is_prepare_pending () {
		my $pending = $_pending{ refaddr $self };
		return defined $pending && refaddr($pending) == refaddr($self) ? 1 : 0;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Core::Preparable - let a widget rebuild its subtree right before the layout pass

=head1 SYNOPSIS

	use v5.22;
	use Object::Pad;
	use Clay::UI;
	use Clay::UI::Box;
	use Clay::UI::Text;
	use Clay::UI::Role::Core::Preparable;

	class My::Label :strict(params) :does(Clay::UI::Text) {}

	class My::List :strict(params)
		:does(Clay::UI::Box)
		:does(Clay::UI::Role::Core::Preparable)
	{
		field @items;

		method add_item ($item) {
			push @items, $item;
			$self->request_prepare;    # cheap: the children are rebuilt once per frame
			return $self;
		}

		method prepare_layout () {
			$self->clear_children;
			$self->add_child(map { My::Label->new(text => $_) } @items);
			return;
		}
	}

	my $list = My::List->new(id => 'list');
	my $ui   = Clay::UI->new(width => 400, height => 300, root => $list);
	$list->add_item($_) for qw(apples pears plums);
	my $commands = $ui->render;    # prepare_layout ran once, then the layout pass

=head1 DESCRIPTION

A widget whose children follow from state of its own (a list of items,
the rows of a table) would have to rebuild them on every change of that
state. With C<Clay::UI::Role::Core::Preparable> it asks to be prepared
instead and rebuilds them once, right before the next frame is laid
out, however many changes came before.

C<request_prepare> puts the widget in a queue. L<Clay::UI/render> calls
the C<prepare_layout> method of every queued widget after the frame's
pointer events and before the layout pass (the part of C<render> that
declares the tree to Clay), so changes the event listeners made are
included.

=over 4

=item *

Only widgets that belong to the rendering UI are prepared (their
C<ui> is that UI). A widget that is not part of a UI yet stays queued
until a UI it belongs to renders.

=item *

A preparation may change anything (no Clay element is open while it
runs) and may request another preparation, of itself or of other
widgets. C<render> keeps preparing until no request is left, and dies
after 100 rounds with
C<Clay::UI: widgets kept requesting preparation; 100 rounds of prepare_layout did not settle>.


=item *

The queue is shared by all UIs of the process and holds widgets
weakly: a widget freed while it is queued is forgotten.

=back

Compose this role together with a widget role
(L<Clay::UI::Role::Core::Element>, L<Clay::UI::Box>, ...); it uses the
widget's C<ui> method.

=head1 METHODS

=head2 prepare_layout

	method prepare_layout () { ... }

Required: the widget class implements it. It brings the widget (usually
its children) up to date. C<render> calls it with no arguments and
ignores the return value. By the time it runs the widget is no longer
queued, so a C<request_prepare> inside it queues it again.

If C<prepare_layout> dies, the other widgets due in the same round are
still prepared, then C<render> stops preparing: requests made during
that round stay queued for the next C<render>. C<render> still runs the
layout pass and then dies with the first error (or with an earlier
listener error of the same frame).

=head2 request_prepare

	$widget->request_prepare;

Queues the widget for C<prepare_layout> before the next layout pass of
its UI. Queuing a queued widget again changes nothing. Always bumps the
revision (L<Clay::UI::Revision>), so a renderer that skips unchanged
frames draws the next one. Returns the widget.

=head2 is_prepare_pending

	if ($widget->is_prepare_pending) { ... }

Returns 1 while the widget is queued, 0 otherwise.

=head1 SEE ALSO

L<Clay::UI/render>, L<Clay::UI::Revision>, L<Clay::Manual>.

=cut
