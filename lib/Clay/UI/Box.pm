package Clay::UI::Box;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Core::Element;
use Clay::UI::Role::Layout::HasLayout;
use Clay::UI::Role::Style::HasBackground;
use Clay::UI::Role::Style::HasBorder;
use Clay::UI::Role::Style::HasCornerRadius;
use Clay::UI::Role::Layout::HasFloating;
use Clay::UI::Role::Events::Emitter;

our $VERSION = '0.01';

role Clay::UI::Box
	:does(Clay::UI::Role::Core::Element)
	:does(Clay::UI::Role::Layout::HasLayout)
	:does(Clay::UI::Role::Style::HasBackground)
	:does(Clay::UI::Role::Style::HasBorder)
	:does(Clay::UI::Role::Style::HasCornerRadius)
	:does(Clay::UI::Role::Layout::HasFloating)
	:does(Clay::UI::Role::Events::Emitter)
{}

1;

__END__

=head1 NAME

Clay::UI::Box - styled container widget role for Clay::UI

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Box;

	class My::Box :does(Clay::UI::Box) {}

	my $box = My::Box->new(
		id               => 'sidebar',
		layout           => { sizing => { width => sizing_fixed(200), height => sizing_grow() } },
		background_color => [40, 50, 60, 255],
		corner_radius    => 6,
		border_color     => [80, 80, 80, 255],
		border_width     => 1,
	);
	$box->add_child($child_widget, $another_child);

=head1 DESCRIPTION

The workhorse styled container role. Composes L<Clay::UI::Role::Core::Element>
with every property mixin: L<HasLayout|Clay::UI::Role::Layout::HasLayout>,
L<HasBackground|Clay::UI::Role::Style::HasBackground>,
L<HasBorder|Clay::UI::Role::Style::HasBorder>,
L<HasCornerRadius|Clay::UI::Role::Style::HasCornerRadius>,
L<HasFloating|Clay::UI::Role::Layout::HasFloating>. A consumer class
gains every mixin parameter on its constructor; the inherited
C<to_config> collects every active slice.

=cut
