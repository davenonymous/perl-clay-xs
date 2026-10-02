package Clay::UI::Role::Layout::HasScroll;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::_validate qw(optional required clay_struct clay_field copy_value);
use Clay::UI::Revision qw(bump_revision);
use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Core::Stateful;
use Clay::UI::Role::Events::Emitter;

our $VERSION = '0.01';

role Clay::UI::Role::Layout::HasScroll
	:does(Clay::UI::Role::Core::Stateful)
	:does(Clay::UI::Role::Core::Container)
	:does(Clay::UI::Role::Events::Emitter)
{
	field $horizontal   :param = 0;
	field $vertical     :param = 1;
	field $child_offset :param = undef;

	ADJUST {
		$horizontal   = required(clay_field('Clay_ClipElementConfig', 'horizontal'),    horizontal   => $horizontal);
		$vertical     = required(clay_field('Clay_ClipElementConfig', 'vertical'),    vertical     => $vertical);
		$child_offset = optional(clay_struct('Clay_Vector2'), child_offset => $child_offset);
	}

	method horizontal (@new) {
		return $horizontal unless @new;
		$horizontal = required(clay_field('Clay_ClipElementConfig', 'horizontal'), horizontal => @new);
		bump_revision();
		return $horizontal;
	}

	method vertical (@new) {
		return $vertical unless @new;
		$vertical = required(clay_field('Clay_ClipElementConfig', 'vertical'), vertical => @new);
		bump_revision();
		return $vertical;
	}

	method child_offset (@new) {
		return copy_value($child_offset) unless @new;
		$child_offset = optional(clay_struct('Clay_Vector2'), child_offset => @new);
		bump_revision();
		return copy_value($child_offset);
	}

	method contribute_clip ($config) {
		my %clip = (horizontal => $horizontal, vertical => $vertical);
		$clip{child_offset} = $child_offset if defined $child_offset;
		$config->{clip} = \%clip;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Layout::HasScroll - scrollable-container mixin for Clay::UI widgets

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::XS qw(sizing_grow sizing_fixed);
	use Clay::UI::Role::Layout::HasScroll;
	use Clay::UI::Role::Layout::HasLayout;

	class My::LogView :strict(params) :does(Clay::UI::Role::Layout::HasScroll)
	                  :does(Clay::UI::Role::Layout::HasLayout)
	{}

	My::LogView->new(
		id       => 'log',
		vertical => 1,
		layout   => { sizing => { width => sizing_grow(), height => sizing_fixed(300) } },
	);

=head1 DESCRIPTION

Mixin role that turns a widget into a scroll container. Only a widget
composing this role is one: the walker gives only it Clay's scroll offset,
and only it receives L<Clay::UI::Events::OnScroll>. A widget that writes
a C<clip> slice itself, without this role, is clipped but does not
scroll. Composes
L<Clay::UI::Role::Core::Stateful> (an C<id> is mandatory because Clay
needs a stable address to track scroll state across frames),
L<Clay::UI::Role::Core::Container> (the scrolled content is added with
C<add_child>) and L<Clay::UI::Role::Events::Emitter>.

Constructor parameters, each also a read/write accessor (call with no
argument to read, with one to write; a write takes effect on the next
C<render>; C<child_offset> is copied on write and on read, so changing
the hash afterwards does not change the widget):

=over

=item C<horizontal>

Enable horizontal scrolling. Defaults to C<0>.

=item C<vertical>

Enable vertical scrolling. Defaults to C<1>.

=item C<child_offset>

Undef by default, meaning "Clay-managed": each frame the walker positions
the children at Clay's own scroll offset (C<Clay_GetScrollOffset>), which
L<Clay::UI/render> updates from its C<scroll_delta> and
C<enable_drag_scrolling> arguments (wheel input applies while the pointer
is over the container). Set C<< { x =E<gt> ..., y =E<gt> ... } >> to take
over and position the content yourself; the explicit offset is used as
is. Set it back to undef to return control to Clay.

=back

=head1 USAGE NOTES

Scrolling needs no extra plumbing:

	$ui->render(
		pointer_state => { x => $mx, y => $my, down => $button },
		scroll_delta  => { x => 0, y => $wheel_delta },
	);

C<render> calls C<Clay_UpdateScrollContainers> once per frame; do not
call it yourself between renders: Clay then drops the scroll state of
every container that was not declared since its previous call.

For programmatic scrolling that keeps Clay's momentum and clamping, use
L<Clay::XS/set_scroll_position> with the container's element id
(C<< Clay::XS::Clay_GetElementId($widget-E<gt>id) >>); for full manual
control, set C<child_offset>.

=cut
