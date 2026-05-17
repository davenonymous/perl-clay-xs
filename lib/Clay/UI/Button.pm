package Clay::UI::Button;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Core::Stateful;
use Clay::UI::Role::Interaction::Pressable;
use Clay::UI::Role::Layout::HasLayout;
use Clay::UI::Role::Style::HasBackground;
use Clay::UI::Role::Style::HasBorder;
use Clay::UI::Role::Style::HasCornerRadius;

our $VERSION = '0.01';

class Clay::UI::Button
	:does(Clay::UI::Role::Core::Stateful)
	:does(Clay::UI::Role::Interaction::Pressable)
	:does(Clay::UI::Role::Layout::HasLayout)
	:does(Clay::UI::Role::Style::HasBackground)
	:does(Clay::UI::Role::Style::HasBorder)
	:does(Clay::UI::Role::Style::HasCornerRadius)
{}

1;

__END__

=head1 NAME

Clay::UI::Button - clickable, hover-aware widget driven by the event system

=head1 SYNOPSIS

	use Clay::UI::Button;
	use Clay::UI::Text;

	my $btn = Clay::UI::Button->new(
		id               => 'submit-btn',
		layout           => { sizing => { width => sizing_fixed(120), height => sizing_fixed(40) } },
		background_color => [70, 130, 200, 255],
		corner_radius    => 4,
		children         => [
			Clay::UI::Text->new( text => 'Submit', text_color => [255, 255, 255, 255] ),
		],
	);

	$btn->on('OnPress',         sub ($e) { warn "clicked" });
	$btn->on('OnHoverStart',    sub ($e) { ... });
	$btn->on('OnHoverStopped',  sub ($e) { ... });

	# Live state readers (true while pointer is over / pressed):
	if ($btn->is_hovered) { ... }
	if ($btn->is_pressed) { ... }

=head1 DESCRIPTION

A stateful widget combining the visual mixins (layout, background,
border, corner-radius) with the event-driven L<Clay::UI::Role::Interaction::Pressable>
(which itself composes L<Clay::UI::Role::Interaction::Hoverable>). Has no extra
fields of its own: all behaviour comes from the composed roles. To
listen for interaction, register handlers via the event system.

Events fired by the composed roles:

=over 4

=item L<Clay::UI::Events::OnHoverStart>

Edge-triggered: fires once on the frame the pointer enters the button.

=item L<Clay::UI::Events::OnHoverStopped>

Edge-triggered: fires once on the frame the pointer leaves.

=item L<Clay::UI::Events::OnPress>

Edge-triggered: fires once on the frame the pointer becomes pressed
while over the button.

=item L<Clay::UI::Events::OnRelease>

Edge-triggered: fires once on the frame the pointer is released
B<while still over> the button. A release that happens after the
pointer drags off does not fire. Combine with C<OnPress> to implement
whatever click semantics you want (short press, long press,
release-only, etc).

=back

Live state readers C<is_hovered> and C<is_pressed> come from the roles
and reflect the pointer poll most recently processed by C<render>.

Per F<AGENTS.md> invariant 6, hover callbacks must be re-registered
every frame; the walker drives Hoverable's C<install_hover_callback>
automatically each render.

=cut
