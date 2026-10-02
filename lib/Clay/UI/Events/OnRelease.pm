package Clay::UI::Events::OnRelease;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Events::Event;

our $VERSION = '0.01';

class Clay::UI::Events::OnRelease :isa(Clay::UI::Events::Event) :strict(params) {
	field $x      :param :reader = 0;
	field $y      :param :reader = 0;
	field $button :param :reader = 1;

	method event_name :common { 'OnRelease' }
}

1;

__END__

=head1 NAME

Clay::UI::Events::OnRelease - pointer-released-over-widget event

=head1 SYNOPSIS

	$button->on('OnPress',   sub ($e) { $start = now() });
	$button->on('OnRelease', sub ($e) {
		my $held = now() - $start;
		$held < 0.3 ? short_click() : long_click();
	});

=head1 DESCRIPTION

Fired by L<Clay::UI/render> in the frame the pointer is released
(Clay's C<CLAY_POINTER_DATA_RELEASED_THIS_FRAME>), on the topmost
L<Clay::UI::Role::Interaction::Pressable> widget that is still under the
pointer B<and> on which the press started - a completed click. Pairs
with L<Clay::UI::Events::OnPress>.

A release after the pointer left the widget (press, drag off, release)
fires nothing, and neither does a release over a widget the press did
not start on (press elsewhere, drag in, release).

=head1 FIELDS

=over 4

=item C<x>, C<y> (default 0)

Pointer position when the release was registered.

=item C<button> (default 1)

Mouse-button index. Clay's pointer state does not distinguish buttons,
so this is forwarded by callers that do (defaults to C<1> = primary).

=back

C<name> defaults to C<'OnRelease'>; C<bubble_mode> defaults to
C<< Clay::UI::Enum::Bubble->IF_CONTINUE >>.

=cut
