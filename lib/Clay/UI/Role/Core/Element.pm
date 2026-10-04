package Clay::UI::Role::Core::Element;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Object::Pad::MOP::Class;
use List::Util qw(uniq);
use Scalar::Util qw(blessed refaddr);
no warnings 'experimental';

use Clay::UI::_validate qw(validate_id);
use Clay::UI::Revision qw(bump_revision);
use Clay::UI::Role::Layout::HasSizingGroup;
use Clay::UI::Role::Layout::HasParent;
use Clay::UI::Role::Events::Listener;

our $VERSION = '0.01';

# Contributor method names per class. Object::Pad classes are sealed once
# compiled, so the list never changes after the first lookup.
my %contributors_for;

sub _contributors_of ($class) {
	return $contributors_for{$class} //= [
		sort { $a cmp $b }
		uniq
		grep { /^contribute_/ }
		map  { $_->name }
		Object::Pad::MOP::Class->for_class($class)->all_methods
	];
}

sub _is_widget ($thing) {
	return blessed($thing)
		&& ( $thing->DOES('Clay::UI::Role::Core::Element')
		  || $thing->DOES('Clay::UI::Role::Core::TextNode') );
}

# Validates widgets that are about to be attached somewhere below $anchor
# (the future parent, or the Grid they end up in). Dies before anything is
# written if any of them cannot be attached.
sub _validate_attachment ($anchor, @kids) {
	my %ancestor = map { refaddr($_) => 1 } _self_and_ancestors($anchor);
	my %seen;
	for my $kid (@kids) {
		die "Clay::UI: child is not a widget (got " . (ref($kid) || 'non-ref') . ")"
			unless _is_widget($kid);
		my $addr = refaddr($kid);
		die "Clay::UI: the same widget (" . ref($kid) . ") is attached twice in one call"
			if $seen{$addr}++;
		die "Clay::UI: cannot attach a widget to itself or to one of its descendants (" . ref($kid) . ")"
			if $ancestor{$addr};
		die "Clay::UI: widget " . ref($kid) . " is the root of a Clay::UI and cannot become a child"
			if defined $kid->_local_ui_controller;
		die "Clay::UI: widget " . ref($kid) . " is still attached to a parent; remove it first"
			if defined $kid->parent;
	}
	return;
}

# True when $order is an array reference holding each of 0..$count-1
# exactly once.
sub _is_permutation ($order, $count) {
	return 0 unless ref $order eq 'ARRAY' && @$order == $count;
	my %seen;
	for my $index (@$order) {
		return 0 unless defined $index && !ref $index && $index =~ /\A[0-9]+\z/ && $index < $count && !$seen{$index}++;
	}
	return 1;
}

sub _self_and_ancestors ($node) {
	my @chain;
	for (my $cursor = $node; defined $cursor; $cursor = $cursor->parent) {
		push @chain, $cursor;
	}
	return @chain;
}

role Clay::UI::Role::Core::Element :does(Clay::UI::Role::Layout::HasSizingGroup)
                              :does(Clay::UI::Role::Layout::HasParent)
                              :does(Clay::UI::Role::Events::Listener) {
	field $id :param :reader = undef;
	field @_children;
	field @_internal_children;

	ADJUST {
		validate_id('id', $id) if defined $id;
	}

	method children () {
		return [ @_children ];
	}

	method get_children_with ($predicate) {
		return grep { $predicate->($_) } @_children;
	}

	method internal_children () {
		return [ @_internal_children ];
	}

	# What a frame lays out below this widget: the children, then the
	# internal children. The walker, the focus order and the frame
	# registry read this list, never children.
	method layout_children () {
		return [ @_children, @_internal_children ];
	}

	# Internal children belong to the widget class, not to its user: a
	# helper the widget needs in the laid-out tree (a floating scrollbar,
	# a popup) that children and the Container mutators never show or
	# touch. They are validated and parent-stamped like children.
	method add_internal_children (@kids) {
		_validate_attachment($self, @kids);
		push @_internal_children, @kids;
		$_->_set_parent($self) for @kids;
		bump_revision();
		return $self;
	}

	method remove_internal_children (@kids) {
		my %leaving = map { refaddr($_) => 1 } @kids;
		my @removed = grep { $leaving{ refaddr($_) } } @_internal_children;
		return $self unless @removed;
		@_internal_children = grep { !$leaving{ refaddr($_) } } @_internal_children;
		bump_revision();
		$self->_release_children(@removed);
		return $self;
	}

	method resolve_id ($base, $indices) {
		return $id if defined $id;
		return 'anon:' . length($base) . ":$base/" . join('/', @$indices);
	}

	# The slices are fresh; the values in them may be the widget's own.
	method to_config {
		my %config;
		$self->$_(\%config) for @{ _contributors_of(ref $self) };
		return \%config;
	}

	# For widget classes that keep state of their own: call from their
	# setters so renderers see the change (see Clay::UI::Revision).
	method mark_changed () {
		bump_revision();
		return $self;
	}

	# ---------------------------------------------------------------------
	# Child-list primitives. Every change to the children goes through
	# _splice_children or _detach_children: new children are validated as a
	# whole before anything is written, removed children are detached, and
	# the revision (Clay::UI::Revision) is bumped.
	# Clay::UI::Role::Core::Container and Clay::UI::Grid build their public
	# mutators on these.
	# ---------------------------------------------------------------------

	method _attach_children (@kids) {
		$self->_splice_children(scalar @_children, 0, @kids);
		return;
	}

	method _splice_children ($offset, $length, @kids) {
		die "Clay::UI: child offset $offset out of range 0.." . scalar(@_children)
			unless $offset >= 0 && $offset <= @_children;
		die "Clay::UI: cannot remove $length children at offset $offset of " . scalar(@_children)
			unless $length >= 0 && $offset + $length <= @_children;
		_validate_attachment($self, @kids);

		my @removed = splice @_children, $offset, $length, @kids;
		$_->_set_parent($self) for @kids;
		bump_revision();
		$self->_release_children(@removed);
		return @removed;
	}

	# Puts the children in a new order without detaching any: child $k
	# becomes the child that was at $order->[$k]. $order must hold every
	# index exactly once.
	method _reorder_children ($order) {
		my $count = scalar @_children;
		die "Clay::UI: a new child order must be an array reference of the indices 0.." . ($count - 1) . " in any order"
			unless _is_permutation($order, $count);
		@_children = @_children[@$order];
		bump_revision();
		return;
	}

	method _detach_children (@kids) {
		my %leaving = map { refaddr($_) => 1 } @kids;
		my @removed = grep { $leaving{ refaddr($_) } } @_children;
		return unless @removed;
		@_children = grep { !$leaving{ refaddr($_) } } @_children;
		bump_revision();
		$self->_release_children(@removed);
		return;
	}

	# Runs after the child list has changed: tells the interaction tracker
	# (hover and focus inside the leaving subtrees are released, with
	# OnHoverStopped / OnBlur bubbling through the still-intact parent
	# slots), then clears each child's parent slot. The
	# children are detached even if a listener dies; its error is
	# rethrown once they are.
	method _release_children (@kids) {
		return unless @kids;
		my $ui = $self->ui;
		my $listener_error;
		if (defined $ui) {
			local $@;
			eval { $ui->interaction->release_subtrees(@kids); 1 }
				or $listener_error = $@ || 'unknown listener error';
		}
		$_->_detach_parent for @kids;
		die $listener_error if defined $listener_error;
		return;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Core::Element - base role for high-level Clay widget nodes

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Role::Core::Container;
	use Clay::UI::Role::Style::HasBackground;

	class My::Widget :strict(params) :does(Clay::UI::Role::Core::Container)
	                 :does(Clay::UI::Role::Style::HasBackground)
	{
		# to_config comes from Element; it collects every contribute_*
		# method from the composed roles automatically.
	}

	my $tree = My::Widget->new(
		id               => 'my-root',
		background_color => [255, 0, 0, 255],
	);
	$tree->add_child(My::Widget->new(background_color => [0, 0, 255, 255]));

=head1 DESCRIPTION

Object::Pad role consumed by every L<Clay::UI> element widget. Provides
what the walker needs - an optional C<id>, the C<children> list and a
C<to_config> that auto-discovers contribution methods from the composed
mixin roles (see L<Clay::UI::Role::Layout::HasLayout>,
L<Clay::UI::Role::Style::HasBackground>, ...) - but no public way to
change the children. Widgets that hold arbitrary children compose
L<Clay::UI::Role::Core::Container>, which adds C<add_child> and the
removal methods; widgets that manage their children themselves (like
L<Clay::UI::Grid>) compose Element only and use the internal child-list
primitives.

Widgets are constructed empty; the constructor does not take children.

=head1 FIELDS

=head2 id (optional)

If set, a non-empty string used verbatim as the Clay element id. If
omitted, the walker derives an id from the tree position via
L</resolve_id>. Ids starting with C<anon:> are reserved for those
derived ids; the constructor dies for a user id that starts with it.

=head2 children

Returns a new arrayref holding the direct children, in order. Changing
that array does not change the widget. Internal children (see
L</add_internal_children>) are not in it.

=head2 internal_children

Returns a new arrayref holding the internal children, in order.

=head2 layout_children

Returns a new arrayref holding the children followed by the internal
children: everything a frame lays out directly below this widget. The
walker, the focus order of L<Clay::UI::Interaction> and the frame
registry read this list; C<children> is only for the widget's user.

=head1 METHODS

=head2 to_config

Collects every method whose name begins with C<contribute_> - from the
composed roles, the class itself and its superclasses - and calls each
exactly once as C<< $self->$name(\%config) >>, in alphabetical order of
the method names, so each contributor writes its own slice into the
configuration hash. Returns the assembled hashref. The list of
contributors is looked up once per class and cached (Object::Pad classes
are sealed).

Contributors must not depend on running before or after one another: a
contributor that adds to a slice another one may also write merges into
it (as L<Clay::UI::Role::Layout::HasLayout> and L<Clay::UI::Grid> do for
C<layout>). If two unrelated contributors write the same key, the
alphabetically last one wins. Contributors build each slice as a fresh
hash; the values inside it may be the widget's own (the copies its
accessors made when they were set), so treat the returned config as
read-only and copy what you want to change. The walker works on a
camelized copy of it.

Widgets normally do not override C<to_config>; they declare fields and
let the mixins contribute their slices. Override C<to_config> only when
you intend to bypass the mixin pipeline entirely - Object::Pad roles
have no C<SUPER>, so an override loses every C<contribute_*> call.

=head2 resolve_id

	my $id = $widget->resolve_id($base, \@indices);

Returns the user-supplied id if set. Otherwise returns an id derived
from the widget's position: C<$base> is the id of the nearest ancestor
with a user id (C<''> if none) and C<@indices> the child indices from
that ancestor down, giving
C<"anon:" . length($base) . ":$base/" . join('/', @indices)>. Ids grow
linearly with depth; the length prefix keeps anonymous ids distinct from
each other, and the reserved C<anon:> prefix keeps them distinct from
user ids. The walker passes the arguments and
hashes the result with C<Clay_GetElementId>.

=head2 mark_changed

	$widget->mark_changed;

Bumps the process-wide revision (L<Clay::UI::Revision>) and returns
C<$self>. The setters of Clay::UI's roles bump it themselves; a widget
class that keeps state of its own, which its C<contribute_*> methods
turn into the config, calls C<mark_changed> from its setters so that
renderers skipping unchanged frames see the change.

Adding or removing children (L<Clay::UI::Role::Core::Container>,
L<Clay::UI::Grid>) bumps the revision as well.

=head2 get_children_with

	my @foos = $root->get_children_with(sub { $_->id =~ /^foo_/ });
	my @bars = $root->get_children_with(sub { $_[0]->isa('My::Bar') });

Returns the list of direct children for which C<< $predicate->($child) >>
is true. C<$_> is also set to the current child inside the block, so
both calling styles work. Does not recurse into descendants.

=head2 add_internal_children

	$self->add_internal_children($gutter);

For widget classes: attaches widgets that the class needs in the
laid-out tree but that are not its user's content, such as a floating
scrollbar over a scroll container. They are validated and
parent-stamped like children (see L</ATTACHING CHILDREN>), laid out
after the children, and reach the UI through C<ui> like any child;
C<children>, C<get_children_with> and the mutators of
L<Clay::UI::Role::Core::Container> never show or remove them. Bumps the
revision and returns the widget.

=head2 remove_internal_children

	$self->remove_internal_children($gutter);

Detaches the given internal children like removed children (their
C<parent> becomes undef, their interaction state is released); widgets
that are not internal children of this widget are ignored. Bumps the
revision when something was removed and returns the widget.

=head1 ATTACHING CHILDREN

Every change to the children - through
L<Clay::UI::Role::Core::Container>, L<Clay::UI::Grid> or
L</add_internal_children> - validates all
new children before anything is changed, so a failed call leaves the
widget as it was. It dies if a child is not a widget
(C<Clay::UI::Role::Core::Element> or C<Clay::UI::Role::Core::TextNode>),
appears twice in the call, is the widget itself or one of its ancestors
(a cycle), is the root of a L<Clay::UI>, or is still attached to a
parent (see L<Clay::UI::Role::Layout::HasParent/ATTACHING AND REMOVING>).

Widgets that manage their children themselves may also reorder them
(L<Clay::UI::Grid/reorder_rows>); no child is detached by that.

Removed children are detached: their C<parent> becomes undef and they
are no longer part of the Clay::UI, until they are attached again. If the focused widget is inside a
removed subtree, focus is cleared first (the widget gets its
C<OnBlur>). An C<OnBlur> listener that dies does not stop the removal:
the call completes and then dies with the listener's error.

=cut
