package Clay::UI::Role::Layout::HasLayout;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::_validate qw(required clay_struct copy_value);
use Clay::UI::Revision qw(bump_revision);

our $VERSION = '0.01';

role Clay::UI::Role::Layout::HasLayout {
	field $layout :param = {};

	ADJUST {
		$layout = required(clay_struct('Clay_LayoutConfig'), layout => $layout);
	}

	method layout (@new) {
		return copy_value($layout) unless @new;
		$layout = required(clay_struct('Clay_LayoutConfig'), layout => @new);
		bump_revision();
		return copy_value($layout);
	}

	# Merges the user's layout over any slice another contributor wrote
	# (e.g. Clay::UI::Grid's defaults), key by key, into a fresh hash.
	method contribute_layout ($config) {
		return unless defined $layout && scalar(keys(%$layout)) > 0;
		$config->{layout} = { %{ $config->{layout} // {} }, %$layout };
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Layout::HasLayout - layout config mixin for Clay::UI widgets

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::XS qw(sizing_grow CLAY_TOP_TO_BOTTOM);
	use Clay::UI::Role::Core::Element;
	use Clay::UI::Role::Layout::HasLayout;

	class My::Box :strict(params) :does(Clay::UI::Role::Core::Element)
	              :does(Clay::UI::Role::Layout::HasLayout)
	{}

	My::Box->new(
		layout => {
			sizing           => { width => sizing_grow(), height => sizing_grow() },
			padding          => { left => 10, right => 10, top => 5, bottom => 5 },
			child_gap        => 4,
			layout_direction => CLAY_TOP_TO_BOTTOM,
		},
	);

=head1 DESCRIPTION

Mixin role that contributes a C<layout> slice to the Clay element
declaration. Pass any subset of Clay's layout fields; snake_case keys
will be camelized by the walker before reaching the C binding.

C<layout> is a read/write accessor: call with no argument to read a copy
of the stored hashref, with one argument to replace it. The widget keeps its own copy of what was written and every read returns
a fresh copy: changing the passed or returned structure afterwards does
not change the widget (write it back to do that). A write takes effect on
the next C<render>. The value is validated when set: it must be a
hashref using only the keys Clay reads (C<sizing>, C<padding>,
C<child_gap>, C<child_alignment>, C<layout_direction>, C<line_gap>,
C<line_sizing>, in snake_case or
camelCase) with values of the right shape - for example C<padding> is a
hashref (C<padding_all(N)> builds one); anything else dies, naming the
key.

The contributed slice is a fresh hash merged over any C<layout> slice
another contributor wrote (L<Clay::UI::Grid> supplies defaults this way),
so keys you set win one by one.

=cut
