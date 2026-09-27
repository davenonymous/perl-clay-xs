package Clay::UI::Box;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Layout::HasLayout;
use Clay::UI::Role::Style::HasBackground;
use Clay::UI::Role::Style::HasBorder;
use Clay::UI::Role::Style::HasCornerRadius;
use Clay::UI::Role::Layout::HasFloating;
use Clay::UI::Role::Events::Emitter;

our $VERSION = '0.01';

role Clay::UI::Box
	:does(Clay::UI::Role::Core::Container)
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
	use Clay::XS qw(sizing_fixed sizing_grow);
	use Clay::UI::Box;

	class My::Box :strict(params) :does(Clay::UI::Box) {}

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

The workhorse styled container role. Composes
L<Clay::UI::Role::Core::Container> (children via C<add_child> and the
removal methods) and L<Clay::UI::Role::Events::Emitter> (C<fire_event>)
with every property mixin: L<HasLayout|Clay::UI::Role::Layout::HasLayout>,
L<HasBackground|Clay::UI::Role::Style::HasBackground>,
L<HasBorder|Clay::UI::Role::Style::HasBorder>,
L<HasCornerRadius|Clay::UI::Role::Style::HasCornerRadius>,
L<HasFloating|Clay::UI::Role::Layout::HasFloating>. A consumer class
gains every mixin parameter on its constructor; the inherited
C<to_config> collects every active slice.

Every mixin attribute (C<layout>, C<background_color>, C<border_color>,
C<border_width>, C<corner_radius>, C<floating>) is a read/write accessor,
so a box's styling and layout can be changed after construction; the
change is picked up on the next C<render>. Values are validated when
they are set, at construction or through the accessor: a wrong type or
an unknown key dies there, naming the attribute.

Consumer classes should be declared C<:strict(params)> so a misspelled
constructor parameter dies instead of being ignored:

	class My::Box :strict(params) :does(Clay::UI::Box) {}

=cut
