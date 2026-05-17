package Clay::UI::Role::Interaction::Hoverable;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::XS qw(Clay_OnHover);

use Clay::UI::Role::Events::Emitter;
use Clay::UI::Events::OnHoverStart;
use Clay::UI::Events::OnHoverStopped;

our $VERSION = '0.01';

role Clay::UI::Role::Interaction::Hoverable :does(Clay::UI::Role::Events::Emitter) {
	field $is_hovered :reader = 0;

	# Set to 1 by the Clay_OnHover trampoline whenever it fires for this
	# widget. Compared against $is_hovered each frame to detect edges.
	field $_seen_over_this_frame = 0;

	# Sub-roles (Pressable, future) push extra per-frame logic in here so
	# the single Clay_OnHover slot per element stays uncontested:
	#   $self->_register_pointer_hook(sub ($pointer, $userdata) { ... });
	#   $self->_register_transition_hook(sub ($was_over_this_frame) { ... });
	field @_pointer_hooks;
	field @_transition_hooks;

	method _register_pointer_hook ($code) {
		die "Hoverable: pointer hook must be a coderef"
			unless ref $code eq 'CODE';
		push @_pointer_hooks, $code;
		return $self;
	}

	method _register_transition_hook ($code) {
		die "Hoverable: transition hook must be a coderef"
			unless ref $code eq 'CODE';
		push @_transition_hooks, $code;
		return $self;
	}

	# Called by the Clay::UI walker once per frame, between
	# Clay__ConfigureOpenElement and the recursion into children.
	#
	# At this point the callback we registered in the PREVIOUS frame has
	# already fired (or not) via Clay_SetPointerState earlier in the same
	# render() call, so $_seen_over_this_frame is the authoritative
	# "pointer was over this widget on the most-recent input poll" flag.
	method install_hover_callback {
		my $was_over = $_seen_over_this_frame;

		if ($was_over && !$is_hovered) {
			$is_hovered = 1;
			$self->fire_event(Clay::UI::Events::OnHoverStart->new);
		} elsif (!$was_over && $is_hovered) {
			$is_hovered = 0;
			$self->fire_event(Clay::UI::Events::OnHoverStopped->new);
		}

		$_->($was_over) for @_transition_hooks;
		$_seen_over_this_frame = 0;

		my @hooks = @_pointer_hooks;
		Clay_OnHover(sub ($id, $pointer, $userdata) {
			$_seen_over_this_frame = 1;
			$_->($pointer, $userdata) for @hooks;
		}, undef);
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Interaction::Hoverable - stateful hover-tracking + edge-triggered events

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Role::Core::Element;
	use Clay::UI::Role::Interaction::Hoverable;

	class My::HoverBox
		:does(Clay::UI::Role::Core::Element)
		:does(Clay::UI::Role::Interaction::Hoverable)
	{}

	my $box = My::HoverBox->new(id => 'tile');
	$box->on('OnHoverStart',   sub ($e) { warn "entered" });
	$box->on('OnHoverStopped', sub ($e) { warn "left" });

	# Later: $box->is_hovered returns the live boolean.

=head1 DESCRIPTION

Real stateful role (no longer a marker). Composing widgets get:

=over 4

=item C<is_hovered> (reader)

Live boolean reflecting whether the pointer was over the widget at the
most recent input poll.

=item C<install_hover_callback>

Method called once per frame by the L<Clay::UI> walker. It detects
hover edges, fires L<Clay::UI::Events::OnHoverStart> /
L<Clay::UI::Events::OnHoverStopped> via the event system, then
re-registers the underlying C<Clay_OnHover> trampoline for the next
frame (per L<AGENTS.md> invariant 6).

=back

Hoverable composes L<Clay::UI::Role::Events::Emitter> transitively, so the
consuming widget gets C<fire_event> for free; just compose Hoverable
and you can both listen for events (every widget can - see
L<Clay::UI::Role::Events::Listener>) and fire your own.

=head1 EXTENSION POINTS

Sub-roles (e.g. L<Clay::UI::Role::Interaction::Pressable>) layer additional pointer
state on top of Hoverable without registering their own C<Clay_OnHover>
(the registry only keeps one entry per element). Two hooks are
available:

=over 4

=item C<_register_pointer_hook($code)>

C<$code> is invoked as C<< $code->($pointer, $userdata) >> from inside
the Clay_OnHover trampoline every frame the pointer is over the
widget.

=item C<_register_transition_hook($code)>

C<$code> is invoked as C<< $code->($was_over_this_frame) >> from
C<install_hover_callback>, after the built-in hover-edge detection but
before the new Clay_OnHover registration. Use this to update derived
state at the frame boundary.

=back

=cut
