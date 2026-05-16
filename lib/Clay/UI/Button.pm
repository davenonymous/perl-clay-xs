package Clay::UI::Button;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::Layout qw(Clay_OnHover CLAY_POINTER_DATA_PRESSED_THIS_FRAME);

use Clay::UI::Role::Stateful;
use Clay::UI::Role::Hoverable;
use Clay::UI::Role::HasLayout;
use Clay::UI::Role::HasBackground;
use Clay::UI::Role::HasBorder;
use Clay::UI::Role::HasCornerRadius;

our $VERSION = '0.01';

class Clay::UI::Button
	:does(Clay::UI::Role::Stateful)
	:does(Clay::UI::Role::Hoverable)
	:does(Clay::UI::Role::HasLayout)
	:does(Clay::UI::Role::HasBackground)
	:does(Clay::UI::Role::HasBorder)
	:does(Clay::UI::Role::HasCornerRadius)
{
	field $on_click :param :reader = undef;
	field $on_hover :param :reader = undef;

	method install_hover_callback {
		my $click = $on_click;
		my $hover = $on_hover;
		return unless defined $click || defined $hover;

		Clay_OnHover(sub ($id, $pointer, $userdata) {
			$hover->($id, $pointer, $userdata) if defined $hover;
			if (defined $click && $pointer->{state} == CLAY_POINTER_DATA_PRESSED_THIS_FRAME) {
				$click->($id, $pointer, $userdata);
			}
		}, undef);
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Button - clickable widget with hover + press callbacks

=head1 SYNOPSIS

	use Clay::UI::Button;
	use Clay::UI::Text;

	my $btn = Clay::UI::Button->new(
		id               => 'submit-btn',
		layout           => { sizing => { width => sizing_fixed(120), height => sizing_fixed(40) } },
		background_color => [70, 130, 200, 255],
		corner_radius    => 4,
		on_click         => sub ($id, $pointer, $ud) { warn "clicked!" },
		children         => [
			Clay::UI::Text->new( text => 'Submit', text_color => [255, 255, 255, 255] ),
		],
	);

=head1 DESCRIPTION

Stateful container (requires an C<id>) that registers a hover callback
each frame and dispatches to:

=over 4

=item *

C<on_hover> on every frame the pointer is over the element.

=item *

C<on_click> when the pointer state is
C<CLAY_POINTER_DATA_PRESSED_THIS_FRAME> (a fresh press inside the
element).

=back

Per F<AGENTS.md> invariant 6, hover callbacks must be re-registered
every frame; the walker does this automatically because
C<install_hover_callback> is called every time the widget is rendered.

=cut
