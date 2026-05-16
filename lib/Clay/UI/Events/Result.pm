package Clay::UI::Events::Result;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Object::PadX::Enum;

our $VERSION = '0.01';

enum Clay::UI::Events::Result {
	item HANDLED;
	item CONTINUE;
}

1;

__END__

=head1 NAME

Clay::UI::Events::Result - handler-return-value enum for Clay::UI events

=head1 SYNOPSIS

	use Clay::UI::Events qw(EVENT_HANDLED EVENT_CONTINUE);

	$widget->on('OnPress', sub ($event) {
		do_thing();
		return EVENT_HANDLED;  # stop bubbling (only matters for BUBBLE_IF_CONTINUE)
	});

=head1 DESCRIPTION

Two singleton values handlers may return:

=over 4

=item C<EVENT_HANDLED>

Equivalent to returning C<undef> from a handler. In
C<BUBBLE_IF_CONTINUE> mode this stops further propagation. In
C<BUBBLE_ALWAYS> or C<BUBBLE_NEVER> mode the return value is ignored.

=item C<EVENT_CONTINUE>

Tells C<BUBBLE_IF_CONTINUE> mode to keep walking up the parent chain
even after this handler.

=back

Handlers may also return any other value: it is treated as
C<EVENT_HANDLED> for the purposes of the IF_CONTINUE check. Only
C<EVENT_CONTINUE> (this singleton, compared with C<==>) is recognised as
"keep going".

=cut
