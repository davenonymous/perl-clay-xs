package Clay::UI::Events::OnPress;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Events::Event;

our $VERSION = '0.01';

class Clay::UI::Events::OnPress :isa(Clay::UI::Events::Event) :strict(params) {
	field $x      :param :reader = 0;
	field $y      :param :reader = 0;
	field $button :param :reader = 1;

	method event_name :common { 'OnPress' }
}

1;

__END__

=head1 NAME

Clay::UI::Events::OnPress - pointer-pressed event

=head1 SYNOPSIS

	$button->on('OnPress', sub ($event) {
		do_thing();
	});

=head1 DESCRIPTION

Fired by L<Clay::UI/render> on the topmost
L<Clay::UI::Role::Interaction::Pressable> widget under the pointer in the
frame the pointer goes down (Clay's C<CLAY_POINTER_DATA_PRESSED_THIS_FRAME>).
Pairs with L<Clay::UI::Events::OnRelease>.

=head1 FIELDS

=over 4

=item C<x>, C<y> (default 0)

Pointer position when the press was registered.

=item C<button> (default 1)

Mouse-button index. Clay's pointer state does not distinguish buttons,
so this is forwarded by callers that do (defaults to C<1> = primary).

=back

C<name> defaults to C<'OnPress'>; C<bubble_mode> defaults to
C<< Clay::UI::Enum::Bubble->IF_CONTINUE >>.

=cut
