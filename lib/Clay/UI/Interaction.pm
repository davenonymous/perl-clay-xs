package Clay::UI::Interaction;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(blessed refaddr weaken);

use Clay::UI::Events::OnHoverStart;
use Clay::UI::Events::OnHoverStopped;
use Clay::UI::Events::OnPress;
use Clay::UI::Events::OnRelease;
use Clay::UI::Events::OnScroll;
use Clay::UI::Events::OnFocus;
use Clay::UI::Events::OnBlur;
use Clay::XS qw(CLAY_ATTACH_TO_NONE);
use Clay::UI::Revision qw(bump_revision);
use Clay::UI::_keys qw(camelize_keys);
use Clay::UI::_validate qw(is_finite_number);

our $VERSION = '0.01';

my %UPDATE_ARGS = map { $_ => 1 } qw(over down x y scrolled);

my $HOVERABLE   = 'Clay::UI::Role::Interaction::Hoverable';
my $PRESSABLE   = 'Clay::UI::Role::Interaction::Pressable';
my $FOCUSABLE   = 'Clay::UI::Role::Interaction::Focusable';
my $FOCUS_ORDER = 'Clay::UI::Role::Interaction::HasFocusOrder';
my $SCROLLABLE  = 'Clay::UI::Role::Layout::HasScroll';
my $FLOATING    = 'Clay::UI::Role::Layout::HasFloating';

class Clay::UI::Interaction :strict(params) {
	field $ui :param :weak;

	# Sorts widgets into the tree order of the last layout (Clay::UI
	# passes its frame registry's in_tree_order).
	field $tree_order :param;

	ADJUST {
		die "Clay::UI::Interaction: 'tree_order' must be a coderef\n" unless ref $tree_order eq 'CODE';
	}

	# Widgets keyed by refaddr; the values are weak references, so a freed
	# widget leaves an undef value behind and never counts.
	field %_hovered;
	field %_armed;
	field %_pressed;
	field @_under_pointer;
	field $_down   = 0;
	field $_firing = 0;
	field $_focused;

	# The widgets whose OnHoverStart / OnFocus has been delivered and not
	# yet followed by OnHoverStopped / OnBlur (weak, like the state sets).
	# A queued event is delivered only while it still matches the state,
	# so these keep every stop after its start, every blur after its focus.
	field %_hover_announced;
	field $_focus_announced;

	# Subtrees release_subtrees is detaching: they no longer belong to the
	# UI, so no listener can hover, press or focus a widget in them.
	field @_leaving;

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
		_require_ui($ui, 'update');
		my $input  = $self->_parse_update(%args);
		my @events = $self->_apply($input);

		$_firing = 1;
		my $ok    = eval { $self->_fire_due(@events); 1 };
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
			_fail("'$axis' must be a finite number") unless is_finite_number($args{$axis});
		}
		$self->_require_own($_, 'over') for @{ $args{over} };

		my $scrolled = $args{scrolled} // [];
		_fail("'scrolled' must be an arrayref of [widget, dx, dy]") unless ref $scrolled eq 'ARRAY';
		my %scrolled_seen;
		for my $entry (@$scrolled) {
			_fail("'scrolled' entries must be [widget, dx, dy]")
				unless ref $entry eq 'ARRAY' && @$entry == 3 && is_finite_number($entry->[1]) && is_finite_number($entry->[2]);
			$self->_require_own($entry->[0], 'scrolled');
			_fail("'scrolled' must hold scroll containers (widgets composing $SCROLLABLE)")
				unless $entry->[0]->DOES($SCROLLABLE);
			_fail("'scrolled' lists the same widget twice") if $scrolled_seen{ refaddr $entry->[0] }++;
		}
		return {
			over     => [ @{ $args{over} } ],
			down     => $args{down} ? 1 : 0,
			x        => $args{x} // 0,
			y        => $args{y} // 0,
			scrolled => $scrolled,
		};
	}

	# True for a widget of this UI's tree that is not being detached.
	method _owns ($widget) {
		my $owner = blessed $widget && $widget->can('ui') ? $widget->ui : undef;
		return 0 unless defined $owner && refaddr($owner) == refaddr($ui);
		return !grep { _is_within($widget, $_) } @_leaving;
	}

	method _require_own ($widget, $arg) {
		_fail("'$arg' must hold widgets of this Clay::UI") unless $self->_owns($widget);
		return;
	}

	# State changes for one frame; returns the events in firing order.
	method _apply ($input) {
		my $states_before = $self->_state_signature;
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
		bump_revision() if $self->_state_signature ne $states_before;

		my ($x, $y) = @$input{qw(x y)};
		my %scroll_of = map { refaddr($_->[0]) => $_ } @{ $input->{scrolled} };
		return (
			(map { $self->_hover_stopped_event($_) } $tree_order->(@hover_stopped)),
			(map { $self->_hover_started_event($_) } $tree_order->(@hover_started)),
			(defined $press_origin   ? $self->_owned_event($press_origin,   Clay::UI::Events::OnPress->new(x => $x, y => $y))   : ()),
			(defined $release_origin ? $self->_owned_event($release_origin, Clay::UI::Events::OnRelease->new(x => $x, y => $y)) : ()),
			(map {
				my (undef, $dx, $dy) = @{ $scroll_of{ refaddr $_ } };
				$self->_owned_event($_, Clay::UI::Events::OnScroll->new(delta_x => $dx, delta_y => $dy));
			} $tree_order->(map { $_->[0] } @{ $input->{scrolled} })),
		);
	}

	# -----------------------------------------------------------------
	# Queued events. Each is [ $widget, $event, $claim ]: $claim runs right
	# before delivery and returns false when an earlier listener of the
	# same dispatch has made the event stale (the widget left the tree, its
	# hover or focus changed again, a nested call already announced it); it
	# records what a delivered event announced.
	# -----------------------------------------------------------------

	method _hover_started_event ($widget) {
		return [ $widget, Clay::UI::Events::OnHoverStart->new, sub {
			return 0 unless $self->is_hovered($widget) && !_holds(\%_hover_announced, $widget);
			_remember(\%_hover_announced, $widget);
			return 1;
		} ];
	}

	method _hover_stopped_event ($widget) {
		return [ $widget, Clay::UI::Events::OnHoverStopped->new, sub {
			return 0 if $self->is_hovered($widget) || !_holds(\%_hover_announced, $widget);
			delete $_hover_announced{ refaddr $widget };
			return 1;
		} ];
	}

	method _focus_event ($widget) {
		return [ $widget, Clay::UI::Events::OnFocus->new, sub {
			return 0 unless $self->is_focused($widget);
			return 0 if defined $_focus_announced && refaddr($_focus_announced) == refaddr($widget);
			$_focus_announced = $widget;
			weaken $_focus_announced;
			return 1;
		} ];
	}

	method _blur_event ($widget) {
		return [ $widget, Clay::UI::Events::OnBlur->new, sub {
			return 0 if $self->is_focused($widget);
			return 0 unless defined $_focus_announced && refaddr($_focus_announced) == refaddr($widget);
			undef $_focus_announced;
			return 1;
		} ];
	}

	# Press, release and scroll events: due while the widget is in the tree.
	method _owned_event ($widget, $event) {
		return [ $widget, $event, sub { $self->_owns($widget) } ];
	}

	# Delivers every event that is still due, even if a listener dies, then
	# rethrows the first exception.
	method _fire_due (@events) {
		my $first_error;
		for my $entry (@events) {
			my ($widget, $event, $claim) = @$entry;
			my $ok = eval { $widget->fire_event($event) if $claim->(); 1 };
			$first_error //= ($@ || 'unknown listener error') unless $ok;
		}
		_prune(\%_hover_announced);
		die $first_error if defined $first_error;
		return;
	}

	# Called by an Element while the subtrees below @tops leave the tree:
	# the widgets in them stop being hovered, armed and pressed and are no
	# longer under the pointer, and focus inside them is released. Then the
	# hovered ones get OnHoverStopped and the focused one OnBlur. Until this
	# returns the subtrees count as gone already (see _owns).
	method release_subtrees (@tops) {
		my $leaving = sub ($widget) { grep { _is_within($widget, $_) } @tops };
		my $states_before = $self->_state_signature;
		my @stopped = grep { $leaving->($_) } _live(\%_hovered);
		delete $_hovered{ refaddr $_ } for @stopped;
		for my $state (\%_armed, \%_pressed) {
			delete $state->{ refaddr $_ } for grep { $leaving->($_) } _live($state);
		}
		@_under_pointer = grep { defined && !$leaving->($_) } @_under_pointer;
		weaken $_ for @_under_pointer;

		my @events = map { $self->_hover_stopped_event($_) } $tree_order->(@stopped);
		if (defined $_focused && $leaving->($_focused)) {
			push @events, $self->_blur_event($_focused);
			undef $_focused;
		}
		bump_revision() if $self->_state_signature ne $states_before;

		push @_leaving, @tops;
		my $ok    = eval { $self->_fire_due(@events); 1 };
		my $error = $@;
		splice @_leaving, -@tops if @tops;
		die $error unless $ok;
		return;
	}

	# Who is hovered, armed, pressed and focused, as a string that changes
	# exactly when one of those does.
	method _state_signature () {
		my $focused = defined $_focused ? refaddr $_focused : '';
		return join ';', $focused,
			map { join ',', sort { $a <=> $b } map { refaddr $_ } _live($_) } \%_hovered, \%_armed, \%_pressed;
	}

	# -----------------------------------------------------------------
	# Focus. Moves only on request, walking the live tree: it must work
	# before the first render and right after the tree changed, while
	# pointer events follow the last frame, which they were hit-tested
	# against.
	# -----------------------------------------------------------------

	method get_focused_widget () {
		return $_focused;
	}

	method is_focused ($widget) {
		return defined $_focused && refaddr($_focused) == refaddr($widget) ? 1 : 0;
	}

	# undef blurs. Focusing the focused widget again is a no-op.
	method set_focused_widget ($widget) {
		_require_ui($ui, 'set_focused_widget');
		return if !defined $_focused && !defined $widget;
		return if defined $widget && $self->is_focused($widget);
		$self->_check_focus_target($widget) if defined $widget;

		# The focused widget changes before any listener runs; a dying
		# OnBlur listener still lets OnFocus fire, and an OnBlur listener
		# that moves focus again makes this OnFocus stale.
		my $previous = $_focused;
		$_focused = $widget;
		weaken $_focused if defined $_focused;
		bump_revision();

		$self->_fire_due(
			(defined $previous ? $self->_blur_event($previous) : ()),
			(defined $widget   ? $self->_focus_event($widget) : ()),
		);
		return;
	}

	method focus_next () {
		$self->_move_focus(1);
		return;
	}

	method focus_previous () {
		$self->_move_focus(-1);
		return;
	}

	# The default order, ignoring every HasFocusOrder: the next / previous
	# Focusable after the focused widget in depth-first pre-order that can
	# focus now, wrapping around.
	method default_next_focus () {
		_require_ui($ui, 'default_next_focus');
		return $self->_step_focus(1);
	}

	method default_previous_focus () {
		_require_ui($ui, 'default_previous_focus');
		return $self->_step_focus(-1);
	}

	method _check_focus_target ($widget) {
		my $fail = sub ($message) { die "Clay::UI::Interaction::set_focused_widget: target $message\n" };
		$fail->('must be a blessed widget') unless blessed $widget;
		$fail->("must consume $FOCUSABLE") unless $widget->DOES($FOCUSABLE);
		$fail->('does not belong to this Clay::UI') unless $self->_owns($widget);
		$fail->('is not currently focusable (can_focus returned false)') unless $widget->can_focus;
		return;
	}

	method _move_focus ($step) {
		_require_ui($ui, $step > 0 ? 'focus_next' : 'focus_previous');
		my $order  = $self->_focus_order_owner;
		my $target = defined $order
			? $self->_validate_focus_order($order, $step > 0 ? $order->get_next_focus : $order->get_previous_focus)
			: $self->_step_focus($step);
		$self->set_focused_widget($target) if defined $target;
		return;
	}

	# The nearest HasFocusOrder ancestor of the focused widget (including
	# itself); with nothing focused, the root if it composes HasFocusOrder.
	method _focus_order_owner () {
		my $root = $ui->root;
		return $root->DOES($FOCUS_ORDER) ? $root : undef unless defined $_focused;
		for (my $node = $_focused; defined $node; $node = $node->parent) {
			return $node if $node->DOES($FOCUS_ORDER);
		}
		return undef;
	}

	# undef means "no change", as does a focusable widget of this UI that
	# is disabled right now; anything else a HasFocusOrder returns is a bug
	# in that class.
	method _validate_focus_order ($order, $widget) {
		return undef unless defined $widget;
		my $fail = sub ($message) { die "Clay::UI::Interaction: " . ref($order) . " returned $message\n" };
		$fail->('a non-widget from its focus order') unless blessed $widget;
		$fail->(ref($widget) . ", which is not $FOCUSABLE") unless $widget->DOES($FOCUSABLE);
		$fail->(ref($widget) . ', which is not part of this Clay::UI') unless $self->_owns($widget);
		return $widget->can_focus ? $widget : undef;
	}

	# The next Focusable after the focused widget in pre-order ($step 1) or
	# before it ($step -1) that can focus now, wrapping around. The focused
	# widget itself may have been disabled while focused.
	method _step_focus ($step) {
		my @all = _focusables_in_order($ui->root);
		return undef unless @all;
		my $start;
		if (defined $_focused) {
			($start) = grep { refaddr($all[$_]) == refaddr($_focused) } 0 .. $#all;
		}
		$start //= $step > 0 ? -1 : scalar @all;
		for my $offset (1 .. scalar @all) {
			my $candidate = $all[ ($start + $step * $offset) % @all ];
			return $candidate if $candidate->can_focus;
		}
		return undef;
	}

	# -----------------------------------------------------------------
	# Helpers.
	# -----------------------------------------------------------------

	sub _fail ($message) {
		die "Clay::UI::Interaction::update: $message\n";
	}

	sub _require_ui ($ui, $method) {
		die "Clay::UI::Interaction::$method: its Clay::UI no longer exists\n" unless defined $ui;
		return;
	}

	# Every Focusable in depth-first pre-order, focusable right now or not.
	sub _focusables_in_order ($root) {
		my @focusables;
		my @stack = ($root);
		while (@stack) {
			my $node = shift @stack;
			push @focusables, $node if $node->DOES($FOCUSABLE);
			unshift @stack, @{ $node->children } if $node->DOES('Clay::UI::Role::Core::Element');
		}
		return @focusables;
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

	# The widget a press or release belongs to. Pointer-over order lists
	# the topmost Clay root first and each root in pre-order, so a later
	# Pressable in the first one's root is its descendant or drawn over
	# it: the last one wins. Ancestors are skipped, as synthetic input may
	# list them after their descendants.
	sub _event_origin (@pressables) {
		my $origin = shift @pressables;
		return undef unless defined $origin;
		my $root_addr = refaddr(_floating_root($origin)) // 0;
		for my $next (@pressables) {
			next if _is_within($origin, $next);
			next unless (refaddr(_floating_root($next)) // 0) == $root_addr;
			$origin = $next;
		}
		return $origin;
	}

	# The widget whose Clay root $widget is laid out in: its nearest
	# floating ancestor (itself included), or undef for the main root.
	sub _floating_root ($widget) {
		for (my $node = $widget; defined $node; $node = $node->parent) {
			return $node if _is_floating($node);
		}
		return undef;
	}

	sub _is_floating ($widget) {
		return 0 unless $widget->DOES($FLOATING);
		my $floating = $widget->floating;
		return defined $floating && (camelize_keys($floating)->{attachTo} // CLAY_ATTACH_TO_NONE) != CLAY_ATTACH_TO_NONE;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Interaction - hover, press and focus state of a Clay::UI

=head1 SYNOPSIS

	my $interaction = $ui->interaction;

	$interaction->is_hovered($button);   # also $button->is_hovered
	$interaction->is_pressed($button);   # also $button->is_pressed
	my $widgets = $interaction->under_pointer;

	# Synthetic input, e.g. in a test or for keyboard activation:
	$interaction->update(over => [ $button, $panel ], down => 1, x => 40, y => 12);
	$interaction->update(over => [ $button, $panel ], down => 0, x => 40, y => 12);

	# Focus, e.g. from a Tab key handler:
	$interaction->set_focused_widget($name_input);
	$interaction->focus_next;
	my $focused = $interaction->get_focused_widget;

=head1 DESCRIPTION

Every L<Clay::UI> owns one interaction tracker, returned by
C<< $ui->interaction >>. It holds which widgets are hovered, armed and
pressed, turns pointer input into state changes, and fires the pointer
events (see L<Clay::UI/POINTER EVENTS>). C<< $ui->render >> feeds it the
real pointer every frame; callers may feed it synthetic input in
between. Synthetic state lasts until the next C<render> reports where
the real pointer is. It also holds which widget has focus and moves it
on request (see L</FOCUS>).

The widget readers C<is_hovered> (L<Clay::UI::Role::Interaction::Hoverable>),
C<is_pressed> (L<Clay::UI::Role::Interaction::Pressable>) and
C<is_focused> (L<Clay::UI::Role::Interaction::Focusable>) and the
derived C<hovered> / C<pressed> / C<focused> states of
L<Clay::UI::Role::Style::HasStates> ask this object.

Whenever the hovered, armed, pressed or focused widgets change, the
tracker bumps the process-wide revision (L<Clay::UI::Revision>), since
widgets may style themselves by those states.

=head1 METHODS

=head2 update(%args)

One pointer frame:

=over 4

=item C<over> (required)

Arrayref of the widgets under the pointer in Clay's pointer-over order:
the topmost floating root first, pre-order within each root, so within a
root a later widget is a descendant of an earlier one or drawn over it.
Widgets must belong to this Clay::UI. Only Hoverables
become hovered and only Pressables can be pressed; the rest are
reported by C<under_pointer>.

=item C<down> (required)

Whether the pointer button is down. A change from up to down is a
press, a change from down to up a release.

=item C<x>, C<y>

The pointer position carried by C<OnPress> and C<OnRelease>; default 0.

=item C<scrolled>

Arrayref of C<[ $widget, $delta_x, $delta_y ]> for scroll containers
(widgets composing L<Clay::UI::Role::Layout::HasScroll>) that moved,
each at most once; each gets an C<OnScroll>.

=back

All state changes happen first, then the events fire in this order:
C<OnHoverStopped>, C<OnHoverStart>, C<OnPress>, C<OnRelease>,
C<OnScroll>, each group in tree order (widgets the last layout did not
reach come after the others, in the order of the live tree). Every
event fires even if a listener dies; C<update> then rethrows the first
error. Calling C<update> from one of its own listeners dies.

An event that an earlier listener of the same update made stale is
dropped instead: C<OnPress>, C<OnRelease> and C<OnScroll> for a widget
that has left the tree, C<OnHoverStart> for a widget that is no longer
hovered. A widget gets C<OnHoverStopped> only after its
C<OnHoverStart>, and C<OnBlur> only after its C<OnFocus>.

A press arms every Pressable under the pointer and fires C<OnPress> at
the one drawn on top: the last Pressable of C<over> that lies in the
same root as the first one, skipping that one's ancestors. Nested
Pressables give the innermost one; overlapping siblings, such as the
children of a C<CLAY_BACK_TO_FRONT> container, give the later one; a
Pressable in a floating root beats everything below that root. A
Pressable is pressed
while it is armed, under the pointer and the button is down. A release
fires C<OnRelease> at the armed Pressable under the pointer chosen the
same way, then disarms everything.

=head2 is_hovered($widget), is_armed($widget), is_pressed($widget)

1 or 0.

=head2 under_pointer

Arrayref of the widgets of the last update's C<over> that still exist
and are still in the tree, Hoverable or not.

=head1 FOCUS

Focus changes only through C<set_focused_widget>, C<focus_next>,
C<focus_previous> and the removal of a subtree holding the focused
widget (which blurs it). C<render> never changes focus. Event listeners,
including pointer listeners running inside C<update>, may move focus.

Focus follows the widget tree as it is now, while pointer events follow
the tree of the last layout: focus must work before the first C<render>
and right after the tree changed, whereas the pointer was hit-tested
against the last layout.

The focus methods die when the Clay::UI that owns this object is gone.

=head2 get_focused_widget

The widget holding focus, or C<undef> if none is focused (or the
focused widget has been garbage-collected). The reference is held
weakly.

=head2 is_focused($widget)

1 or 0.

=head2 set_focused_widget($widget)

Sets focus to C<$widget>; C<undef> clears focus (blur). Validates
loudly, before anything changes: dies if C<$widget> is not blessed, does
not consume L<Clay::UI::Role::Interaction::Focusable>, belongs to a
different Clay::UI, or its C<can_focus> returns false.

Then the focus moves - the C<focused> state moves from the previous
widget to the new one - and L<Clay::UI::Events::OnBlur> fires on the
previously focused widget (if any) and L<Clay::UI::Events::OnFocus> on
the new one (if any). Both events fire even if the first listener dies;
the first error is rethrown afterwards, with focus already changed. An
C<OnBlur> listener may move focus again; the C<OnFocus> of this call is
then dropped, since its widget no longer has focus.
Focusing the already-focused widget is a no-op (no events fire).

=head2 focus_next, focus_previous

Move focus to the next / previous focusable widget.

The default order is the depth-first pre-order of the tree, skipping
widgets whose C<can_focus> is false, wrapping from end to beginning
(and vice versa). With no focused widget, C<focus_next> focuses the
first widget of the chain and C<focus_previous> the last. The focused
widget itself does not have to be focusable any more: after
C<< $focused->can_focus(0) >>, C<focus_next> moves on from its
position.

If the focused widget or one of its ancestors composes
L<Clay::UI::Role::Interaction::HasFocusOrder>, the nearest such widget
decides instead: its C<get_next_focus> / C<get_previous_focus> is
called. With no focused widget, the root decides if it composes
HasFocusOrder. The result must be C<undef> (focus does not change), a
Focusable widget of this UI (focused, or no change if its C<can_focus>
is false right now), or else the call dies naming the HasFocusOrder
class and what was wrong with the result.

=head2 default_next_focus, default_previous_focus

The widget the default order would focus next / previously, ignoring
every HasFocusOrder; C<undef> if no widget can focus. Nothing changes.
L<Clay::UI::Role::Interaction::HasFocusOrder> uses them to fall back to
the default order.

=head1 REMOVED WIDGETS

When a subtree leaves the tree, its hovered widgets stop being hovered,
its armed and pressed widgets are dropped and focus inside it is
released. Then the hovered ones get C<OnHoverStopped> and the focused
one gets C<OnBlur>, all at once, during the removal.

While these events fire, the leaving subtrees already count as gone:
a listener cannot hover, press or focus a widget inside them
(C<set_focused_widget> and C<update> die as for a widget of another
UI).

=head2 release_subtrees(@tops)

Does the above for every widget of C<@tops> and everything below them,
and bumps the revision if any state changed. The child-mutation methods
of L<Clay::UI::Role::Core::Element> call it once per change, with all
removed children, while they are still attached, so the events bubble
through their old ancestors; a widget class that detaches children some
other way must call it too. Every event fires even if a listener dies;
the first error is rethrown.

=head1 CONSTRUCTION

L<Clay::UI> builds its tracker with C<ui> (the UI, held weakly) and
C<tree_order>, a coderef that sorts widgets into the tree order of the
last layout. Nothing else needs to construct one.

=cut
