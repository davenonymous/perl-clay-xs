package Clay::UI::Role::Style::HasBackground;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::_validate qw(optional clay_struct);

our $VERSION = '0.01';

role Clay::UI::Role::Style::HasBackground {
	field $background_color :param = undef;

	ADJUST {
		$background_color = optional(clay_struct('Clay_Color'), background_color => $background_color);
	}

	method background_color (@new) {
		return $background_color unless @new;
		return $background_color = optional(clay_struct('Clay_Color'), background_color => @new);
	}

	method contribute_background ($config) {
		return unless defined $background_color;
		$config->{background_color} = $background_color;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Style::HasBackground - background-color mixin for Clay::UI widgets

=head1 SYNOPSIS

	class My::Box :strict(params) :does(Clay::UI::Role::Core::Element)
	              :does(Clay::UI::Role::Style::HasBackground)
	{}

	My::Box->new( background_color => [40, 50, 60, 255] );

=head1 DESCRIPTION

Mixin role that contributes a C<backgroundColor> slice to the Clay
element declaration. Value is an arrayref of four 0-255 channel values
C<[r, g, b, a]> or a hashref with C<r>, C<g>, C<b>, C<a>; any other value
dies when set (at construction or through the accessor).

C<background_color> is a read/write accessor: C<< $widget->background_color >>
reads, C<< $widget->background_color([r, g, b, a]) >> writes. A write takes
effect on the next C<render>.

=cut
