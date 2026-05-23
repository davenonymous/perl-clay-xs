package Clay::UI::Role::Layout::HasLayout;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::Layout::HasLayout {
	field $layout :param :accessor = {};

	method contribute_layout ($config) {
		return unless defined $layout && scalar(keys(%$layout)) > 0;
		$config->{layout} = $layout;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Layout::HasLayout - layout config mixin for Clay::UI widgets

=head1 SYNOPSIS

	class My::Box :does(Clay::UI::Role::Core::Element)
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

C<layout> is a read/write accessor: call with no argument to read the
stored hashref, with one argument to replace it. A write takes effect on
the next C<render>.

=cut
