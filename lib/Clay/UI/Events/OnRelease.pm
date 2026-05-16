package Clay::UI::Events::OnRelease;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Events::Event;

our $VERSION = '0.01';

class Clay::UI::Events::OnRelease :isa(Clay::UI::Events::Event) {
	field $x        :param :reader = 0;
	field $y        :param :reader = 0;
	field $button   :param :reader = 1;
	field $userdata :param :reader = undef;

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

Fired by L<Clay::UI::Role::Pressable> on the frame the pointer
transitions from pressed to released B<while still over the widget>
(Clay's C<CLAY_POINTER_DATA_RELEASED_THIS_FRAME>). Pairs with
L<Clay::UI::Events::OnPress>.

A release that happens after the pointer leaves the widget does B<not>
fire this event - the underlying C<Clay_OnHover> callback only runs
while the pointer is over the element. Use this asymmetry to implement
click-cancel behavior (drag off, release: no OnRelease).

=head1 FIELDS

=over 4

=item C<x>, C<y> (default 0)

Pointer position when the release was registered.

=item C<button> (default 1)

Mouse-button index. Clay's pointer state does not distinguish buttons,
so this is forwarded by callers that do (defaults to C<1> = primary).

=item C<userdata> (default undef)

Opaque payload forwarded from the originating callback.

=back

C<name> defaults to C<'OnRelease'>; C<bubble_mode> defaults to
C<BUBBLE_IF_CONTINUE>.

=cut
