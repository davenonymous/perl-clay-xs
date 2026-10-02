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

Clay::UI::Role::Core::Container - Element role with public child mutators

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Role::Core::Container;

	class My::Panel :strict(params) :does(Clay::UI::Role::Core::Container) {}

	my $panel = My::Panel->new(id => 'panel');
	$panel->add_child($header)->add_child($body, $footer);
	$panel->remove_child('body');

=head1 DESCRIPTION

Extends L<Clay::UI::Role::Core::Element> with the public methods that
change a widget's children. Composed by L<Clay::UI::Box>,
L<Clay::UI::Grid::Cell> and L<Clay::UI::Role::Layout::HasScroll>.
L<Clay::UI::Grid> does not compose it: a grid's children are its rows,
managed through C<append_row> and friends.

All mutators follow the rules in
L<Clay::UI::Role::Core::Element/ATTACHING CHILDREN>: new children are
validated as a whole before anything changes, and removed children are
detached; they can be attached again (see
L<Clay::UI::Role::Layout::HasParent/ATTACHING AND REMOVING>).

=head1 METHODS

=head2 add_child

	$widget->add_child(@kids);

Appends one or more widgets. Each must be a blessed instance consuming
C<Clay::UI::Role::Core::Element> or C<Clay::UI::Role::Core::TextNode>
that has no parent (never attached, or removed since); see
L<Clay::UI::Role::Core::Element/ATTACHING CHILDREN> for everything that
dies. Returns C<$self> so calls chain:

	$root->add_child($header)->add_child($body, $footer);

=head2 clear_children

Removes and detaches every child. Returns C<$self>.

=head2 remove_child

	$widget->remove_child($id);

Removes and detaches every direct child whose C<id> equals C<$id>. Text
nodes have no id and are never removed. Unknown ids are silently
ignored. Returns C<$self>.

=head2 remove_children_with

	$widget->remove_children_with(sub { $_->id =~ /^tmp-/ });

Removes and detaches every direct child for which
C<< $predicate->($child) >> is true. C<$_> is also bound to the current
child inside the block. Returns C<$self>.

=cut
