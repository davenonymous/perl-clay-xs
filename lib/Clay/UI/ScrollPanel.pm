package Clay::UI::ScrollPanel;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Stateful;
use Clay::UI::Role::HasLayout;
use Clay::UI::Role::HasBackground;
use Clay::UI::Role::HasCornerRadius;

our $VERSION = '0.01';

class Clay::UI::ScrollPanel
	:does(Clay::UI::Role::Stateful)
	:does(Clay::UI::Role::HasLayout)
	:does(Clay::UI::Role::HasBackground)
	:does(Clay::UI::Role::HasCornerRadius)
{
	field $horizontal   :param :reader = 0;
	field $vertical     :param :reader = 1;
	field $child_offset :param :reader = undef;

	method contribute_scroll ($config) {
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

Clay::UI::ScrollPanel - scrollable container widget for Clay::UI

=head1 SYNOPSIS

	use Clay::UI::ScrollPanel;

	my $panel = Clay::UI::ScrollPanel->new(
		id         => 'log-view',
		vertical   => 1,
		layout     => { sizing => { width => sizing_grow(), height => sizing_fixed(300) } },
		children   => [ ... ],
	);

=head1 DESCRIPTION

Stateful container (requires an C<id>) that emits a Clay C<clip> config
slice configured for scrolling. Defaults to vertical-only scrolling;
pass C<< horizontal => 1 >> for two-axis or C<< vertical => 0 >> for
horizontal-only.

=head1 USAGE NOTES

Scroll containers need the caller to drive scroll updates each frame.
After processing input events, call

	Clay::XS::Clay_UpdateScrollContainers($enable_drag_scrolling, $scroll_delta, $delta_time);

and, if you want programmatic scroll-offset queries, install a
C<Clay::XS::Clay_SetQueryScrollOffsetFunction>. The widget itself
only contributes the C<clip> config; per-frame scroll plumbing lives
on the caller (see F<AGENTS.md> invariant 3).

=cut
