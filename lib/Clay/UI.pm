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
	Clay_GetPointerOverIds
	Clay_BeginLayout
	Clay_EndLayout
	Clay_GetElementId
	Clay__OpenElementWithId
	Clay__ConfigureOpenElement
	Clay__CloseElement
	Clay__OpenTextElement
);
use Clay::UI::_keys qw(camelize_keys);

use Clay::UI::Events::OnFocus;
use Clay::UI::Events::OnBlur;

our $VERSION = '0.02';

class Clay::UI {
	field $root   :param :reader;
	field $width  :param;
	field $height :param;

	field $memory_size    :param = undef;
	field $error_handler  :param = undef;
	field $measure_text   :param = undef;

	field $_ctx;
	field %_widget_by_refaddr;
	field %_widget_by_id;
	field $_pending_by_refaddr;
	field $_pending_by_id;
	field $_focused = undef;

	ADJUST {
		unless (blessed $root
			&& ($root->DOES('Clay::UI::Role::Core::Element')
			 || $root->DOES('Clay::UI::Role::Core::TextNode'))) {
			die "Clay::UI: 'root' must be a widget consuming Clay::UI::Role::Core::Element or TextNode";
		}
		unless (looks_like_number($width) && $width > 0
			&& looks_like_number($height) && $height > 0) {
			die "Clay::UI: 'width' and 'height' must be positive numbers";
		}

		$memory_size   //= Clay_MinMemorySize();
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

	method render (%args) {
		my %known = (pointer_state => 1, delta_time => 1);
		my @unknown = grep { !$known{$_} } keys %args;
		die "Clay::UI::render: unknown argument(s): @{[ sort @unknown ]}" if @unknown;

		my $pointer    = $args{pointer_state};
		my $delta_time = $args{delta_time} // 0;

		Clay_SetCurrentContext($_ctx);

		if ($pointer) {
			Clay_SetPointerState(
				{ x => $pointer->{x}, y => $pointer->{y} },
				$pointer->{down} ? 1 : 0,
			);
		}

		# Stage registry writes in shadow hashes; commit only on a successful
		# walk so a mid-walk exception cannot leave get_hovered staring at a
		# half-cleared registry from this frame.
		my %staged_by_refaddr;
		my %staged_by_id;
		$_pending_by_refaddr = \%staged_by_refaddr;
		$_pending_by_id      = \%staged_by_id;

		Clay_BeginLayout();

		my $walk_error;
		{
			local $@;
			eval { $self->_walk($root, []); 1 } or $walk_error = $@ || 'unknown walker error';
		}

		my $cmds = Clay_EndLayout($delta_time);

		$_pending_by_refaddr = undef;
		$_pending_by_id      = undef;

		die $walk_error if defined $walk_error;

		%_widget_by_refaddr = %staged_by_refaddr;
		%_widget_by_id      = %staged_by_id;
		# Re-weaken refs after the hash copy (weakness is per-slot, not preserved by assignment).
		weaken $_widget_by_refaddr{$_} for keys %_widget_by_refaddr;
		weaken $_widget_by_id{$_}      for keys %_widget_by_id;

		return $cmds;
	}

	method widget_for ($user_data) {
		return undef unless defined $user_data && $user_data;
		return $_widget_by_refaddr{$user_data};
	}

	method get_hovered () {
		Clay_SetCurrentContext($_ctx);
		my $ids = Clay_GetPointerOverIds();
		my @widgets;
		for my $id (@$ids) {
			my $w = $_widget_by_id{ $id->{id} };
			push @widgets, $w if defined $w;
		}
		return \@widgets;
	}

	method get_focused_widget () {
		return $_focused;
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
				unless defined($widget->ui) && refaddr($widget->ui) == refaddr($self);
			die "Clay::UI: set_focused_widget target is not currently focusable (can_focus returned false)"
				unless $widget->can_focus;
		}

		my $previous = $_focused;
		$_focused = $widget;
		weaken $_focused if defined $_focused;

		if (defined $previous) {
			$previous->fire_event(Clay::UI::Events::OnBlur->new);
		}
		if (defined $widget) {
			$widget->fire_event(Clay::UI::Events::OnFocus->new);
		}
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

	method _delegate_or_default ($from, $custom_method, $default_method) {
		# Walk up from $from looking for the nearest HasFocusOrder ancestor
		# (including $from itself). That ancestor takes over.
		my $node = $from;
		while (defined $node) {
			if ($node->DOES('Clay::UI::Role::Interaction::HasFocusOrder')) {
				my $next = $node->$custom_method;
				return $self->_validate_focus_target($next);
			}
			$node = $node->parent;
		}
		return $self->$default_method($from);
	}

	method _validate_focus_target ($widget) {
		return undef unless defined $widget;
		return undef unless blessed($widget)
			&& $widget->DOES('Clay::UI::Role::Interaction::Focusable')
			&& $widget->can_focus;
		return undef unless defined($widget->ui) && refaddr($widget->ui) == refaddr($self);
		return $widget;
	}

	method _default_focus_chain () {
		my @chain;
		my @stack = ($root);
		while (@stack) {
			my $node = shift @stack;
			if ($node->DOES('Clay::UI::Role::Interaction::Focusable') && $node->can_focus) {
				push @chain, $node;
			}
			if ($node->DOES('Clay::UI::Role::Core::Element')) {
				my $kids = $node->children;
				unshift @stack, @$kids;
			}
		}
		return @chain;
	}

	method _compute_default_next_focus ($from) {
		my @chain = $self->_default_focus_chain;
		return undef unless @chain;
		return $chain[0] unless defined $from;
		my $from_addr = refaddr($from);
		for my $i (0 .. $#chain) {
			next unless refaddr($chain[$i]) == $from_addr;
			return $chain[($i + 1) % @chain];
		}
		# Current focus not in chain (e.g. became disabled) - start at first.
		return $chain[0];
	}

	method _compute_default_previous_focus ($from) {
		my @chain = $self->_default_focus_chain;
		return undef unless @chain;
		return $chain[-1] unless defined $from;
		my $from_addr = refaddr($from);
		for my $i (0 .. $#chain) {
			next unless refaddr($chain[$i]) == $from_addr;
			return $chain[($i - 1) % @chain];
		}
		return $chain[-1];
	}

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

	method _register_id_lookup ($element_id, $node) {
		$_pending_by_id->{$element_id} = $node;
		weaken $_pending_by_id->{$element_id};
		return;
	}

	method _walk ($node, $path) {
		unless (blessed $node) {
			die "Clay::UI: tree node is not a blessed widget (got " . (ref($node) || 'non-ref') . ")";
		}

		if ($node->DOES('Clay::UI::Role::Core::TextNode')) {
			my $text_config = $node->text_config;
			$self->_attach_back_reference($text_config, $node);
			Clay__OpenTextElement($node->text, camelize_keys($text_config));
			return;
		}

		unless ($node->DOES('Clay::UI::Role::Core::Element')) {
			die "Clay::UI: tree node " . ref($node) . " does not consume Clay::UI::Role::Core::Element or TextNode";
		}

		# Build and validate the config BEFORE opening the Clay element so a
		# config-time exception cannot leave Clay's open-element stack
		# unbalanced (which would SEGV at EndLayout).
		my $config = $node->to_config;
		$self->_attach_back_reference($config, $node);
		my $camelized = camelize_keys($config);

		my $id      = $node->resolve_id($path);
		my $element = Clay_GetElementId($id);
		$self->_register_id_lookup($element->{id}, $node);

		Clay__OpenElementWithId($element);
		Clay__ConfigureOpenElement($camelized);

		$node->install_hover_callback if $node->DOES('Clay::UI::Role::Interaction::Hoverable');

		# Ensure CloseElement always runs to keep Clay's open-element
		# stack balanced, even if a child walk dies; re-throw afterwards.
		my $children = $node->children;
		my $child_error;
		for my $index (0 .. $#$children) {
			local $@;
			my $ok = eval {
				$self->_walk($children->[$index], [ @$path, "$id/$index" ]);
				1;
			};
			unless ($ok) {
				$child_error = $@ || 'unknown walker error';
				last;
			}
		}

		Clay__CloseElement();
		die $child_error if defined $child_error;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI - Perl-idiomatic high-level layer over Clay::XS

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI;
	use Clay::UI::Box;

	my $root = Clay::UI::Box->new(
		id               => 'root',
		layout           => { sizing => { width => sizing_grow(), height => sizing_grow() } },
		background_color => [40, 50, 60, 255],
	);

	my $ui = Clay::UI->new(
		width  => 800,
		height => 600,
		root   => $root,
	);

	my $commands = $ui->render(
		pointer_state => { x => 120, y => 80, down => 0 },
	);

	my $hovered = $ui->get_hovered;  # arrayref of widget objects

=head1 DESCRIPTION

C<Clay::UI> wraps the low-level L<Clay::XS> binding in an
Object::Pad class. The class owns the Clay context, the measure-text
callback, and the widget back-reference registries, so callers never
have to invoke C<Clay_*> functions directly.

The low-level API is untouched and remains independently usable.

=head1 CONSTRUCTOR

=head2 new(%params)

Required:

=over 4

=item C<root>

The root widget. Must be a blessed object consuming
L<Clay::UI::Role::Core::Element> or L<Clay::UI::Role::Core::TextNode>. Immutable
after construction (the I<tree> below the root is still mutable through
the widget's own child-mutation methods).

=item C<width>, C<height>

Positive numbers; the viewport dimensions. Mutable post-construction
via the same-named accessor methods, which propagate the change to
Clay automatically.

=back

Optional:

=over 4

=item C<memory_size>

Bytes of arena memory to allocate. Defaults to C<Clay_MinMemorySize()>.

=item C<error_handler>

Coderef called with C<($error_hashref, $userdata)> when Clay reports an
error. Default: C<die "Clay error: $err->{errorText}\n">.

=item C<measure_text>

Coderef called with C<($text, $config, $userdata)>, must return
C<< { width => $w, height => $h } >>. Default: monospace estimate,
C<width = length($text) * fontSize>, C<height = fontSize>.

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

=head2 render(%args)

Lays out the root widget tree and returns the render-command arrayref.

Named arguments:

=over 4

=item C<pointer_state> (optional)

Hashref C<< { x => $x, y => $y, down => $bool } >>. When omitted, the
pointer state from the previous frame is reused.

=item C<delta_time> (optional, default 0)

Seconds since last frame; passed to C<Clay_EndLayout>.

=back

=head2 widget_for($user_data)

Given the C<userData> integer carried on a render command, returns the
widget object that produced it (or C<undef> if the widget has been
garbage-collected since the last C<render> call, or if C<$user_data> is
falsy or unknown).

	for my $cmd (@$render_commands) {
		my $widget = $ui->widget_for($cmd->{userData});
		next unless $widget;
		# dispatch on ref $widget, read its fields, etc.
	}

=head2 get_hovered

Returns an arrayref of widget objects currently under the pointer (as
reported by C<Clay_GetPointerOverIds>). Widgets that have been
garbage-collected since the last C<render> are skipped.

=head2 get_focused_widget

Returns the widget currently holding focus, or C<undef> if no widget
is focused (or the previously focused widget has been
garbage-collected). The reference is held weakly.

=head2 set_focused_widget($widget)

Sets focus to C<$widget>. Pass C<undef> to clear focus (blur).

Validates loudly:

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

Fires L<Clay::UI::Events::OnBlur> on the previously focused widget
(if any) and L<Clay::UI::Events::OnFocus> on the new one (if any).
Setting focus to the already-focused widget is a no-op (no events
fire).

=head2 focus_next, focus_previous

Move focus to the next / previous focusable widget. Traversal order
is the default depth-first walk of the tree, unless an ancestor of
the currently focused widget composes
L<Clay::UI::Role::Interaction::HasFocusOrder>; in that case the
nearest such ancestor's C<get_next_focus> / C<get_previous_focus> is
called and its return value (if a valid Focusable belonging to this
tree) is used.

Both methods wrap from end to beginning (and vice versa). With no
currently focused widget, C<focus_next> focuses the first widget in
the default chain and C<focus_previous> focuses the last.

=head1 NOTES

The walker auto-injects C<refaddr($widget)> as each element's
C<user_data> so render commands carry a back-reference. A widget's
C<to_config> (or C<text_config>) must therefore NOT set C<user_data>
itself; C<render> dies with a clear message if it sees one already
present.

Registry entries are weak references. The widget tree is kept alive by
the C<root> field on this object, so as long as the C<Clay::UI>
instance is alive, every widget reachable from C<root> stays
resolvable.

=head1 SEE ALSO

L<Clay::UI::Role::Core::Element>, L<Clay::XS>.

=cut
