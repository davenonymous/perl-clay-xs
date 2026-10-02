package Clay::UI::Role::Layout::HasParent;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Scalar::Util qw(blessed weaken);

our $VERSION = '0.01';

role Clay::UI::Role::Layout::HasParent {
	field $parent :reader = undef;
	field $_ui_controller = undef;

	method _set_parent ($new_parent) {
		die "Clay::UI: parent must be a blessed widget"
			unless blessed $new_parent;
		die "Clay::UI: widget " . ref($self) . " is still attached to a parent; remove it first"
			if defined $parent;
		$parent = $new_parent;
		weaken $parent;
		return;
	}

	# Clears the parent slot when the widget is removed from its parent; the
	# widget can then be attached again.
	method _detach_parent () {
		$parent = undef;
		return;
	}

	method root () {
		my $node = $self;
		while (defined(my $next = $node->parent)) {
			$node = $next;
		}
		return $node;
	}

	method _set_ui_controller ($ui) {
		die "Clay::UI: ui controller must be a Clay::UI instance"
			unless blessed($ui) && $ui->isa('Clay::UI');
		die "Clay::UI: widget already bound to a Clay::UI controller"
			if defined $_ui_controller;
		$_ui_controller = $ui;
		weaken $_ui_controller;
		return;
	}

	method _local_ui_controller () { $_ui_controller }

	method ui () {
		my $top = $self->root;
		return $top->_local_ui_controller;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Layout::HasParent - parent back-reference mixin for Clay::UI widgets

=head1 SYNOPSIS

	# Composed automatically into every Clay::UI widget via
	# Clay::UI::Role::Core::Element and Clay::UI::Role::Core::TextNode.
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

=head1 ATTACHING AND REMOVING

B<A widget can be attached whenever it has no parent.> Attaching (for
example L<Clay::UI::Role::Core::Container/add_child>) stamps the parent;
attaching a widget that still has one dies with "is still attached to a
parent; remove it first", whether the new parent is another widget or
the same one again.

Removing a widget (C<remove_child>, C<remove_children_with>,
C<clear_children>, a Grid row removal or replacement) detaches it: its
C<parent> becomes undef, it becomes the C<root> of its own subtree, and
C<ui> returns undef for that subtree. Its hover, press and focus state
is released on the way out, so it is idle when it comes back. A detached
widget, like one whose parent has been garbage-collected, can be
attached again, to its old parent or any other, or become the root of a
L<Clay::UI>. Once attached it renders and receives pointer events like
any other widget, from the next frame on; without a user C<id> it gets
the id derived from its new position.

=head1 METHODS

=head1 METHODS

=head2 parent

Read-only accessor. Returns the widget that owns this one, or C<undef>
if the widget has never been attached, has been removed from its
parent, or its parent has been garbage-collected (the back-reference is
weak).

=head2 root

Walks C<< $self->parent->parent->... >> until the chain ends and
returns the topmost widget. For an unparented widget returns C<$self>.
If a mid-chain ancestor has been garbage-collected, returns the highest
still-alive ancestor on the surviving prefix of the chain.

Each call walks the chain; the result is not cached. Trees are shallow
enough in practice that the walk cost is negligible.

=head2 ui

Returns the L<Clay::UI> controller that owns this widget's tree, or
C<undef> if the widget is not attached to a Clay::UI (not yet, or no
longer: a removed subtree has no controller). Walks up to the root
widget and returns the controller stamped there by
C<< Clay::UI->new(root => $root) >>.

The Clay::UI back-reference is held weakly; if the controller has been
garbage-collected, C<ui> returns C<undef>.

=cut
