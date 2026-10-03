package Clay::UI::Role::Core::Preparable;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(refaddr weaken);

use Clay::UI::Revision qw(bump_revision);

our $VERSION = '0.01';

# Process-wide, like the revision: refaddr => the widget (weak), for every
# widget whose prepare_layout is due before its UI's next layout pass.
my %_pending;

# Calls prepare_layout on the pending widgets that belong to $ui, until
# none is left (a preparation may request another one). Widgets of other
# UIs, or of none yet, stay pending. Dies when preparations keep
# requesting new ones.
use constant _MAX_ROUNDS => 100;

sub _prepare_pending ($ui) {
	for my $round (1 .. _MAX_ROUNDS) {
		my @due = grep { _belongs_to($_, $ui) } map { $_pending{$_} } sort keys %_pending;
		return unless @due;
		delete $_pending{ refaddr $_ } for @due;
		$_->prepare_layout for @due;
	}
	die "Clay::UI: widgets kept requesting preparation; " . _MAX_ROUNDS . " rounds of prepare_layout did not settle\n";
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

Clay::UI::Role::Core::Preparable - let a widget update its subtree right before the layout

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Box;
	use Clay::UI::Role::Core::Preparable;

	class My::List :strict(params) :does(Clay::UI::Box) :does(Clay::UI::Role::Core::Preparable) {
		field @items;

		method add_item ($item) {
			push @items, $item;
			$self->request_prepare;    # cheap: the children are built once per frame
			return $self;
		}

		method prepare_layout () {
			$self->clear_children;
			$self->add_child( map { My::Label->new(text => $_) } @items );
			return;
		}
	}

=head1 DESCRIPTION

A widget whose children follow from state of its own (a list of items,
the rows of a table) would have to rebuild them on every change of that
state. With this role it asks to be prepared instead, and rebuilds them
once, right before the next frame is laid out, however many changes came
before.

C<request_prepare> queues the widget; L<Clay::UI/render> calls its
C<prepare_layout> after the frame's pointer events and before the layout
pass, so the changes the listeners of those events made are included.
Only widgets that belong to the rendering UI are prepared; a widget that
is not part of a UI yet stays queued until it is. A preparation may
change anything (no Clay element is open), and may request another
preparation, of itself or of other widgets; C<render> keeps preparing
until no request is left, and dies after 100 rounds.

The queue holds widgets weakly: a widget freed while it is queued is
simply forgotten.

=head1 METHODS

=head2 prepare_layout

Required. Brings the widget (usually its children) up to date. Called
by C<render> with no arguments; the return value is ignored. An
exception from it makes C<render> die with it, after the layout pass
has run (like an exception from an event listener); the widget is no
longer queued.

=head2 request_prepare

	$widget->request_prepare;

Queues the widget for C<prepare_layout> before the next layout pass of
its UI (queuing it twice queues it once) and bumps the revision
(L<Clay::UI::Revision>), so a renderer that skips unchanged frames draws
the next one. Returns the widget.

=head2 is_prepare_pending

True while the widget is queued.

=head1 SEE ALSO

L<Clay::UI>, L<Clay::UI::Revision>.

=cut
