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
		die "Clay::UI: widget " . ref($kid) . " has been attached before; no reparenting allowed"
			if $kid->_was_parented;
	}
	return;
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

	ADJUST {
		validate_id('id', $id) if defined $id;
	}

	method children () {
		return [ @_children ];
	}

	method get_children_with ($predicate) {
		return grep { $predicate->($_) } @_children;
	}

	method resolve_id ($base, $indices) {
		return $id if defined $id;
		return 'anon:' . length($base) . ":$base/" . join('/', @$indices);
	}

	method to_config {
		my %config;
		$self->$_(\%config) for @{ _contributors_of(ref $self) };
		return \%config;
	}

	# ---------------------------------------------------------------------
	# Child-list primitives. Every change to the children goes through
	# _splice_children or _detach_children: new children are validated as a
	# whole before anything is written, removed children are detached.
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
		$self->_release_children(@removed);
		return @removed;
	}

	method _detach_children (@kids) {
		my %leaving = map { refaddr($_) => 1 } @kids;
		my @removed = grep { $leaving{ refaddr($_) } } @_children;
		return unless @removed;
		@_children = grep { !$leaving{ refaddr($_) } } @_children;
		$self->_release_children(@removed);
		return;
	}

	# Runs after the child list has changed: tells the interaction tracker
	# (hover and focus inside a leaving subtree are released, with
	# OnHoverStopped / OnBlur bubbling through the still-intact parent
	# slots), then clears each child's parent slot. The
	# children are detached even if an OnBlur listener dies; its error is
	# rethrown once they are.
	method _release_children (@kids) {
		return unless @kids;
		my $ui = $self->ui;
		my $listener_error;
		if (defined $ui) {
			for my $kid (@kids) {
				local $@;
				eval { $ui->interaction->_subtree_detached($kid); 1 }
					or $listener_error //= $@ || 'unknown listener error';
			}
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
that array does not change the widget.

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
alphabetically last one wins. Contributors should put fresh hashes into
the config rather than hashes the widget keeps; the walker may add keys.

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

=head2 get_children_with

	my @foos = $root->get_children_with(sub { $_->id =~ /^foo_/ });
	my @bars = $root->get_children_with(sub { $_[0]->isa('My::Bar') });

Returns the list of direct children for which C<< $predicate->($child) >>
is true. C<$_> is also set to the current child inside the block, so
both calling styles work. Does not recurse into descendants.

=head1 ATTACHING CHILDREN

Every change to the children - through
L<Clay::UI::Role::Core::Container> or L<Clay::UI::Grid> - validates all
new children before anything is changed, so a failed call leaves the
widget as it was. It dies if a child is not a widget
(C<Clay::UI::Role::Core::Element> or C<Clay::UI::Role::Core::TextNode>),
appears twice in the call, is the widget itself or one of its ancestors
(a cycle), is the root of a L<Clay::UI>, or has been attached before
(see L<Clay::UI::Role::Layout::HasParent/NO REPARENTING>).

Removed children are detached: their C<parent> becomes undef and they
are no longer part of the Clay::UI. If the focused widget is inside a
removed subtree, focus is cleared first (the widget gets its
C<OnBlur>). An C<OnBlur> listener that dies does not stop the removal:
the call completes and then dies with the listener's error.

=cut
