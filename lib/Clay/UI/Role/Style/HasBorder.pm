package Clay::UI::Role::Style::HasBorder;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::_validate qw(optional validate_border_width clay_struct);

our $VERSION = '0.01';

role Clay::UI::Role::Style::HasBorder {
	field $border_color :param = undef;
	field $border_width :param = undef;

	ADJUST {
		$border_color = optional(clay_struct('Clay_Color'),        border_color => $border_color);
		$border_width = optional(\&validate_border_width, border_width => $border_width);
	}

	method border_color (@new) {
		return $border_color unless @new;
		return $border_color = optional(clay_struct('Clay_Color'), border_color => @new);
	}

	method border_width (@new) {
		return $border_width unless @new;
		return $border_width = optional(\&validate_border_width, border_width => @new);
	}

	method contribute_border ($config) {
		return unless defined $border_color || defined $border_width;

		my %border;
		$border{color} = $border_color if defined $border_color;

		if (defined $border_width) {
			$border{width} = ref $border_width
				? $border_width
				: { left => $border_width, right => $border_width, top => $border_width, bottom => $border_width, between_children => 0 };
		}

		$config->{border} = \%border;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Style::HasBorder - border mixin for Clay::UI widgets

=head1 SYNOPSIS

	class My::Box :strict(params) :does(Clay::UI::Role::Core::Element)
	              :does(Clay::UI::Role::Style::HasBorder)
	{}

	# Uniform width on all four sides:
	My::Box->new( border_color => [100, 100, 100, 255], border_width => 2 );

	# Per-side widths:
	My::Box->new(
		border_color => [100, 100, 100, 255],
		border_width => { left => 2, right => 2, top => 0, bottom => 0, between_children => 0 },
	);

=head1 DESCRIPTION

Mixin role that contributes a C<border> slice to the Clay element
declaration. C<border_width> accepts either a scalar (applied to all
four sides; C<between_children> is hardcoded to 0 - pass an explicit
hashref if you need to set it) or a hashref with explicit per-side
values.

C<border_color> and C<border_width> are read/write accessors: call with no
argument to read, with one argument to write. A write takes effect on the
next C<render>. Values are validated when set: C<border_color> is a
colour (C<[r, g, b, a]> or C<{ r, g, b, a }>), C<border_width> a number or
a hashref with the keys above; anything else dies.

=cut
