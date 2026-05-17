package Clay::UI::Enum::Bubble;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Object::PadX::Enum;

our $VERSION = '0.01';

enum Clay::UI::Enum::Bubble {
	item ALWAYS;
	item IF_CONTINUE;
	item NEVER;
}

1;

__END__

=head1 NAME

Clay::UI::Enum::Bubble - bubble-policy enum for Clay::UI events

=head1 SYNOPSIS

	use Clay::UI::Enum::Bubble;

	my $event = Clay::UI::Events::OnPress->new(
		bubble_mode => Clay::UI::Enum::Bubble->IF_CONTINUE,
	);

=head1 DESCRIPTION

Singleton-bearing enum (built with L<Object::PadX::Enum>) carrying the
three bubble policies a Clay::UI event can use:

=over 4

=item C<Clay::UI::Enum::Bubble->ALWAYS>

Bubble up to every ancestor unconditionally, ignoring handler return
values.

=item C<Clay::UI::Enum::Bubble->IF_CONTINUE>

After all handlers at the current node have fired (in registration
order), bubble to the parent only if every one of them returned
C<Clay::UI::Enum::Result->CONTINUE>. A single handler returning
C<undef>, C<Clay::UI::Enum::Result->HANDLED>, or any unrelated value
halts propagation B<after> the current node finishes - sibling handlers
at the same node still all run; the stop decision is per-node, not
per-handler.

=item C<Clay::UI::Enum::Bubble->NEVER>

Fire on the originating widget only. Ancestors never see the event.

=back

Comparison uses ordinary object identity (C<==>).

=cut
