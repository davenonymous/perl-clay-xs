package Clay::UI::Interaction;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(blessed refaddr weaken looks_like_number);

use Clay::UI::Events::OnHoverStart;
use Clay::UI::Events::OnHoverStopped;
use Clay::UI::Events::OnPress;
use Clay::UI::Events::OnRelease;
use Clay::UI::Events::OnScroll;

our $VERSION = '0.01';

my %UPDATE_ARGS = map { $_ => 1 } qw(over down x y scrolled);

my $HOVERABLE = 'Clay::UI::Role::Interaction::Hoverable';
my $PRESSABLE = 'Clay::UI::Role::Interaction::Pressable';

class Clay::UI::Interaction :strict(params) {
	field $ui :param :weak;

	# Widgets keyed by refaddr; the values are weak references, so a freed
	# widget leaves an undef value behind and never counts.
	field %_hovered;
	field %_armed;
	field %_pressed;
	field @_under_pointer;
	field $_down   = 0;
	field $_firing = 0;

	method is_hovered ($widget) { return _holds(\%_hovered, $widget) }
	method is_armed   ($widget) { return _holds(\%_armed,   $widget) }
	method is_pressed ($widget) { return _holds(\%_pressed, $widget) }

	method under_pointer () {
		return [ grep { defined } @_under_pointer ];
	}

	# One pointer frame: the widgets under the pointer (topmost first),
	# whether the button is down, where the pointer is and which scroll
	# containers moved. Updates the state first, then fires the events.
	method update (%args) {
		die "Clay::UI::Interaction::update: called from one of its own listeners\n" if $_firing;
		die "Clay::UI::Interaction::update: its Clay::UI no longer exists\n" unless defined $ui;
		my $input  = $self->_parse_update(%args);
		my @events = $self->_apply($input);

		$_firing = 1;
		my $ok    = eval { _fire_all(@events); 1 };
		my $error = $@;
		$_firing = 0;
		die $error unless $ok;
		return;
	}

	method _parse_update (%args) {
		my @unknown = sort grep { !$UPDATE_ARGS{$_} } keys %args;
		_fail('unknown argument(s): ' . join(', ', @unknown)) if @unknown;
		_fail("'over' must be an arrayref of widgets") unless ref $args{over} eq 'ARRAY';
		_fail("'down' is required") unless exists $args{down};
		_fail("'down' must be a plain boolean value") if ref $args{down};
		for my $axis ('x', 'y') {
			next unless defined $args{$axis};
			_fail("'$axis' must be a finite number") unless _is_finite($args{$axis});
		}
		$self->_require_own($_, 'over') for @{ $args{over} };

		my $scrolled = $args{scrolled} // [];
		_fail("'scrolled' must be an arrayref of [widget, dx, dy]") unless ref $scrolled eq 'ARRAY';
		for my $entry (@$scrolled) {
			_fail("'scrolled' entries must be [widget, dx, dy]")
				unless ref $entry eq 'ARRAY' && @$entry == 3 && _is_finite($entry->[1]) && _is_finite($entry->[2]);
			$self->_require_own($entry->[0], 'scrolled');
		}
		return {
			over     => [ @{ $args{over} } ],
			down     => $args{down} ? 1 : 0,
			x        => $args{x} // 0,
			y        => $args{y} // 0,
			scrolled => $scrolled,
		};
	}

	method _require_own ($widget, $arg) {
		my $owner = blessed $widget && $widget->can('ui') ? $widget->ui : undef;
		_fail("'$arg' must hold widgets of this Clay::UI")
			unless defined $owner && refaddr($owner) == refaddr($ui);
		return;
	}

	# State changes for one frame; returns the events in firing order.
	method _apply ($input) {
		my $press_edge   = $input->{down} && !$_down;
		my $release_edge = !$input->{down} && $_down;
		$_down = $input->{down};

		my %over            = map { refaddr($_) => $_ } grep { $_->DOES($HOVERABLE) } @{ $input->{over} };
		my @over_pressables = grep { $_->DOES($PRESSABLE) } @{ $input->{over} };

		# Everything whose state may change: what is under the pointer now
		# plus what was hovered, armed or pressed before.
		my %candidates = (
			(map { refaddr($_) => $_ } _live(\%_hovered), _live(\%_armed), _live(\%_pressed)),
			%over,
		);
		my @candidates = values %candidates;
		my @pressables = grep { $_->DOES($PRESSABLE) } @candidates;

		my (@hover_stopped, @hover_started);
		for my $widget (@candidates) {
			my $is_over = exists $over{ refaddr $widget };
			if ($is_over && !$self->is_hovered($widget)) {
				_remember(\%_hovered, $widget);
				push @hover_started, $widget;
			} elsif (!$is_over && $self->is_hovered($widget)) {
				delete $_hovered{ refaddr $widget };
				push @hover_stopped, $widget;
			}
		}

		my ($press_origin, $release_origin);
		if ($press_edge) {
			_remember(\%_armed, $_) for @over_pressables;
			$press_origin = _event_origin(@over_pressables);
		} elsif ($release_edge) {
			$release_origin = _event_origin(grep { $self->is_armed($_) } @over_pressables);
			%_armed = ();
		}
		%_pressed = ();
		for my $widget (@pressables) {
			_remember(\%_pressed, $widget)
				if $input->{down} && $self->is_armed($widget) && exists $over{ refaddr $widget };
		}
		_prune(\%_hovered, \%_armed);

		@_under_pointer = @{ $input->{over} };
		weaken $_ for @_under_pointer;

		my ($x, $y) = @$input{qw(x y)};
		my %scroll_of = map { refaddr($_->[0]) => $_ } @{ $input->{scrolled} };
		return (
			(map { [ $_, Clay::UI::Events::OnHoverStopped->new ] } $ui->_in_tree_order(@hover_stopped)),
			(map { [ $_, Clay::UI::Events::OnHoverStart->new ] }   $ui->_in_tree_order(@hover_started)),
			(defined $press_origin   ? [ $press_origin,   Clay::UI::Events::OnPress->new(x => $x, y => $y) ]   : ()),
			(defined $release_origin ? [ $release_origin, Clay::UI::Events::OnRelease->new(x => $x, y => $y) ] : ()),
			(map {
				my (undef, $dx, $dy) = @{ $scroll_of{ refaddr $_ } };
				[ $_, Clay::UI::Events::OnScroll->new(delta_x => $dx, delta_y => $dy) ];
			} $ui->_in_tree_order(map { $_->[0] } @{ $input->{scrolled} })),
		);
	}

	# Called by Clay::UI while $top (and its subtree) leaves the tree: the
	# widgets in it stop being hovered (OnHoverStopped fires now), armed and
	# pressed, and are no longer under the pointer.
	method _subtree_detached ($top) {
		my @stopped = grep { _is_within($_, $top) } _live(\%_hovered);
		delete $_hovered{ refaddr $_ } for @stopped;
		for my $state (\%_armed, \%_pressed) {
			delete $state->{ refaddr $_ } for grep { _is_within($_, $top) } _live($state);
		}
		@_under_pointer = grep { defined && !_is_within($_, $top) } @_under_pointer;
		weaken $_ for @_under_pointer;

		_fire_all(map { [ $_, Clay::UI::Events::OnHoverStopped->new ] } $ui->_in_tree_order(@stopped));
		return;
	}

	# -----------------------------------------------------------------
	# Helpers.
	# -----------------------------------------------------------------

	sub _fail ($message) {
		die "Clay::UI::Interaction::update: $message\n";
	}

	sub _is_finite ($value) {
		return defined $value && !ref $value && looks_like_number($value)
			&& $value == $value && $value != 9**9**9 && $value != -9**9**9;
	}

	sub _holds ($state, $widget) {
		my $held = $state->{ refaddr $widget };
		return defined $held && refaddr($held) == refaddr($widget) ? 1 : 0;
	}

	sub _remember ($state, $widget) {
		$state->{ refaddr $widget } = $widget;
		weaken $state->{ refaddr $widget };
		return;
	}

	sub _live ($state) {
		return grep { defined } values %$state;
	}

	sub _prune (@states) {
		for my $state (@states) {
			delete $state->{$_} for grep { !defined $state->{$_} } keys %$state;
		}
		return;
	}

	sub _is_within ($widget, $top) {
		for (my $node = $widget; defined $node; $node = $node->parent) {
			return 1 if refaddr($node) == refaddr($top);
		}
		return 0;
	}

	# The widget a press or release belongs to: the first Pressable in
	# pointer-over order, replaced by each following Pressable that is its
	# descendant. The innermost widget of the topmost stack wins.
	sub _event_origin (@pressables) {
		my $origin = shift @pressables;
		for my $next (@pressables) {
			last unless _is_within($next->parent, $origin);
			$origin = $next;
		}
		return $origin;
	}

	# Fires every event even if a listener dies, then rethrows the first
	# exception. Clay::UI's focus changes use it too.
	sub _fire_all (@events) {
		my $first_error;
		for my $event (@events) {
			my ($widget, $object) = @$event;
			my $ok = eval { $widget->fire_event($object); 1 };
			$first_error //= ($@ || 'unknown listener error') unless $ok;
		}
		die $first_error if defined $first_error;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Interaction - pointer interaction state of a Clay::UI

=head1 SYNOPSIS

	my $interaction = $ui->interaction;

	$interaction->is_hovered($button);   # also $button->is_hovered
	$interaction->is_pressed($button);   # also $button->is_pressed
	my $widgets = $interaction->under_pointer;

	# Synthetic input, e.g. in a test or for keyboard activation:
	$interaction->update(over => [ $button, $panel ], down => 1, x => 40, y => 12);
	$interaction->update(over => [ $button, $panel ], down => 0, x => 40, y => 12);

=head1 DESCRIPTION

Every L<Clay::UI> owns one interaction tracker, returned by
C<< $ui->interaction >>. It holds which widgets are hovered, armed and
pressed, turns pointer input into state changes, and fires the pointer
events (see L<Clay::UI/POINTER EVENTS>). C<< $ui->render >> feeds it the
real pointer every frame; callers may feed it synthetic input in
between. Synthetic state lasts until the next C<render> reports where
the real pointer is.

The widget readers C<is_hovered> (L<Clay::UI::Role::Interaction::Hoverable>)
and C<is_pressed> (L<Clay::UI::Role::Interaction::Pressable>) and the
derived C<hovered> / C<pressed> states of
L<Clay::UI::Role::Style::HasStates> ask this object.

=head1 METHODS

=head2 update(%args)

One pointer frame:

=over 4

=item C<over> (required)

Arrayref of the widgets under the pointer, topmost first (Clay's
pointer-over order: the topmost floating root first, pre-order within
each root). Widgets must belong to this Clay::UI. Only Hoverables
become hovered and only Pressables can be pressed; the rest are
reported by C<under_pointer>.

=item C<down> (required)

Whether the pointer button is down. A change from up to down is a
press, a change from down to up a release.

=item C<x>, C<y>

The pointer position carried by C<OnPress> and C<OnRelease>; default 0.

=item C<scrolled>

Arrayref of C<[ $widget, $delta_x, $delta_y ]> for scroll containers
that moved; each gets an C<OnScroll>.

=back

All state changes happen first, then the events fire in this order:
C<OnHoverStopped>, C<OnHoverStart>, C<OnPress>, C<OnRelease>,
C<OnScroll>, each group in tree order. Every event fires even if a
listener dies; C<update> then rethrows the first error. Calling
C<update> from one of its own listeners dies.

A press arms every Pressable under the pointer and fires C<OnPress> at
the innermost Pressable of the topmost stack. A Pressable is pressed
while it is armed, under the pointer and the button is down. A release
fires C<OnRelease> at the armed Pressable under the pointer chosen the
same way, then disarms everything.

=head2 is_hovered($widget), is_armed($widget), is_pressed($widget)

1 or 0.

=head2 under_pointer

Arrayref of the widgets of the last update's C<over> that still exist
and are still in the tree, Hoverable or not.

=head1 REMOVED WIDGETS

When a subtree leaves the tree, its hovered widgets get C<OnHoverStopped>
at once, and its armed and pressed widgets are dropped without events,
like focus (C<OnBlur>) is.

=cut
