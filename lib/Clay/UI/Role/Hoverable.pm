package Clay::UI::Role::Hoverable;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::Hoverable {
	method install_hover_callback;
}

1;

__END__

=head1 NAME

Clay::UI::Role::Hoverable - marker role for widgets that register hover callbacks

=head1 DESCRIPTION

Marker role consumed by widgets like L<Clay::UI::Button> that need to
call C<Clay_OnHover> while the element is open. After configuring an
element, the walker checks
C<< $node->DOES('Clay::UI::Role::Hoverable') >> and calls
C<< $node->install_hover_callback >> so the widget can register its
own callback every frame (matching idiomatic Clay usage; see
F<AGENTS.md> invariant 6).

=head1 REQUIRED METHODS

=head2 install_hover_callback

Called by the walker between C<Clay__ConfigureOpenElement> and the
recursion into children. The widget should call
C<Clay::Layout::Clay_OnHover> here.

=cut
