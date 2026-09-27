package Clay::UI::Role::Layout::HasSizingGroup;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::_validate qw(required validate_group_id);

our $VERSION = '0.01';

role Clay::UI::Role::Layout::HasSizingGroup {
	field $width_group  :param = 0;
	field $height_group :param = 0;

	ADJUST {
		$width_group  = required(\&validate_group_id, width_group  => $width_group);
		$height_group = required(\&validate_group_id, height_group => $height_group);
	}

	method width_group (@new) {
		return $width_group unless @new;
		return $width_group = required(\&validate_group_id, width_group => @new);
	}

	method height_group (@new) {
		return $height_group unless @new;
		return $height_group = required(\&validate_group_id, height_group => @new);
	}

	# Clay::UI::Grid stamps its packed (grid id << 20 | index) group ids
	# here; they are outside the range users may set.
	method _set_grid_groups ($width, $height) {
		$width_group  = $width;
		$height_group = $height;
		return;
	}

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

	use Object::Pad;
	use Clay::XS qw(sizing_fit);
	use Clay::UI::Box;

	# Implicit: composed into Clay::UI::Role::Core::Element, so every widget
	# already accepts width_group / height_group.
	class My::Box :strict(params) :does(Clay::UI::Box) {}

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

Width-axis group id: an integer in C<0 .. 2**20 - 1>; C<0> means "no
group". Non-zero ids cause this element's fit-width to be equalized with
every other element declaring the same C<width_group>. Larger ids are
reserved for the ids L<Clay::UI::Grid> assigns; other values die.

Read/write accessor: C<< $widget->width_group >> reads,
C<< $widget->width_group($id) >> writes.

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

=item *

A member never exceeds its own sizing C<max>
(C<< sizing_fit(0, 50) >> stays at most 50 wide even if another member
is wider).

=item *

Groups may nest: a member can contain members of other groups (a grid
inside a grid cell). Equalization repeats until the sizes settle.
Cyclic nesting on one axis is reported as a Clay error
(C<CLAY_ERROR_TYPE_SIZING_GROUP_CYCLE>).

=back

=cut
