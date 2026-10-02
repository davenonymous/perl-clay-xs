package Clay::UI::Revision;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Exporter 'import';

our $VERSION   = '0.01';
our @EXPORT_OK = qw(bump_revision current_revision);

# One counter for the whole process: a renderer only needs to know whether
# anything changed, not what or in which Clay::UI.
my $revision = 0;

sub bump_revision () {
	return ++$revision;
}

sub current_revision () {
	return $revision;
}

1;

__END__

=head1 NAME

Clay::UI::Revision - process-wide "something changed" counter for Clay::UI

=head1 SYNOPSIS

	use Clay::UI::Revision qw(current_revision);

	my $drawn_revision = -1;
	while ($running) {
		handle_input();
		next if current_revision() == $drawn_revision;
		$drawn_revision = current_revision();
		draw($ui->render(%input));
	}

=head1 DESCRIPTION

A non-negative integer that grows whenever something that a frame lays
out or draws has changed. A renderer remembers the value it saw when it
drew its last frame and skips the next frame while the value is still
the same.

Every Clay::UI setter that changes a frame bumps it: widget attributes
(C<layout>, C<background_color>, C<text>, ...), the children of a
widget, user states (C<add_state> and friends), the viewport size and
measure-text callback of a L<Clay::UI>, and the hovered, armed, pressed
and focused widgets of its L<Clay::UI::Interaction>, which drive the
derived C<hovered> / C<pressed> / C<focused> states. Reading an
attribute never bumps it. Widget classes that keep state of their own
call C<< $widget->mark_changed >> (see
L<Clay::UI::Role::Core::Element/mark_changed>) from their setters.

There is one counter for the whole process, shared by every Clay::UI.
A change in any of them makes every renderer draw again; a program with
several UIs that wants to skip more frames compares more than this
value.

Only the value's equality is meaningful: it starts at 0 and only grows,
but how far it grows per change is unspecified (one write may bump it
more than once).

=head1 FUNCTIONS

Nothing is exported by default.

=head2 bump_revision

	my $revision = bump_revision();

Increments the counter and returns the new value.

=head2 current_revision

	my $revision = current_revision();

Returns the counter's current value.

=cut
