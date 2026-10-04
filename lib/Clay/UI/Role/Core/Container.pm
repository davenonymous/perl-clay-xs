package Clay::UI::Role::Core::Container;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Core::Element;

our $VERSION = '0.01';

role Clay::UI::Role::Core::Container :does(Clay::UI::Role::Core::Element) {
	method add_child (@kids) {
		$self->_attach_children(@kids);
		return $self;
	}

	method clear_children () {
		$self->_detach_children(@{ $self->children });
		return $self;
	}

	method remove_child ($target_id) {
		$self->_detach_children(grep {
			$_->DOES('Clay::UI::Role::Core::Element') && defined $_->id && $_->id eq $target_id
		} @{ $self->children });
		return $self;
	}

	method remove_children_with ($predicate) {
		$self->_detach_children(grep { $predicate->($_) } @{ $self->children });
		return $self;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Core::Container - element widget role with public child mutators

=head1 SYNOPSIS

	use v5.22;
	use Object::Pad;
	use Clay::UI::Role::Core::Container;
	use Clay::UI::Text;

	class My::Panel :strict(params) :does(Clay::UI::Role::Core::Container) {}
	class My::Label :strict(params) :does(Clay::UI::Text) {}

	my $panel  = My::Panel->new(id => 'panel');
	my $header = My::Panel->new(id => 'header');
	my $body   = My::Panel->new(id => 'body');

	$panel->add_child($header)->add_child($body, My::Label->new(text => 'footer'));
	$panel->remove_child('body');
	$panel->remove_children_with(sub { $_->isa('My::Label') });
	$panel->clear_children;

=head1 DESCRIPTION

C<Clay::UI::Role::Core::Container> extends
L<Clay::UI::Role::Core::Element> with the public methods that change a
widget's children. L<Clay::UI::Box>, L<Clay::UI::Grid::Cell> and
L<Clay::UI::Role::Layout::HasScroll> compose it. L<Clay::UI::Grid> does
not: a grid's children are its rows, changed through C<append_row> and
the other row methods.

All methods follow L<Clay::UI::Role::Core::Element/ATTACHING CHILDREN>:
new children are checked as a whole before anything changes, every
change bumps the revision (L<Clay::UI::Revision>), and removed children
are detached and can be attached again (see
L<Clay::UI::Role::Layout::HasParent/ATTACHING AND REMOVING>). Changes
show from the next C<render> on. None of these methods see the internal
children of L<Clay::UI::Role::Core::Element/add_internal_children>.

=head1 METHODS

=head2 add_child

	$widget->add_child(@kids);

Appends one or more widgets, in the given order. Each must be a widget
(composing L<Clay::UI::Role::Core::Element> or
L<Clay::UI::Role::Core::TextNode>) without a parent: never attached, or
removed since. Returns the widget, so calls chain:

	$root->add_child($header)->add_child($body, $footer);

Dies, changing nothing, for the cases listed in
L<Clay::UI::Role::Core::Element/ATTACHING CHILDREN>, for example
C<Clay::UI: widget ... is still attached to a parent; remove it first>.

=head2 clear_children

	$widget->clear_children;

Removes and detaches every child. Returns the widget.

=head2 remove_child

	$widget->remove_child($id);

Removes and detaches every direct child whose C<id> equals C<$id>
(string comparison). Children without an id and text widgets are never
matched. An id no child has is ignored. Returns the widget.

=head2 remove_children_with

	$widget->remove_children_with(sub { ($_->id // '') =~ /^tmp-/ });
	$widget->remove_children_with(sub ($child) { $child->isa('My::Row') });

Removes and detaches every direct child for which
C<< $predicate->($child) >> is true. C<$_> is set to the child as well.
Text widgets are passed too; their C<id> is undef.
Returns the widget.

If a removal releases the focused or hovered widget and one of the
resulting C<OnBlur> / C<OnHoverStopped> listeners dies, the removal
still completes and the method then dies with the listener's error
(this applies to all removal methods).

=head1 SEE ALSO

L<Clay::UI::Role::Core::Element>, L<Clay::UI::Box>,
L<Clay::UI::Role::Layout::HasParent>.

=cut
