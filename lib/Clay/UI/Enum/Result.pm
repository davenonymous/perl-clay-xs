package Clay::UI::Enum::Result;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Object::PadX::Enum;

our $VERSION = '0.01';

enum Clay::UI::Enum::Result {
	item HANDLED;
	item CONTINUE;
}

1;

__END__

=head1 NAME

Clay::UI::Enum::Result - handler-return-value enum for Clay::UI events

=head1 SYNOPSIS

	use Clay::UI::Enum::Result;

	$widget->on('OnPress', sub ($event) {
		do_thing();
		return Clay::UI::Enum::Result->HANDLED;  # stop bubbling (only matters for IF_CONTINUE)
	});

=head1 DESCRIPTION

Two singleton values handlers may return:

=over 4

=item C<< Clay::UI::Enum::Result->HANDLED >>

Equivalent to returning C<undef> from a handler. In
C<< Clay::UI::Enum::Bubble->IF_CONTINUE >> mode this stops further
propagation. In C<ALWAYS> or C<NEVER> mode the return value is ignored.

=item C<< Clay::UI::Enum::Result->CONTINUE >>

Tells C<IF_CONTINUE> mode to keep walking up the parent chain even
after this handler.

=back

Handlers may also return any other value: it is treated as C<HANDLED>
for the purposes of the C<IF_CONTINUE> check. Only C<CONTINUE> (this
singleton, compared with C<==>) is recognised as "keep going".

=cut
