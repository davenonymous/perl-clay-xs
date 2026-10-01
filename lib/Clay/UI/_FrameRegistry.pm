package Clay::UI::_FrameRegistry;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(refaddr weaken);

our $VERSION = '0.01';

class Clay::UI::_FrameRegistry :strict(params) {
	# Every widget reference is weak: a widget freed after its frame looks
	# like one the frame never saw.
	field %_by_user_data;   # render-command userData (refaddr) -> widget
	field %_by_element;     # Clay element id -> widget
	field %_rank;           # refaddr -> position in the walk (pre-order)
	field @_scroll;         # [ widget, element id hash ] per scroll container

	# Records a widget that emits render commands; returns the userData
	# value that maps them back to it.
	method add_back_reference ($widget) {
		my $user_data = refaddr $widget;
		$_by_user_data{$user_data} = $widget;
		weaken $_by_user_data{$user_data};
		return $user_data;
	}

	# Records an element widget in walk order, with the element id hash
	# Clay_GetElementId returned for it.
	method add_element ($widget, $element_id) {
		$_by_element{ $element_id->{id} } = $widget;
		weaken $_by_element{ $element_id->{id} };
		$_rank{ refaddr $widget } = scalar keys %_rank;
		if ($widget->DOES('Clay::UI::Role::Layout::HasScroll')) {
			push @_scroll, [ $widget, $element_id ];
			weaken $_scroll[-1][0];
		}
		return;
	}

	method widget_for ($user_data) {
		return $_by_user_data{$user_data};
	}

	method widget_for_element ($id) {
		return $_by_element{$id};
	}

	# Widgets sorted by their position in the walk; widgets the walk did
	# not reach (removed ones) keep their relative order last.
	method in_tree_order (@widgets) {
		my $rank = sub ($widget) { $_rank{ refaddr $widget } // 9**9**9 };
		return map { $_->[1] } sort { $a->[0] <=> $b->[0] } map { [ $rank->($_), $_ ] } @widgets;
	}

	# [ widget, element id hash ] for every scroll container that still
	# exists, in walk order.
	method scroll_containers () {
		return map { [ @$_ ] } grep { defined $_->[0] } @_scroll;
	}
}

1;

__END__

=head1 NAME

Clay::UI::_FrameRegistry - what one Clay::UI frame laid out

=head1 DESCRIPTION

L<Clay::UI> builds one registry per frame while it walks the widget tree
and replaces the previous one only when the frame completes, so a failed
frame leaves the last good registry in place. It answers the questions
the next frame's pointer and scroll handling asks about the last layout:
which widget a render command's C<userData> or a Clay element id
belongs to, where widgets came in the walk, and which scroll containers
were declared under which element id.

Widget references are weak.

This module is internal. The API is not part of the public contract.

=head1 METHODS

=over 4

=item C<add_back_reference($widget)>

Records C<$widget>; returns the C<userData> value for its render
commands.

=item C<add_element($widget, $element_id)>

Records an element widget in walk order under the element id hash from
C<Clay_GetElementId>; a scroll container is also listed by
C<scroll_containers>.

=item C<widget_for($user_data)>, C<widget_for_element($id)>

The widget, or undef.

=item C<in_tree_order(@widgets)>

C<@widgets> sorted by walk position; unknown ones last, in their
original order.

=item C<scroll_containers>

List of C<[ $widget, $element_id ]> for the scroll containers that
still exist, in walk order.

=back

=cut
