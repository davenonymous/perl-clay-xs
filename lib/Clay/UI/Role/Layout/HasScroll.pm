package Clay::UI::Role::Layout::HasScroll;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Core::Stateful;

our $VERSION = '0.01';

role Clay::UI::Role::Layout::HasScroll
	:does(Clay::UI::Role::Core::Stateful)
{
	field $horizontal   :param :reader = 0;
	field $vertical     :param :reader = 1;
	field $child_offset :param :reader = undef;

	method contribute_clip ($config) {
		$config->{clip} = {
			horizontal   => $horizontal,
			vertical     => $vertical,
			child_offset => $child_offset // { x => 0, y => 0 },
		};
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Layout::HasScroll - scrollable-container mixin for Clay::UI widgets

=head1 SYNOPSIS

	class My::LogView :does(Clay::UI::Role::Layout::HasScroll)
	                  :does(Clay::UI::Role::Layout::HasLayout)
	{}

	My::LogView->new(
		id       => 'log',
		vertical => 1,
		layout   => { sizing => { width => sizing_grow(), height => sizing_fixed(300) } },
	);

=head1 DESCRIPTION

Mixin role that turns a widget into a Clay scroll container. Composes
L<Clay::UI::Role::Core::Stateful>: an C<id> is mandatory because Clay
needs a stable address to track scroll state across frames.

Constructor parameters:

=over

=item C<horizontal>

Enable horizontal scrolling. Defaults to C<0>.

=item C<vertical>

Enable vertical scrolling. Defaults to C<1>.

=item C<child_offset>

Initial C<< { x =E<gt> ..., y =E<gt> ... } >> offset. Defaults to
C<< { x =E<gt> 0, y =E<gt> 0 } >>.

=back

=head1 USAGE NOTES

Scroll containers need the caller to drive scroll updates each frame.
After processing input events, call

	Clay::XS::Clay_UpdateScrollContainers($enable_drag_scrolling, $scroll_delta, $delta_time);

and, if you want programmatic scroll-offset queries, install a
C<Clay::XS::Clay_SetQueryScrollOffsetFunction>. The role itself only
contributes the C<clip> config; per-frame scroll plumbing lives on the
caller (see F<AGENTS.md> invariant 3).

=cut
