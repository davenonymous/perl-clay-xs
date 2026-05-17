package Clay::UI::Events::OnFocus;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Events::Event;

our $VERSION = '0.01';

class Clay::UI::Events::OnFocus :isa(Clay::UI::Events::Event) {
	method event_name :common { 'OnFocus' }
}

1;

__END__

=head1 NAME

Clay::UI::Events::OnFocus - edge-triggered focus-gained event

=head1 SYNOPSIS

	$input->on('OnFocus', sub ($event) {
		warn "focus gained by ", $event->target->id;
	});

=head1 DESCRIPTION

Fired by L<Clay::UI> on the widget that just became the focused
element, immediately after C<< $ui->set_focused_widget >> (directly or
via C<focus_next> / C<focus_previous>) installs it. Pairs with
L<Clay::UI::Events::OnBlur>. Carries no payload beyond the inherited
C<target> / C<current_target>.

C<name> defaults to C<'OnFocus'>; C<bubble_mode> defaults to
C<< Clay::UI::Enum::Bubble->IF_CONTINUE >> (inherited).

=cut
