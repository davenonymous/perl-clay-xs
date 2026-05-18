package Clay::UI::Role::Layout::HasSizingGroup;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::Layout::HasSizingGroup {
	field $width_group  :param :accessor = 0;
	field $height_group :param :accessor = 0;

	method contribute_sizing_group ($config) {
		return if $width_group == 0 && $height_group == 0;
		$config->{sizing_group} = {
			width  => $width_group,
			height => $height_group,
		};
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Layout::HasSizingGroup - cross-tree sizing constraint mixin for Clay::UI widgets

=head1 SYNOPSIS

	# Implicit: composed into Clay::UI::Role::Core::Element, so every widget
	# already accepts width_group / height_group.
	class My::Box :does(Clay::UI::Box) {}

	My::Box->new(
		layout       => { sizing => { width => sizing_fit() } },
		width_group  => 17,
	);

	# Two unrelated widgets aligned to a common width.
	my $a = My::Box->new( ..., width_group => 17 );
	my $b = My::Box->new( ..., width_group => 17 );

=head1 DESCRIPTION

Mixin role composed automatically into every Clay::UI widget (via
L<Clay::UI::Role::Core::Element>) that exposes two integer constraint-group
ids. After Clay's per-axis fit-sizing pass, all elements sharing a
non-zero group id on the same axis are equalized to the per-group max
fit-size before grow distribution. The Clay-side machinery is provided
by a vendored patch (C<patches/0001-clay-sizing-groups.patch>).

The high-level L<Clay::UI::Grid> widget assigns group ids automatically
to its cells. Direct use of this role is for cross-tree alignment cases
that don't fit a grid (form-label widths, equal-height button rows,
etc.).

=head1 FIELDS

=head2 width_group (default 0)

Width-axis group id. C<0> means "no group". Non-zero ids cause this
element's fit-width to be equalized with every other element declaring
the same C<width_group>.

The field is C<:accessor>, so callers (notably L<Clay::UI::Grid>) can
assign the id after construction via C<< $cell->width_group($new_id) >>.

=head2 height_group (default 0)

Height-axis group id, mirror of C<width_group>.

=head1 INTERACTION WITH OTHER SIZING TYPES

=over 4

=item *

C<FIT> and C<GROW> elements participate in group equalization. For
C<GROW>, the equalized max becomes the effective floor before grow
distribution runs.

=item *

C<FIXED> and C<PERCENT> elements are ignored by equalization: their
size is independent of content, so including them in the group max
would be meaningless.

=back

=cut
