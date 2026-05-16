package Clay::UI::Role::HasParent;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(blessed weaken);

our $VERSION = '0.01';

role Clay::UI::Role::HasParent {
	field $parent :reader = undef;

	method _set_parent ($new_parent) {
		die "Clay::UI: parent must be a blessed widget"
			unless blessed $new_parent;
		die "Clay::UI: widget is already parented; no reparenting allowed"
			if defined $parent;
		$parent = $new_parent;
		weaken $parent;
		return;
	}

	method root () {
		my $node = $self;
		while (defined(my $next = $node->parent)) {
			$node = $next;
		}
		return $node;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::HasParent - parent back-reference mixin for Clay::UI widgets

=head1 SYNOPSIS

	# Composed automatically into every Clay::UI widget via
	# Clay::UI::Role::Element and Clay::UI::Role::TextNode.
	my $child = $box->children->[0];
	my $owner = $child->parent;   # the Box
	my $top   = $child->root;     # walks the parent chain to the topmost widget

=head1 DESCRIPTION

Mixin role providing two pieces of upward navigation for Clay::UI
widgets:

=over 4

=item *

A C<parent> reader that returns the widget directly containing this one
(or C<undef> for an unparented widget).

=item *

A C<root> method that walks the parent chain and returns the topmost
ancestor (or C<$self> if this widget has no parent).

=back

The C<parent> slot is a weak reference: it does not keep the parent
alive. The widget tree is held together by parents owning their
C<children> arrayrefs, not by children referring back up.

=head1 NO REPARENTING

B<A widget's parent slot is set exactly once for its lifetime.>
L<Clay::UI::Role::Element/add_child> stamps the parent on each kid the
first time it is attached and dies on any further attempt, including:

=over 4

=item *

Adding the same widget to a different parent.

=item *

Adding the same widget to its existing parent again.

=item *

Re-attaching a widget that was previously removed via C<remove_child>
or C<clear_children>: those mutators do B<not> clear the child's
C<parent> slot.

=back

A detached widget therefore cannot be re-attached anywhere. Build a
fresh widget per mount rather than reusing instances across rebuilds.
This rule keeps the parent contract simple (single-writer, no race
between concurrent attaches, no cache-invalidation surface) at the cost
of forbidding patterns that rely on widget reuse.

=head1 METHODS

=head2 parent

Read-only accessor. Returns the widget that owns this one, or C<undef>
if the widget has never been attached, or if the parent has been
garbage-collected (the back-reference is weak).

=head2 root

Walks C<< $self->parent->parent->... >> until the chain ends and
returns the topmost widget. For an unparented widget returns C<$self>.
If a mid-chain ancestor has been garbage-collected, returns the highest
still-alive ancestor on the surviving prefix of the chain.

Each call walks the chain; the result is not cached. Trees are shallow
enough in practice that the walk cost is negligible.

=cut
