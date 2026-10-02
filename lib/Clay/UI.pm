package Clay::UI;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Scalar::Util qw(blessed refaddr);

use Clay::XS qw(
	Clay_Initialize
	Clay_MinMemorySize
	Clay_GetCurrentContext
	Clay_SetCurrentContext
	Clay_SetMaxElementCount
	Clay_SetMaxMeasureTextCacheWordCount
	Clay_SetLayoutDimensions
	Clay_SetMeasureTextFunction
	Clay_ResetMeasureTextCache
	Clay_SetPointerState
	Clay_GetPointerState
	Clay_GetPointerOverIds
	Clay_UpdateScrollContainers
	Clay_GetScrollOffset
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
use Clay::UI::_validate qw(is_finite_number);
use Clay::UI::Interaction;
use Clay::UI::_FrameRegistry;
use Clay::UI::Revision qw(bump_revision);

our $VERSION = '0.02';

my %RENDER_ARGS  = map { $_ => 1 } qw(pointer_state delta_time scroll_delta enable_drag_scrolling);
my %POINTER_KEYS = map { $_ => 1 } qw(x y down);
my %VECTOR_KEYS  = map { $_ => 1 } qw(x y);

# Clay's default element count, and the fewest measure-cache words Clay::XS
# accepts.
my $DEFAULT_MAX_ELEMENT_COUNT = 8192;
my $MIN_MEASURE_CACHE_WORDS   = 32;

class Clay::UI :strict(params) {
	field $root   :param :reader;
	field $width  :param;
	field $height :param;

	field $memory_size       :param = undef;
	field $max_element_count :param :reader = $DEFAULT_MAX_ELEMENT_COUNT;
	field $error_handler     :param = undef;
	field $measure_text      :param = undef;

	field $_ctx;
	field $_uses_default_error_handler;
	field $_rendering = 0;

	# What the last completed frame laid out (see Clay::UI::_FrameRegistry).
	field $_frame = Clay::UI::_FrameRegistry->new;

	# The last pointer state passed to render, and the tracker that owns
	# hover, armed, pressed and focus state.
	field $_last_pointer;
	field $interaction :reader;

	ADJUST {
		unless (blessed $root
			&& ($root->DOES('Clay::UI::Role::Core::Element')
			 || $root->DOES('Clay::UI::Role::Core::TextNode'))) {
			die "Clay::UI: 'root' must be a widget consuming Clay::UI::Role::Core::Element or TextNode";
		}
		die "Clay::UI: 'root' must not have a parent; the root is the top of its widget tree"
			if defined $root->parent;
		die "Clay::UI: 'root' is already the root of another Clay::UI"
			if defined $root->_local_ui_controller;
		unless (_is_viewport_size($width) && _is_viewport_size($height)) {
			die "Clay::UI: 'width' and 'height' must be positive finite numbers";
		}
		unless (is_finite_number($max_element_count) && $max_element_count == int($max_element_count)
			&& $max_element_count >= 1) {
			die "Clay::UI: 'max_element_count' must be a positive integer";
		}

		$_uses_default_error_handler = !defined $error_handler;
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

		# A failure frees the new context at once and makes the caller's
		# context current again.
		my $previous = Clay_GetCurrentContext();
		my $ok = eval {
			$_ctx = $self->_initialize_context;
			Clay_SetMeasureTextFunction($measure_text);
			# Clay's pointer state starts zeroed, which reads as "pressed
			# this frame"; settle it so the first real pointer frame is no
			# click.
			Clay_SetPointerState({ x => -1, y => -1 }, 0);
			1;
		};
		unless ($ok) {
			my $error = $@;
			undef $_ctx;
			Clay_SetCurrentContext($previous) if defined $previous;
			die $error;
		}

		# Events follow the tree order of the last completed frame.
		$interaction = Clay::UI::Interaction->new(
			ui         => $self,
			tree_order => sub (@widgets) { $_frame->in_tree_order(@widgets) },
		);
		$root->_set_ui_controller($self);
	}

	# Creates this UI's context, sized for max_element_count, and leaves it
	# current. Clay_MinMemorySize and Clay_Initialize use the counts of the
	# current context, so a throwaway seed context carries this UI's counts
	# to them: setting the counts on another UI's context would disable it
	# until it is initialised again, and setting them with no current
	# context would change Clay's process-wide defaults. The measure cache
	# gets twice as many words as elements, as Clay's defaults do.
	method _initialize_context () {
		my $seed = Clay_Initialize(Clay_MinMemorySize(), { width => $width, height => $height });
		Clay_SetMaxElementCount($max_element_count);
		my $word_count = 2 * $max_element_count;
		Clay_SetMaxMeasureTextCacheWordCount($word_count > $MIN_MEASURE_CACHE_WORDS ? $word_count : $MIN_MEASURE_CACHE_WORDS);

		my $min_memory = Clay_MinMemorySize();
		$memory_size //= $min_memory;
		unless (is_finite_number($memory_size) && $memory_size == int($memory_size)
			&& $memory_size >= $min_memory) {
			die "Clay::UI: 'memory_size' must be an integer >= Clay_MinMemorySize() ($min_memory)"
				. " for max_element_count $max_element_count";
		}
		# The new context copies the seed's counts and becomes current.
		return Clay_Initialize($memory_size, { width => $width, height => $height }, $error_handler);
	}

	# Clay keeps one element for its own root and never fills its last
	# slot, so this many widgets fit into one frame.
	method _widget_capacity () {
		return $max_element_count > 2 ? $max_element_count - 2 : 0;
	}

	sub _is_viewport_size ($value) {
		return is_finite_number($value) && $value > 0;
	}

	sub _one_value ($name, @value) {
		die "Clay::UI: $name takes one value" unless @value == 1;
		return $value[0];
	}

	# Read with no args; write with one arg, propagating to Clay. Clay gets
	# the new size before the field does, so a size Clay refuses leaves
	# both unchanged.
	method width (@v) {
		return $width unless @v;
		my $new = _one_value(width => @v);
		die "Clay::UI: width must be a positive finite number" unless _is_viewport_size($new);
		Clay_SetCurrentContext($_ctx);
		Clay_SetLayoutDimensions({ width => $new, height => $height });
		$width = $new;
		bump_revision();
		return $width;
	}

	method height (@v) {
		return $height unless @v;
		my $new = _one_value(height => @v);
		die "Clay::UI: height must be a positive finite number" unless _is_viewport_size($new);
		Clay_SetCurrentContext($_ctx);
		Clay_SetLayoutDimensions({ width => $width, height => $new });
		$height = $new;
		bump_revision();
		return $height;
	}

	method measure_text (@v) {
		return $measure_text unless @v;
		my $new = _one_value(measure_text => @v);
		die "Clay::UI: measure_text must be a coderef" unless ref $new eq 'CODE';
		Clay_SetCurrentContext($_ctx);
		Clay_SetMeasureTextFunction($new);
		Clay_ResetMeasureTextCache();
		$measure_text = $new;
		bump_revision();
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
				die "Clay::UI::render: pointer_state '$axis' must be a finite number"
					unless is_finite_number($pointer->{$axis});
			}
			$pointer = { x => $pointer->{x}, y => $pointer->{y}, down => $pointer->{down} ? 1 : 0 };
		}

		my $delta_time = $args{delta_time} // 0;
		die "Clay::UI::render: 'delta_time' must be a finite number >= 0"
			unless is_finite_number($delta_time) && $delta_time >= 0;

		my $scroll_delta = $args{scroll_delta} // [0, 0];
		if (ref $scroll_delta eq 'HASH') {
			my @bad = grep { !$VECTOR_KEYS{$_} } keys %$scroll_delta;
			die "Clay::UI::render: unknown scroll_delta key(s): @{[ sort @bad ]}" if @bad;
			$scroll_delta = [ @{$scroll_delta}{qw(x y)} ];
		}
		die "Clay::UI::render: 'scroll_delta' must be { x => ..., y => ... } or [x, y] of finite numbers"
			unless ref $scroll_delta eq 'ARRAY' && @$scroll_delta == 2
				&& !grep { !is_finite_number($_) } @$scroll_delta;

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
		if (defined $pointer) {
			Clay_SetPointerState({ x => $pointer->{x}, y => $pointer->{y} }, $pointer->{down});
		}
		$_last_pointer = $pointer;
		my @under_pointer = $self->_widgets_under_pointer;
		my $pointer_data  = Clay_GetPointerState();

		my $scroll_before = $_frame->scroll_positions($self);
		Clay_UpdateScrollContainers($frame->{drag}, $frame->{scroll_delta}, $frame->{delta_time});

		my ($dispatch_error, $layout_error, $commands);
		{
			local $@;
			eval {
				# Wheel, drag and momentum scrolling move containers without
				# any setter: the frame changes all the same.
				my @scrolled = $_frame->scroll_changes($scroll_before);
				bump_revision() if @scrolled;

				my $state = $pointer_data->{state};
				$interaction->update(
					over     => \@under_pointer,
					down     => $state == CLAY_POINTER_DATA_PRESSED || $state == CLAY_POINTER_DATA_PRESSED_THIS_FRAME,
					x        => $pointer_data->{position}{x},
					y        => $pointer_data->{position}{y},
					scrolled => \@scrolled,
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
		# The walk fills a new registry; it replaces the current one only
		# after a complete frame, so a failed frame leaves the last good one
		# in place.
		my $next_frame = Clay::UI::_FrameRegistry->new;

		# A listener may have used another Clay::UI, which switches Clay's
		# current context.
		Clay_SetCurrentContext($_ctx);
		my ($walk_error, $end_error, $commands);
		Clay_BeginLayout();
		{
			local $@;
			eval { $self->_walk($next_frame, $root, '', []); 1 } or $walk_error = $@ || 'unknown walker error';
		}
		{
			local $@;
			eval { $commands = Clay_EndLayout($delta_time); 1 }
				or $end_error = $@ || 'unknown Clay_EndLayout error';
		}
		$end_error = $self->_capacity_error($next_frame->element_count)
			if defined $end_error && $_uses_default_error_handler && $next_frame->element_count > $self->_widget_capacity;

		if (defined $walk_error) {
			$walk_error .= "(Clay_EndLayout also failed: $end_error)"
				if defined $end_error && !ref $walk_error;
			die $walk_error;
		}
		die $end_error if defined $end_error;

		$_frame = $next_frame;
		return $commands;
	}

	# Clay drops every element past its capacity without a word and then
	# reports the open elements it could not close; this says what
	# happened instead.
	method _capacity_error ($widget_count) {
		return "Clay::UI: the widget tree has more elements than max_element_count ($max_element_count) allows:"
			. " $widget_count widgets, at most " . $self->_widget_capacity . " fit;"
			. " pass a larger max_element_count to Clay::UI->new\n";
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
			my $widget = $_frame->widget_for_element($id->{id});
			push @widgets, $widget if defined $widget && $self->_belongs_here($widget);
		}
		return @widgets;
	}

	method widget_for ($user_data) {
		return undef unless defined $user_data && $user_data;
		return $_frame->widget_for($user_data);
	}

	# Injects the back-reference into a config hash the walker owns (a
	# copy of what the widget returned) and records it in $frame.
	sub _attach_back_reference ($frame, $config, $node) {
		if (exists $config->{user_data} || exists $config->{userData}) {
			die "Clay::UI: widget " . ref($node)
				. " set user_data in its config; Clay::UI auto-injects a refaddr"
				. " back-reference here. Use one mechanism or the other, not both.";
		}
		$config->{user_data} = $frame->add_back_reference($node);
		return;
	}

	# Declares $node and its subtree, recording it in $frame (the registry
	# of the frame being laid out). $base is the nearest ancestor-or-self
	# user id ('' if none) and $indices the child indices below it; they
	# name anonymous elements (see Element::resolve_id).
	#
	# Only the config is built before the element is opened; marshalling
	# (Clay__ConfigureOpenElement), the scroll offset lookup and the
	# children run after the open, inside one guard, so Clay__CloseElement
	# always runs and the first error is rethrown after it: Clay's
	# open-element stack stays balanced whatever fails. No listener runs
	# during the walk.
	method _walk ($frame, $node, $base, $indices) {
		unless (blessed $node) {
			die "Clay::UI: tree node is not a blessed widget (got " . (ref($node) || 'non-ref') . ")";
		}

		if ($node->DOES('Clay::UI::Role::Core::TextNode')) {
			my %text_config = %{ $node->text_config };
			_attach_back_reference($frame, \%text_config, $node);
			Clay__OpenTextElement($node->text, camelize_keys(\%text_config));
			return;
		}

		unless ($node->DOES('Clay::UI::Role::Core::Element')) {
			die "Clay::UI: tree node " . ref($node) . " does not consume Clay::UI::Role::Core::Element or TextNode";
		}

		my %config = %{ $node->to_config };
		_attach_back_reference($frame, \%config, $node);
		my $camelized = camelize_keys(\%config);

		my $element = Clay_GetElementId($node->resolve_id($base, $indices));
		$frame->add_element($node, $element);
		my ($child_base, $child_indices) = defined $node->id ? ($node->id, []) : ($base, $indices);

		Clay__OpenElementWithId($element);
		my $ok = eval {
			my $clip = $camelized->{clip};
			if ($frame->is_scroll_container($node) && $clip && !exists $clip->{childOffset}) {
				$clip->{childOffset} = Clay_GetScrollOffset();
			}
			Clay__ConfigureOpenElement($camelized);

			my @children = @{ $node->children };
			for my $index (0 .. $#children) {
				$self->_walk($frame, $children[$index], $child_base, [ @$child_indices, $index ]);
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

Every setter that changes what a frame lays out or draws - widget
attributes, children, user states, this object's C<width>, C<height> and
C<measure_text>, and the hovered, armed, pressed and focused widgets of
its L</interaction> - bumps a process-wide revision counter
(L<Clay::UI::Revision>); reading never does. A renderer compares the
counter with the value it saw at its last frame and skips the frame
while the two are equal. Widgets that keep state of their own call
C<mark_changed> (see L<Clay::UI::Role::Core::Element/mark_changed>).

The low-level API is untouched and remains independently usable.

=head1 CONSTRUCTOR

=head2 new

	my $ui = Clay::UI->new(%params);

Required:

=over 4

=item C<root>

The root widget. Must be a blessed object consuming
L<Clay::UI::Role::Core::Element> or L<Clay::UI::Role::Core::TextNode>,
and must not currently have a parent (it is the top of its tree) nor be
the root of another Clay::UI; a widget that was removed from its parent
may become a root. A constructor that dies leaves the Clay context that
was current before it current again. Immutable after
construction (the I<tree> below the root is still mutable through the
widgets' own child-mutation methods).

=item C<width>, C<height>

Positive finite numbers; the viewport dimensions. Mutable post-construction
via the same-named accessor methods, which propagate the change to
Clay automatically.

=back

Optional:

=over 4

=item C<memory_size>

Bytes of arena memory to allocate: an integer of at least
C<Clay_MinMemorySize()> for this UI's C<max_element_count>, which is
also the default.

=item C<max_element_count>

How many Clay layout elements this UI's context holds: a positive
integer, default 8192 (Clay's default). Every element widget and every
text widget of the tree is one element; Clay keeps two of the slots
for itself, so a frame fits C<max_element_count - 2> widgets (none
for a count below 3). Clay's
measure-text word cache is sized to twice this count (at least 32), as
Clay's defaults are. Each Clay::UI has its own count, whatever context
is current when it is constructed. A larger count needs more memory
(see C<memory_size>).

A tree with more widgets than fit makes C<render> die with
C<Clay::UI: the widget tree has more elements than max_element_count
(8192) allows: ...> when the default C<error_handler> is in use.

=item C<error_handler>

Coderef called with C<($error_hashref, $userdata)> when Clay reports an
error. Default: C<die "Clay error: $err->{errorText}\n">. Like
C<measure_text>, it runs inside Clay and must not use any Clay::UI
object (a C<render> there dies, see
L<Clay::XS/What a callback may do>). An exception
thrown by the handler makes C<render> die with it (see
L<Clay::XS/ERRORS FROM CALLBACKS>), so with the default handler any Clay
error - for example two widgets with the same C<id> - makes C<render>
die with C<Clay error: ...>. The one exception is a tree with more
widgets than C<max_element_count> allows: Clay drops the excess
elements silently and then reports open elements it could not close,
so the default handler's error is replaced by one that names
C<max_element_count>. A handler of your own receives Clay's error data
unchanged.

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

=head2 max_element_count

Read-only accessor for the C<max_element_count> passed at construction
(8192 by default).

=head2 width, width($new)

Read or write the viewport width, a positive finite number. Setting
also issues C<Clay_SetLayoutDimensions> so the new size takes effect on
the next C<render>; a value that is refused leaves the width as it
was.

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

Hashref C<< { x => $x, y => $y, down => $bool } >> with finite numeric
C<x> and C<y>; no other keys. When omitted, the pointer state from the previous
frame is reused.

=item C<delta_time> (optional, default 0)

Seconds since last frame, a finite number E<gt>= 0; passed to
C<Clay_UpdateScrollContainers> and C<Clay_EndLayout>.

=item C<scroll_delta> (optional, default C<< { x => 0, y => 0 } >>)

Wheel input for this frame, C<< { x => ..., y => ... } >> (no other
keys) or C<[x, y]>, finite numbers.
Scroll containers (L<Clay::UI::Role::Layout::HasScroll>) under the
pointer scroll by it; Clay applies momentum and clamping.

=item C<enable_drag_scrolling> (optional, default false)

Lets pressing and dragging scroll a container, as on touch screens.

=back

Unknown arguments die. C<render> dies if an event listener dies (after
all of the frame's events have fired and the layout pass has run, see
L</POINTER EVENTS>), if any widget
produces a config Clay::XS rejects, if the tree has more widgets than
C<max_element_count> allows (with the default error handler), if Clay
reports an error through the error handler, or if a callback dies; the
frame is discarded and Clay
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

Returns this UI's L<Clay::UI::Interaction>, which owns hover, armed,
pressed and focus state. C<< $ui->interaction->under_pointer >> lists the widgets
that were under the pointer at the last C<render>, in Clay's
pointer-over order (see L</POINTER EVENTS>), Hoverable or not; widgets
that have been garbage-collected or removed from the tree since are
skipped. C<< $ui->interaction->update(...) >> takes synthetic pointer
input between renders, and C<< $ui->interaction->set_focused_widget >>,
C<focus_next> and C<focus_previous> move focus (see
L<Clay::UI::Interaction/FOCUS>).

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
this frame (wheel input, drag scrolling or momentum). Such a change also
bumps the revision (L<Clay::UI::Revision>), as the frame shows it.

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
do not come from C<render>; see L<Clay::UI::Interaction/FOCUS>.

=head1 NOTES

The walker auto-injects C<refaddr($widget)> as each element's
C<user_data> (into its own copy of the config the widget returned) so
render commands carry a back-reference. A widget's C<to_config> (or
C<text_config>) must therefore NOT set C<user_data> itself; C<render>
dies with a clear message if it sees one already present.

For a scroll container (a widget composing
L<Clay::UI::Role::Layout::HasScroll>) without an explicit C<child_offset>,
the walker also sets the C<clip> slice's C<childOffset> to Clay's scroll
offset, so its children follow the scroll position. A C<clip> slice from
any other widget is passed on as is: it clips, but does not scroll.

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
