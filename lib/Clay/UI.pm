package Clay::UI;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Scalar::Util qw(blessed refaddr weaken looks_like_number);

use Clay::XS qw(
	Clay_Initialize
	Clay_MinMemorySize
	Clay_SetCurrentContext
	Clay_SetLayoutDimensions
	Clay_SetMeasureTextFunction
	Clay_ResetMeasureTextCache
	Clay_SetPointerState
	Clay_GetPointerState
	Clay_GetPointerOverIds
	Clay_UpdateScrollContainers
	Clay_GetScrollOffset
	Clay_GetScrollContainerData
	Clay_BeginLayout
	Clay_EndLayout
	Clay_GetElementId
	Clay__OpenElementWithId
	Clay__ConfigureOpenElement
	Clay__CloseElement
	Clay__OpenTextElement
	CLAY_POINTER_DATA_PRESSED
	CLAY_POINTER_DATA_PRESSED_THIS_FRAME
);
use Clay::UI::_keys qw(camelize_keys);
use Clay::UI::Interaction;

use Clay::UI::Events::OnFocus;
use Clay::UI::Events::OnBlur;

our $VERSION = '0.02';

my %RENDER_ARGS  = map { $_ => 1 } qw(pointer_state delta_time scroll_delta enable_drag_scrolling);
my %POINTER_KEYS = map { $_ => 1 } qw(x y down);
my %VECTOR_KEYS  = map { $_ => 1 } qw(x y);

class Clay::UI :strict(params) {
	field $root   :param :reader;
	field $width  :param;
	field $height :param;

	field $memory_size    :param = undef;
	field $error_handler  :param = undef;
	field $measure_text   :param = undef;

	field $_ctx;
	field $_focused   = undef;
	field $_rendering = 0;

	# Registries of the last completed frame (values are weak references):
	# render-command userData -> widget, Clay element id -> widget, widget
	# -> position in the walk (pre-order), and the scroll containers
	# walked. The _pending_* versions are filled during the walk.
	field $_widget_by_refaddr = {};
	field $_widget_by_id      = {};
	field $_walk_order        = {};
	field $_scroll_widgets    = [];
	field $_pending_by_refaddr;
	field $_pending_by_id;
	field $_pending_order;
	field $_pending_scroll;

	# The last pointer state passed to render, and the tracker that owns
	# hover, armed and pressed state.
	field $_last_pointer;
	field $interaction :reader;

	ADJUST {
		unless (blessed $root
			&& ($root->DOES('Clay::UI::Role::Core::Element')
			 || $root->DOES('Clay::UI::Role::Core::TextNode'))) {
			die "Clay::UI: 'root' must be a widget consuming Clay::UI::Role::Core::Element or TextNode";
		}
		die "Clay::UI: 'root' must not have a parent; the root is the top of its widget tree"
			if $root->_was_parented;
		unless (looks_like_number($width) && $width > 0
			&& looks_like_number($height) && $height > 0) {
			die "Clay::UI: 'width' and 'height' must be positive numbers";
		}

		my $min_memory = Clay_MinMemorySize();
		$memory_size //= $min_memory;
		unless (looks_like_number($memory_size) && $memory_size == int($memory_size)
			&& $memory_size >= $min_memory) {
			die "Clay::UI: 'memory_size' must be an integer >= Clay_MinMemorySize() ($min_memory)";
		}
		$error_handler //= sub ($err, $userdata) {
			die "Clay error: $err->{errorText}\n";
		};
		$measure_text //= sub ($text, $config, $userdata) {
			my $fs = $config->{fontSize} || 16;
			return { width => length($text) * $fs, height => $fs };
		};

		unless (ref $error_handler eq 'CODE') {
			die "Clay::UI: 'error_handler' must be a coderef";
		}
		unless (ref $measure_text eq 'CODE') {
			die "Clay::UI: 'measure_text' must be a coderef";
		}

		$_ctx = Clay_Initialize(
			$memory_size,
			{ width => $width, height => $height },
			$error_handler,
		);
		Clay_SetCurrentContext($_ctx);
		Clay_SetMeasureTextFunction($measure_text);
		# Clay's pointer state starts zeroed, which reads as "pressed this
		# frame"; settle it so the first real pointer frame is no click.
		Clay_SetPointerState({ x => -1, y => -1 }, 0);

		$interaction = Clay::UI::Interaction->new(ui => $self);
		$root->_set_ui_controller($self);
	}

	# Read with no args; write with one arg, propagating to Clay.
	method width (@v) {
		if (@v) {
			my ($new) = @v;
			die "Clay::UI: width must be a positive number"
				unless looks_like_number($new) && $new > 0;
			$width = $new;
			Clay_SetCurrentContext($_ctx);
			Clay_SetLayoutDimensions({ width => $width, height => $height });
		}
		return $width;
	}

	method height (@v) {
		if (@v) {
			my ($new) = @v;
			die "Clay::UI: height must be a positive number"
				unless looks_like_number($new) && $new > 0;
			$height = $new;
			Clay_SetCurrentContext($_ctx);
			Clay_SetLayoutDimensions({ width => $width, height => $height });
		}
		return $height;
	}

	method measure_text (@v) {
		if (@v) {
			my ($new) = @v;
			die "Clay::UI: measure_text must be a coderef"
				unless ref $new eq 'CODE';
			$measure_text = $new;
			Clay_SetCurrentContext($_ctx);
			Clay_SetMeasureTextFunction($measure_text);
			Clay_ResetMeasureTextCache();
		}
		return $measure_text;
	}

	# Parses render's named arguments into a frame description; dies on
	# anything it does not recognise.
	sub _parse_render_args (%args) {
		my @unknown = grep { !$RENDER_ARGS{$_} } keys %args;
		die "Clay::UI::render: unknown argument(s): @{[ sort @unknown ]}" if @unknown;

		my $pointer = $args{pointer_state};
		if (defined $pointer) {
			die "Clay::UI::render: 'pointer_state' must be a hashref { x => ..., y => ..., down => ... }"
				unless ref $pointer eq 'HASH';
			my @bad = grep { !$POINTER_KEYS{$_} } keys %$pointer;
			die "Clay::UI::render: unknown pointer_state key(s): @{[ sort @bad ]}" if @bad;
			for my $axis (qw(x y)) {
				die "Clay::UI::render: pointer_state '$axis' must be a number"
					unless looks_like_number($pointer->{$axis});
			}
			$pointer = { x => $pointer->{x}, y => $pointer->{y}, down => $pointer->{down} ? 1 : 0 };
		}

		my $delta_time = $args{delta_time} // 0;
		die "Clay::UI::render: 'delta_time' must be a finite number >= 0"
			unless looks_like_number($delta_time) && $delta_time >= 0 && $delta_time < 9**9**9;

		my $scroll_delta = $args{scroll_delta} // [0, 0];
		if (ref $scroll_delta eq 'HASH') {
			my @bad = grep { !$VECTOR_KEYS{$_} } keys %$scroll_delta;
			die "Clay::UI::render: unknown scroll_delta key(s): @{[ sort @bad ]}" if @bad;
			$scroll_delta = [ @{$scroll_delta}{qw(x y)} ];
		}
		die "Clay::UI::render: 'scroll_delta' must be { x => ..., y => ... } or [x, y]"
			unless ref $scroll_delta eq 'ARRAY' && @$scroll_delta == 2
				&& !grep { !looks_like_number($_) } @$scroll_delta;

		my $drag = $args{enable_drag_scrolling} // 0;
		die "Clay::UI::render: 'enable_drag_scrolling' must be a plain boolean value"
			if ref $drag;

		return {
			pointer      => $pointer,
			delta_time   => $delta_time,
			scroll_delta => { x => $scroll_delta->[0], y => $scroll_delta->[1] },
			drag         => $drag ? 1 : 0,
		};
	}

	method render (%args) {
		my $frame = _parse_render_args(%args);
		die "Clay::UI::render: called while this Clay::UI is already rendering"
			if $_rendering;

		$_rendering = 1;
		my $commands;
		my $ok = eval { $commands = $self->_render_frame($frame); 1 };
		my $error = $@;
		$_rendering = 0;
		die $error unless $ok;
		return $commands;
	}

	# One frame: pointer and scroll input, event dispatch (plain Perl, with
	# no element open, so listeners may change the tree), then the layout
	# pass.
	#
	# Clay_UpdateScrollContainers clears every scroll container's "declared
	# this frame" mark, and the next update drops the scroll state of any
	# container still unmarked. So once it has run, the layout pass runs
	# too, even when a listener died; its commands are then discarded and
	# the listener's error is rethrown.
	method _render_frame ($frame) {
		Clay_SetCurrentContext($_ctx);

		my $pointer = $frame->{pointer} // $_last_pointer;
		$_last_pointer = $pointer;
		if (defined $pointer) {
			Clay_SetPointerState({ x => $pointer->{x}, y => $pointer->{y} }, $pointer->{down});
		}
		my @under_pointer = $self->_widgets_under_pointer;
		my $pointer_data  = Clay_GetPointerState();

		my %scroll_before = $self->_scroll_positions;
		Clay_UpdateScrollContainers($frame->{drag}, $frame->{scroll_delta}, $frame->{delta_time});

		my ($dispatch_error, $layout_error, $commands);
		{
			local $@;
			eval {
				my $state = $pointer_data->{state};
				$interaction->update(
					over     => \@under_pointer,
					down     => $state == CLAY_POINTER_DATA_PRESSED || $state == CLAY_POINTER_DATA_PRESSED_THIS_FRAME,
					x        => $pointer_data->{position}{x},
					y        => $pointer_data->{position}{y},
					scrolled => [ $self->_scroll_changes(\%scroll_before) ],
				);
				1;
			} or $dispatch_error = $@ || 'unknown listener error';
		}
		{
			local $@;
			eval { $commands = $self->_layout_frame($frame->{delta_time}); 1 }
				or $layout_error = $@ || 'unknown layout error';
		}
		if (defined $dispatch_error) {
			$dispatch_error .= "(the layout pass also failed: $layout_error)"
				if defined $layout_error && !ref $dispatch_error;
			die $dispatch_error;
		}
		die $layout_error if defined $layout_error;
		return $commands;
	}

	method _layout_frame ($delta_time) {
		# Stage registry writes; commit them only after a complete frame so a
		# failed frame leaves the registries of the last good one in place.
		my %staged_by_refaddr;
		my %staged_by_id;
		my %staged_order;
		my @staged_scroll;
		$_pending_by_refaddr = \%staged_by_refaddr;
		$_pending_by_id      = \%staged_by_id;
		$_pending_order      = \%staged_order;
		$_pending_scroll     = \@staged_scroll;

		# A listener may have used another Clay::UI, which switches Clay's
		# current context.
		Clay_SetCurrentContext($_ctx);
		my ($walk_error, $end_error, $commands);
		Clay_BeginLayout();
		{
			local $@;
			eval { $self->_walk($root, '', []); 1 } or $walk_error = $@ || 'unknown walker error';
		}
		{
			local $@;
			eval { $commands = Clay_EndLayout($delta_time); 1 }
				or $end_error = $@ || 'unknown Clay_EndLayout error';
		}
		$_pending_by_refaddr = undef;
		$_pending_by_id      = undef;
		$_pending_order      = undef;
		$_pending_scroll     = undef;

		if (defined $walk_error) {
			$walk_error .= "(Clay_EndLayout also failed: $end_error)"
				if defined $end_error && !ref $walk_error;
			die $walk_error;
		}
		die $end_error if defined $end_error;

		$_widget_by_refaddr = \%staged_by_refaddr;
		$_widget_by_id      = \%staged_by_id;
		$_walk_order        = \%staged_order;
		$_scroll_widgets    = \@staged_scroll;
		return $commands;
	}

	# ---------------------------------------------------------------------
	# Pointer and scroll events.
	# ---------------------------------------------------------------------

	method _belongs_here ($widget) {
		my $ui = $widget->ui;
		return defined $ui && refaddr($ui) == refaddr($self);
	}

	# The widgets of this UI under the pointer, in Clay's pointer-over order:
	# the topmost floating root first, pre-order within each root. Clay adds
	# an element to that list exactly when it would call its hover callback.
	method _widgets_under_pointer () {
		my @widgets;
		for my $id (@{ Clay_GetPointerOverIds() }) {
			my $widget = $_widget_by_id->{ $id->{id} };
			push @widgets, $widget if defined $widget && $self->_belongs_here($widget);
		}
		return @widgets;
	}

	method _scroll_positions () {
		my %positions;
		for my $widget (grep { defined && $self->_belongs_here($_) } @$_scroll_widgets) {
			my $data = Clay_GetScrollContainerData(Clay_GetElementId($widget->id));
			$positions{ refaddr $widget } = [ $widget, $data->{scrollPosition} ] if $data->{found};
		}
		return %positions;
	}

	method _scroll_changes ($before) {
		my @changes;
		for my $entry (values %$before) {
			my ($widget, $old) = @$entry;
			my $data = Clay_GetScrollContainerData(Clay_GetElementId($widget->id));
			next unless $data->{found};
			my $new = $data->{scrollPosition};
			my ($dx, $dy) = ($new->{x} - $old->{x}, $new->{y} - $old->{y});
			push @changes, [ $widget, $dx, $dy ] if $dx != 0 || $dy != 0;
		}
		return @changes;
	}

	# Widgets sorted by their position in the last walk (pre-order); widgets
	# the walk did not reach (removed ones) keep their relative order last.
	method _in_tree_order (@widgets) {
		my $rank = sub ($widget) { $_walk_order->{ refaddr $widget } // 9**9**9 };
		return map { $_->[1] } sort { $a->[0] <=> $b->[0] } map { [ $rank->($_), $_ ] } @widgets;
	}

	method widget_for ($user_data) {
		return undef unless defined $user_data && $user_data;
		return $_widget_by_refaddr->{$user_data};
	}

	# ---------------------------------------------------------------------
	# Focus.
	# ---------------------------------------------------------------------

	method get_focused_widget () {
		return $_focused;
	}

	# Called by a widget whose child $top leaves the tree: the interaction
	# tracker drops the subtree (hovered widgets get OnHoverStopped), then
	# focus held inside it is released (the focused widget gets OnBlur).
	# Both run even if a listener dies; the first error is rethrown.
	method _subtree_detached ($top) {
		my $error;
		{
			local $@;
			eval { $interaction->_subtree_detached($top); 1 }
				or $error = $@ || 'unknown listener error';
			eval { $self->_release_focus_within($top); 1 }
				or $error //= $@ || 'unknown listener error';
		}
		die $error if defined $error;
		return;
	}

	method _release_focus_within ($top) {
		return unless defined $_focused;
		for (my $node = $_focused; defined $node; $node = $node->parent) {
			next unless refaddr($node) == refaddr($top);
			$self->set_focused_widget(undef);
			return;
		}
		return;
	}

	method set_focused_widget ($widget) {
		# Pass undef to blur. Setting to the currently focused widget is
		# a no-op (no events refire).
		if (defined $_focused && defined $widget && refaddr($_focused) == refaddr($widget)) {
			return;
		}
		if (!defined $_focused && !defined $widget) {
			return;
		}

		if (defined $widget) {
			die "Clay::UI: set_focused_widget target must be a blessed widget"
				unless blessed $widget;
			die "Clay::UI: set_focused_widget target must consume Clay::UI::Role::Interaction::Focusable"
				unless $widget->DOES('Clay::UI::Role::Interaction::Focusable');
			die "Clay::UI: set_focused_widget target does not belong to this Clay::UI"
				unless $self->_belongs_here($widget);
			die "Clay::UI: set_focused_widget target is not currently focusable (can_focus returned false)"
				unless $widget->can_focus;
		}

		# The focused widget changes before any listener runs; a dying
		# OnBlur listener still lets OnFocus fire.
		my $previous = $_focused;
		$_focused = $widget;
		weaken $_focused if defined $_focused;

		Clay::UI::Interaction::_fire_all(
			(defined $previous ? [ $previous, Clay::UI::Events::OnBlur->new ]  : ()),
			(defined $widget   ? [ $widget,   Clay::UI::Events::OnFocus->new ] : ()),
		);
		return;
	}

	method focus_next () {
		my $next = $self->_compute_next_focus($_focused);
		return unless defined $next;
		$self->set_focused_widget($next);
		return;
	}

	method focus_previous () {
		my $prev = $self->_compute_previous_focus($_focused);
		return unless defined $prev;
		$self->set_focused_widget($prev);
		return;
	}

	method _compute_next_focus ($from) {
		return $self->_delegate_or_default($from, 'get_next_focus', '_compute_default_next_focus');
	}

	method _compute_previous_focus ($from) {
		return $self->_delegate_or_default($from, 'get_previous_focus', '_compute_default_previous_focus');
	}

	# The nearest HasFocusOrder ancestor of the focused widget (including
	# itself) takes over; with nothing focused, the root does if it
	# composes HasFocusOrder.
	method _delegate_or_default ($from, $custom_method, $default_method) {
		my $node = $from // $root;
		while (defined $node) {
			if ($node->DOES('Clay::UI::Role::Interaction::HasFocusOrder')) {
				return $self->_validate_focus_target($node, $node->$custom_method);
			}
			last unless defined $from;
			$node = $node->parent;
		}
		return $self->$default_method($from);
	}

	# undef means "no change", as does a focusable widget of this UI that
	# is disabled right now; anything else a HasFocusOrder returns is a bug
	# in that class.
	method _validate_focus_target ($order, $widget) {
		return undef unless defined $widget;
		my $class = ref $order;
		die "Clay::UI: $class returned a non-widget from its focus order"
			unless blessed $widget;
		die "Clay::UI: $class returned " . ref($widget) . ", which is not Clay::UI::Role::Interaction::Focusable"
			unless $widget->DOES('Clay::UI::Role::Interaction::Focusable');
		die "Clay::UI: $class returned " . ref($widget) . ", which is not part of this Clay::UI"
			unless $self->_belongs_here($widget);
		return $widget->can_focus ? $widget : undef;
	}

	# Every Focusable in depth-first pre-order, focusable right now or not.
	method _focusables_in_order () {
		my @focusables;
		my @stack = ($root);
		while (@stack) {
			my $node = shift @stack;
			push @focusables, $node if $node->DOES('Clay::UI::Role::Interaction::Focusable');
			unshift @stack, @{ $node->children } if $node->DOES('Clay::UI::Role::Core::Element');
		}
		return @focusables;
	}

	# The next focusable widget after $from in pre-order ($step 1) or
	# before it ($step -1), wrapping around. $from itself does not have to
	# be focusable (it may have been disabled while focused).
	method _step_focus ($from, $step) {
		my @all = $self->_focusables_in_order;
		return undef unless @all;
		my $start;
		if (defined $from) {
			($start) = grep { refaddr($all[$_]) == refaddr($from) } 0 .. $#all;
		}
		$start //= $step > 0 ? -1 : scalar @all;
		for my $offset (1 .. scalar @all) {
			my $candidate = $all[ ($start + $step * $offset) % @all ];
			return $candidate if $candidate->can_focus;
		}
		return undef;
	}

	method _compute_default_next_focus ($from) {
		return $self->_step_focus($from, 1);
	}

	method _compute_default_previous_focus ($from) {
		return $self->_step_focus($from, -1);
	}

	# Injects the refaddr back-reference into a config hash the walker owns
	# (a copy of what the widget returned) and stages the registry entry.
	method _attach_back_reference ($config, $node) {
		if (exists $config->{user_data} || exists $config->{userData}) {
			die "Clay::UI: widget " . ref($node)
				. " set user_data in its config; Clay::UI auto-injects a refaddr"
				. " back-reference here. Use one mechanism or the other, not both.";
		}
		my $addr = refaddr($node);
		$config->{user_data} = $addr;
		$_pending_by_refaddr->{$addr} = $node;
		weaken $_pending_by_refaddr->{$addr};
		return;
	}

	method _register_element ($element_id, $node) {
		$_pending_by_id->{$element_id} = $node;
		weaken $_pending_by_id->{$element_id};
		$_pending_order->{ refaddr $node } = scalar keys %$_pending_order;
		if ($node->DOES('Clay::UI::Role::Layout::HasScroll')) {
			push @$_pending_scroll, $node;
			weaken $_pending_scroll->[-1];
		}
		return;
	}

	# Declares $node and its subtree. $base is the nearest ancestor-or-self
	# user id ('' if none) and $indices the child indices below it; they
	# name anonymous elements (see Element::resolve_id).
	#
	# Only the config is built before the element is opened; marshalling
	# (Clay__ConfigureOpenElement), the scroll offset lookup and the
	# children run after the open, inside one guard, so Clay__CloseElement
	# always runs and the first error is rethrown after it: Clay's
	# open-element stack stays balanced whatever fails. No listener runs
	# during the walk.
	method _walk ($node, $base, $indices) {
		unless (blessed $node) {
			die "Clay::UI: tree node is not a blessed widget (got " . (ref($node) || 'non-ref') . ")";
		}

		if ($node->DOES('Clay::UI::Role::Core::TextNode')) {
			my %text_config = %{ $node->text_config };
			$self->_attach_back_reference(\%text_config, $node);
			Clay__OpenTextElement($node->text, camelize_keys(\%text_config));
			return;
		}

		unless ($node->DOES('Clay::UI::Role::Core::Element')) {
			die "Clay::UI: tree node " . ref($node) . " does not consume Clay::UI::Role::Core::Element or TextNode";
		}

		my %config = %{ $node->to_config };
		$self->_attach_back_reference(\%config, $node);
		my $camelized = camelize_keys(\%config);

		my $element = Clay_GetElementId($node->resolve_id($base, $indices));
		$self->_register_element($element->{id}, $node);
		my ($child_base, $child_indices) = defined $node->id ? ($node->id, []) : ($base, $indices);

		Clay__OpenElementWithId($element);
		my $ok = eval {
			my $clip = $camelized->{clip};
			if ($clip && !exists $clip->{childOffset}) {
				$clip->{childOffset} = Clay_GetScrollOffset();
			}
			Clay__ConfigureOpenElement($camelized);

			my @children = @{ $node->children };
			for my $index (0 .. $#children) {
				$self->_walk($children[$index], $child_base, [ @$child_indices, $index ]);
			}
			1;
		};
		my $error = $@;
		Clay__CloseElement();
		die($error || 'unknown walker error') unless $ok;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI - Perl-idiomatic high-level layer over Clay::XS

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::XS qw(sizing_grow sizing_fixed);
	use Clay::UI;
	use Clay::UI::Box;

	class My::Box :strict(params) :does(Clay::UI::Box) {}

	my $root = My::Box->new(
		id               => 'root',
		layout           => { sizing => { width => sizing_grow(), height => sizing_grow() } },
		background_color => [40, 50, 60, 255],
	);
	my $button = My::Box->new(
		id     => 'ok',
		layout => { sizing => { width => sizing_fixed(80), height => sizing_fixed(30) } },
	);
	$button->on('OnHoverStart', sub ($event) { warn "over the button\n"; return });
	$root->add_child($button);

	my $ui = Clay::UI->new(
		width  => 800,
		height => 600,
		root   => $root,
	);

	my $commands = $ui->render(
		pointer_state => { x => 120, y => 80, down => 0 },
	);

	my $hovered = $ui->interaction->under_pointer;  # arrayref of widget objects

=head1 DESCRIPTION

C<Clay::UI> wraps the low-level L<Clay::XS> binding in an
Object::Pad class. The class owns the Clay context, the measure-text
callback, and the widget back-reference registries, so callers never
have to invoke C<Clay_*> functions directly. Each L</render> turns the
pointer and scroll input into widget events (see L</POINTER EVENTS>)
and then lays out the widget tree.

The low-level API is untouched and remains independently usable.

=head1 CONSTRUCTOR

=head2 new

	my $ui = Clay::UI->new(%params);

Required:

=over 4

=item C<root>

The root widget. Must be a blessed object consuming
L<Clay::UI::Role::Core::Element> or L<Clay::UI::Role::Core::TextNode>,
and must not have a parent (it is the top of its tree). Immutable after
construction (the I<tree> below the root is still mutable through the
widgets' own child-mutation methods).

=item C<width>, C<height>

Positive numbers; the viewport dimensions. Mutable post-construction
via the same-named accessor methods, which propagate the change to
Clay automatically.

=back

Optional:

=over 4

=item C<memory_size>

Bytes of arena memory to allocate: an integer of at least
C<Clay_MinMemorySize()>, which is also the default.

=item C<error_handler>

Coderef called with C<($error_hashref, $userdata)> when Clay reports an
error. Default: C<die "Clay error: $err->{errorText}\n">. Like
C<measure_text>, it runs inside Clay and must not use any Clay::UI
object (a C<render> there dies, see
L<Clay::XS/What a callback may do>). An exception
thrown by the handler makes C<render> die with it (see
L<Clay::XS/ERRORS FROM CALLBACKS>), so with the default handler any Clay
error - for example two widgets with the same C<id> - makes C<render>
die with C<Clay error: ...>.

=item C<measure_text>

Coderef called with C<($text, $config, $userdata)>, must return
C<< { width => $w, height => $h } >>. Default: monospace estimate,
C<width = length($text) * fontSize>, C<height = fontSize>. It runs while
Clay lays out the frame and must not use any Clay::UI object: C<render>,
C<width>, C<height> or C<measure_text> writes die there, which makes the
outer C<render> die.

=back

=head1 METHODS

=head2 root

Read-only accessor for the root widget passed at construction.

=head2 width, width($new)

Read or write the viewport width. Setting also issues
C<Clay_SetLayoutDimensions> so the new size takes effect on the next
C<render>.

=head2 height, height($new)

Mirror of C<width>.

=head2 measure_text, measure_text($coderef)

Read or replace the measure-text callback. On write, also calls
C<Clay_ResetMeasureTextCache> so previously cached measurements made
by the old callback are discarded.

=head2 render

	my $commands = $ui->render(%args);

Processes the frame's pointer and scroll input, fires the resulting
events (see L</POINTER EVENTS>), then lays out the root widget tree and
returns the render-command arrayref (see L<Clay::XS/RENDER COMMANDS>).

Named arguments:

=over 4

=item C<pointer_state> (optional)

Hashref C<< { x => $x, y => $y, down => $bool } >> with numeric C<x> and
C<y>; no other keys. When omitted, the pointer state from the previous
frame is reused.

=item C<delta_time> (optional, default 0)

Seconds since last frame, a finite number E<gt>= 0; passed to
C<Clay_UpdateScrollContainers> and C<Clay_EndLayout>.

=item C<scroll_delta> (optional, default C<< { x => 0, y => 0 } >>)

Wheel input for this frame, C<< { x => ..., y => ... } >> (no other
keys) or C<[x, y]>.
Scroll containers (L<Clay::UI::Role::Layout::HasScroll>) under the
pointer scroll by it; Clay applies momentum and clamping.

=item C<enable_drag_scrolling> (optional, default false)

Lets pressing and dragging scroll a container, as on touch screens.

=back

Unknown arguments die. C<render> dies if an event listener dies (after
all of the frame's events have fired and the layout pass has run, see
L</POINTER EVENTS>), if any widget
produces a config Clay::XS rejects, if Clay reports an error through the
error handler, or if a callback dies; the frame is discarded and Clay
stays usable, so the next C<render> works once the cause is fixed.
C<render> cannot be called again while it is running (for example from
an event listener).

=head2 widget_for

	my $widget = $ui->widget_for($user_data);

Given the C<userData> integer carried on a render command, returns the
widget object that produced it (or C<undef> if the widget has been
garbage-collected since the last C<render> call, or if C<$user_data> is
falsy or unknown).

	for my $cmd (@$render_commands) {
		my $widget = $ui->widget_for($cmd->{userData});
		next unless $widget;
		# dispatch on ref $widget, read its fields, etc.
	}

=head2 interaction

Returns this UI's L<Clay::UI::Interaction>, which owns hover, armed and
pressed state. C<< $ui->interaction->under_pointer >> lists the widgets
that were under the pointer at the last C<render>, in Clay's
pointer-over order (see L</POINTER EVENTS>), Hoverable or not; widgets
that have been garbage-collected or removed from the tree since are
skipped. C<< $ui->interaction->update(...) >> takes synthetic pointer
input between renders.

=head2 get_focused_widget

Returns the widget currently holding focus, or C<undef> if no widget
is focused (or the previously focused widget has been
garbage-collected). The reference is held weakly.

=head2 set_focused_widget

	$ui->set_focused_widget($widget);

Sets focus to C<$widget>. Pass C<undef> to clear focus (blur).

Validates loudly, before anything changes:

=over 4

=item *

Dies if C<$widget> is not blessed.

=item *

Dies if C<$widget> does not consume
L<Clay::UI::Role::Interaction::Focusable>.

=item *

Dies if C<< $widget->can_focus >> returns false.

=item *

Dies if C<$widget> belongs to a different Clay::UI tree.

=back

Then switches focus - the C<focused> state moves from the previous
widget to the new one - and fires L<Clay::UI::Events::OnBlur> on the
previously focused widget (if any) and L<Clay::UI::Events::OnFocus> on
the new one (if any). Both events fire even if the first listener dies;
the first error is rethrown afterwards, with focus already changed.
Setting focus to the already-focused widget is a no-op (no events
fire).

Focus changes only through this method, L</focus_next>,
L</focus_previous>, and the removal of a subtree holding the focused
widget (which blurs it). C<render> never changes focus.

=head2 focus_next

Moves focus to the next focusable widget.

=head2 focus_previous

Moves focus to the previous focusable widget.

Both follow the same rules.

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

=head1 POINTER EVENTS

C<render> handles the frame's input before it lays anything out:

=over 4

=item 1.

The pointer (C<pointer_state>, or the previous frame's) goes to
C<Clay_SetPointerState>. Clay tests it against the layout computed by
the previous C<render>, so the widgets I<under the pointer> are those
whose elements Clay lists in C<Clay_GetPointerOverIds>, in that order:
the topmost floating element first, depth-first within it. A widget
added to the tree can be hovered from the render after the one that
first lays it out.

=item 2.

C<scroll_delta> goes to C<Clay_UpdateScrollContainers>, which scrolls
the scroll container under the pointer.

=item 3.

The widgets under the pointer, whether the pointer is down and the
scroll containers that moved go to the interaction tracker
(C<< $ui->interaction->update >>, see L<Clay::UI::Interaction>). It
updates the widget states first (C<hovered>, C<pressed>, see below),
then the events fire in this order: every OnHoverStopped, every
OnHoverStart, OnPress, OnRelease, every OnScroll. Events of one kind
fire in tree order (depth-first pre-order of the last layout).

=item 4.

The layout pass runs and C<render> returns its commands.

=back

The events:

=over 4

=item L<Clay::UI::Events::OnHoverStart>, L<Clay::UI::Events::OnHoverStopped>

A L<Clay::UI::Role::Interaction::Hoverable> gets OnHoverStart when it
comes under the pointer and OnHoverStopped when it leaves it. A hovered
widget removed from the tree gets OnHoverStopped at once, during the
removal (as a focused one gets OnBlur); a removed armed or pressed
Pressable is dropped without events. They do not bubble: every hovered widget, nested
ones included, gets its own event.

=item L<Clay::UI::Events::OnPress>

When the pointer goes down, exactly one
L<Clay::UI::Role::Interaction::Pressable> gets OnPress: the innermost
Pressable of the topmost stack under the pointer (a button inside a
pressable card, not the card; the upper of two overlapping, unrelated
Pressables). Every Pressable under the pointer becomes I<armed>.

=item L<Clay::UI::Events::OnRelease>

When the pointer goes up, the innermost I<armed> Pressable still under
the pointer gets OnRelease - a completed click. Every release disarms
all Pressables, so a press that started elsewhere and a press that was
dragged off the widget end without OnRelease.

A Pressable's C<is_pressed> (and C<pressed> state) is true while it is
armed, under the pointer and the pointer is down. OnPress and OnRelease
bubble with C<IF_CONTINUE>: an ancestor sees the event only when the
widget's listeners return C<< Clay::UI::Enum::Result->CONTINUE >>.

=item L<Clay::UI::Events::OnScroll>

A widget composing L<Clay::UI::Role::Layout::HasScroll> gets OnScroll
with C<delta_x> / C<delta_y> whenever its scroll position changed in
this frame (wheel input, drag scrolling or momentum).

=back

The constructor settles Clay's pointer state, so the first C<render>
never reports a press or release that did not happen.

Listeners run while no Clay element is open. They may change the tree,
widget attributes and focus, and use other Clay::UI objects; the
changes show in this frame's layout. They must not call this object's
C<render>. If a listener dies, the remaining events of the frame still
fire and the layout pass still runs (Clay would otherwise forget the
scroll positions at the next C<render>), then C<render> dies with the
first error and the frame's render commands are discarded; the widget
states are already up to date and the next C<render> works normally.

Focus events (L<Clay::UI::Events::OnFocus>, L<Clay::UI::Events::OnBlur>)
do not come from C<render>; see L</set_focused_widget>.

=head1 NOTES

The walker auto-injects C<refaddr($widget)> as each element's
C<user_data> (into its own copy of the config the widget returned) so
render commands carry a back-reference. A widget's C<to_config> (or
C<text_config>) must therefore NOT set C<user_data> itself; C<render>
dies with a clear message if it sees one already present.

Widgets without an C<id> get one derived from their position below the
nearest ancestor that has one; see
L<Clay::UI::Role::Core::Element/resolve_id>.

Registry entries are weak references. The widget tree is kept alive by
the C<root> field on this object, so as long as the C<Clay::UI>
instance is alive, every widget reachable from C<root> stays
resolvable.

=head1 SEE ALSO

L<Clay::UI::Role::Core::Element>, L<Clay::XS>.

=cut
