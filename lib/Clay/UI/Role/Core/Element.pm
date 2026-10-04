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
use Clay::UI::_error qw(croak_ui);

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
		croak_ui "Clay::UI: child is not a widget (got " . (ref($kid) || 'non-ref') . ")"
			unless _is_widget($kid);
		my $addr = refaddr($kid);
		croak_ui "Clay::UI: the same widget (" . ref($kid) . ") is attached twice in one call"
			if $seen{$addr}++;
		croak_ui "Clay::UI: cannot attach a widget to itself or to one of its descendants (" . ref($kid) . ")"
			if $ancestor{$addr};
		croak_ui "Clay::UI: widget " . ref($kid) . " is the root of a Clay::UI and cannot become a child"
			if defined $kid->_local_ui_controller;
		croak_ui "Clay::UI: widget " . ref($kid) . " is still attached to a parent; remove it first"
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
		return $self unless @kids;
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
		croak_ui "Clay::UI: child offset $offset out of range 0.." . scalar(@_children)
			unless $offset >= 0 && $offset <= @_children;
		croak_ui "Clay::UI: cannot remove $length children at offset $offset of " . scalar(@_children)
			unless $length >= 0 && $offset + $length <= @_children;
		_validate_attachment($self, @kids);
		return () if !@kids && !$length;    # nothing changes, so no revision bump

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
		croak_ui "Clay::UI: a new child order must be an array reference of the indices 0.." . ($count - 1) . " in any order"
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

Clay::UI::Role::Core::Element - base role of every Clay::UI element widget

=head1 SYNOPSIS

	use v5.22;
	use Object::Pad;
	use Clay::XS qw(sizing_fixed);
	use Clay::UI;
	use Clay::UI::Role::Core::Container;
	use Clay::UI::Role::Layout::HasLayout;
	use Clay::UI::Role::Style::HasBackground;

	class My::Panel :strict(params)
		:does(Clay::UI::Role::Core::Container)
		:does(Clay::UI::Role::Layout::HasLayout)
		:does(Clay::UI::Role::Style::HasBackground)
	{}

	my $root = My::Panel->new(
		id     => 'root',
		layout => {
			sizing => { width => sizing_fixed(200), height => sizing_fixed(100) },
		},
		background_color => [255, 0, 0, 255],
	);
	$root->add_child(My::Panel->new(background_color => [0, 0, 255, 255]));

	# The declaration the layout pass sends to Clay for this widget:
	my $config = $root->to_config;
	# { layout => { sizing => ... }, background_color => [255, 0, 0, 255] }

	my $ui       = Clay::UI->new(width => 800, height => 600, root => $root);
	my $commands = $ui->render;

=head1 DESCRIPTION

C<Clay::UI::Role::Core::Element> is the Object::Pad role every element
widget composes, directly or through another role. An element widget
becomes one Clay element (a box) in each frame. Text widgets are the
other kind of widget; they compose L<Clay::UI::Role::Core::TextNode>
instead.

The role provides:

=over 4

=item *

an optional C<id> (L</id>) and the id Clay::UI derives for widgets
without one (L</resolve_id>);

=item *

the list of children (L</children>) and of internal children
(L</internal_children>), with read access only;

=item *

C<to_config> (L</to_config>), which builds the widget's declaration
from the C<contribute_*> methods of its roles (see
L</EXTENDING THE DECLARATION>);

=item *

C<mark_changed> (L</mark_changed>) for widget classes that keep state of
their own.

=back

It also composes L<Clay::UI::Role::Layout::HasSizingGroup> (the
C<width_group> and C<height_group> attributes),
L<Clay::UI::Role::Layout::HasParent> (C<parent>, C<root>, C<ui>) and
L<Clay::UI::Role::Events::Listener> (C<on>).

Element has no public method that changes the children. Widgets that
hold any children their user gives them compose
L<Clay::UI::Role::Core::Container>, which adds C<add_child> and the
removal methods. Widgets that decide their children themselves (such as
L<Clay::UI::Grid>) compose Element alone and use the internal
child-list methods. The constructor never takes children: a widget
starts empty.

Two terms used below:

=over 4

=item declaration

The hash of settings Clay receives for one element: C<layout>,
C<background_color>, C<border>, C<floating> and so on (see
L<Clay::XS::Structs>). Clay::UI widgets build it with snake_case keys;
the layout pass converts the keys to Clay's camelCase.

=item layout pass

The part of L<Clay::UI/render> that declares the widget tree to Clay:
for every widget it calls C<to_config> (or C<text_config> for a text
widget), opens the Clay element, configures it and walks the children.

=back

=head1 CONSTRUCTOR PARAMETERS

=head2 id

	my $panel = My::Panel->new(id => 'sidebar');
	my $name  = $panel->id;    # 'sidebar', or undef

The element id of the widget: a non-empty string, used as the Clay
element id (C<Clay_GetElementId($id)> gives the same numeric id the
layout pass uses). Optional; without it the layout pass derives an id
from the widget's position (see L</resolve_id>).

The C<id> reader is read-only: an id is set at construction and never
changes.

An undef C<id> means "no id". The constructor dies with
C<Clay::UI: 'id' must be a non-empty string> for a reference or an empty
string, and with C<Clay::UI: 'id' must not start with 'anon:'> for an id
starting with C<anon:>, which is reserved for derived ids.


Two widgets with the same id in one frame are a Clay error; with the
default C<error_handler> of L<Clay::UI> the C<render> dies.

=head2 width_group

The width sizing group; see
L<Clay::UI::Role::Layout::HasSizingGroup/width_group>.

=head2 height_group

The height sizing group; see
L<Clay::UI::Role::Layout::HasSizingGroup/height_group>.

=head1 METHODS

=head2 children

	my $kids = $widget->children;    # arrayref, a new one on every call

Returns a new arrayref holding the direct children, in order. Changing
that array does not change the widget. Internal children (see
L</add_internal_children>) are not included.

=head2 get_children_with

	my @foos = $root->get_children_with(sub { ($_->id // '') =~ /^foo_/ });
	my @bars = $root->get_children_with(sub ($child) { $child->isa('My::Bar') });

Returns the direct children for which C<< $predicate->($child) >> is
true, as a list (in scalar context: how many). C<$_> is set to the
child as well, so both calling styles work. Does not look at
grandchildren or internal children. Text widgets are passed too; their
C<id> is undef.

=head2 internal_children

	my $helpers = $widget->internal_children;

Returns a new arrayref holding the internal children, in order.

=head2 layout_children

	my $laid_out = $widget->layout_children;

Returns a new arrayref holding the children followed by the internal
children: everything a frame lays out directly below this widget. The
layout pass, the focus order of L<Clay::UI::Interaction> and the
registry that maps render commands back to widgets read this list.
Widget users want L</children>.

=head2 add_internal_children

	$self->add_internal_children($scrollbar);

For widget classes: attaches widgets that the class needs in the
laid-out tree but that are not its user's content, for example a
floating scrollbar over a scroll container or a popup. Internal
children are:

=over 4

=item *

validated and given this widget as C<parent>, like children (see
L</ATTACHING CHILDREN>; the same errors apply);

=item *

laid out after the children, and part of the UI (C<ui>, events,
focus order) like any child;

=item *

invisible to the widget's user: C<children>, C<get_children_with> and
the mutators of L<Clay::UI::Role::Core::Container> never show or remove
them.

=back

Bumps the revision (L<Clay::UI::Revision>) and returns the widget.

=head2 remove_internal_children

	$self->remove_internal_children($scrollbar);

Detaches the given internal children the way removed children are
detached (their C<parent> becomes undef, hover, press and focus inside
them are released, see L</ATTACHING CHILDREN>). Widgets that are not
internal children of this widget are ignored. Bumps the revision when
something was removed. Returns the widget.

=head2 to_config

	my $config = $widget->to_config;

Builds and returns the widget's declaration: a new hashref with
snake_case keys. It calls every C<contribute_*> method of the widget's
class once, as C<< $self->$name(\%config) >>, so each one adds its part
(see L</EXTENDING THE DECLARATION>). A widget with nothing to declare
returns C<{}>.

The hashref is new on every call, and so are the parts the roles of
this distribution write (C<layout>, C<border>, ...), but the values
inside them may be the widget's own copies. Treat the result as
read-only; copy what you want to change. The layout pass works on a
camelCase copy of it.

Do not override C<to_config>. Object::Pad roles have no C<SUPER>, so an
override silently drops every C<contribute_*> method; add a
C<contribute_*> method instead.

=head2 resolve_id

	my $id = $widget->resolve_id($base, \@indices);

Returns the string the layout pass hashes with C<Clay_GetElementId> for
this widget: the user's C<id> when it has one, otherwise an anonymous
id derived from the widget's position:

	'anon:' . length($base) . ":$base/" . join('/', @indices)

C<$base> is the id of the nearest ancestor with an id (C<''> when there
is none) and C<@indices> the positions in C<layout_children> on the way
down from that ancestor. For example:

	root without an id                    anon:0:/
	its third child                       anon:0:/2
	child 1 of the widget 'list'          anon:4:list/1
	child 0 of that child                 anon:4:list/1/0

The length prefix keeps anonymous ids apart from each other (C<a/b> as
an id cannot be confused with an index path), and the reserved C<anon:>
prefix keeps them apart from user ids.

An anonymous id changes when the widget moves: inserting a sibling
before it, or before one of its anonymous ancestors, gives it a new id.
Give an C<id> to widgets that need the same Clay element id from frame
to frame: scroll containers (L<Clay::UI::Role::Layout::HasScroll>
requires one), elements with Clay transitions, and elements you look up
with L<Clay::XS> functions such as C<Clay_GetElementData>.

The layout pass supplies the arguments; calling C<resolve_id> yourself
is only useful in tests.

=head2 mark_changed

	$widget->mark_changed;

Bumps the revision (L<Clay::UI::Revision>) and returns the widget. The
accessors of this distribution's roles bump it themselves, and so does
every change to the children. A widget class that keeps state of its
own, which its C<contribute_*> methods turn into the declaration, calls
C<mark_changed> from its setters, so that a renderer that skips
unchanged frames draws the next one.

=head1 EXTENDING THE DECLARATION

C<to_config> knows nothing about layout, colours or borders. It finds
every method of the widget's class whose name starts with
C<contribute_> - from the class, its superclasses and every composed
role - and calls each one with the declaration hash under
construction. Each method writes one part of the declaration. This is
how L<Clay::UI::Role::Layout::HasLayout> adds C<layout>,
L<Clay::UI::Role::Style::HasBackground> adds C<background_color>, and
so on.

A widget class adds a declaration part Clay::UI has no role for by
defining a C<contribute_E<lt>nameE<gt>> method. This class adds Clay's
C<aspectRatio> (see L<Clay::XS::Structs/aspectRatio>):

	use v5.22;
	use Object::Pad;
	use Clay::XS qw(sizing_fixed);
	use Clay::UI;
	use Clay::UI::Box;
	use Scalar::Util ();

	class My::Picture :strict(params) :does(Clay::UI::Box) {
		field $aspect_ratio :param = 1;

		# The constructor and the setter check the value the same way.
		sub checked_ratio {
			my ($ratio) = @_;
			die "My::Picture: aspect_ratio must be a positive number\n"
				unless Scalar::Util::looks_like_number($ratio) && $ratio > 0;
			return $ratio;
		}

		ADJUST {
			checked_ratio($aspect_ratio);
		}

		method aspect_ratio (@new) {
			return $aspect_ratio unless @new;
			$aspect_ratio = checked_ratio($new[0]);
			$self->mark_changed;    # the declaration changes
			return $aspect_ratio;
		}

		# Adds the aspectRatio part to the declaration.
		method contribute_aspect_ratio ($config) {
			$config->{aspect_ratio} = { aspect_ratio => $aspect_ratio };
			return;
		}
	}

	my $picture = My::Picture->new(
		layout           => { sizing => { width => sizing_fixed(200) } },
		background_color => [90, 90, 90, 255],
		aspect_ratio     => 2,
	);
	my $ui = Clay::UI->new(width => 800, height => 600, root => $picture);
	my $commands = $ui->render;    # the rectangle is 200 x 100

	$picture->aspect_ratio(4);
	$commands = $ui->render;       # now 200 x 50

The rules for C<contribute_*> methods:

=over 4

=item *

Each is called once per C<to_config> with the declaration hashref; the
return value is ignored. The methods run in alphabetical order of their
names (C<contribute_background> before C<contribute_layout>).

=item *

Keys may be snake_case or camelCase; the layout pass converts them.
Do not use both spellings of one key.

=item *

A part that another method may also write must be merged, not
replaced. L<Clay::UI::Role::Layout::HasLayout> merges the user's
C<layout> over what is already there; defaults go under what is already
there, as L<Clay::UI::Grid> does for its C<layout>:

	method contribute_my_defaults ($config) {
		$config->{layout} = { child_gap => 4, %{ $config->{layout} // {} } };
		return;
	}

=item *

Do not set a value that another C<contribute_*> method of the class
also sets and that cannot be merged, for example a C<contribute_state_colour> that sets
C<background_color> in a class that also has the C<background_color>
attribute (L<Clay::UI::Role::Style::HasBackground>): the result then
depends on the order of the method names. To set the background by
state (L<Clay::UI::Role::Style::HasStates>), either leave the
C<background_color> attribute unset, or compose the roles without
HasBackground instead of L<Clay::UI::Box> (as the C<Settings::Toggle>
class in F<examples/12-ui-interaction.pl> does).

=item *

Write fresh hashes and arrays into the declaration; do not hand out a
container the widget keeps changing.

=item *

Do not set C<user_data>: the layout pass sets it to find the widget
again, and C<render> dies with C<Clay::UI: widget ... set user_data in its config>.

=item *

A setter that changes what a C<contribute_*> method writes calls
L</mark_changed>.

=item *

Clay::XS checks the declaration only when the element is configured,
and ignores unknown keys there: a misspelled key in a
C<contribute_*> method is silently dropped. Values of the wrong shape
make C<render> die. Validate in the constructor and the setters
(C<check_struct> of L<Clay::XS> checks a value against a Clay struct,
see L<Clay::XS/CHECKING STRUCTS>).

=item *

The methods run for every widget in every frame; keep them cheap.

=back

Method names must be unique: Object::Pad dies when two composed roles
provide the same C<contribute_*> method, or when a class defines one
that a role it composes already provides
(C<Method 'contribute_layout' clashes with the one provided by role ...>).
The roles of this distribution use these names:


=over 4

=item *

C<contribute_background> (L<Clay::UI::Role::Style::HasBackground>)

=item *

C<contribute_border> (L<Clay::UI::Role::Style::HasBorder>)

=item *

C<contribute_clip> (L<Clay::UI::Role::Layout::HasScroll>)

=item *

C<contribute_corner_radius> (L<Clay::UI::Role::Style::HasCornerRadius>)

=item *

C<contribute_floating> (L<Clay::UI::Role::Layout::HasFloating>)

=item *

C<contribute_grid_defaults> (L<Clay::UI::Grid>)

=item *

C<contribute_layout> (L<Clay::UI::Role::Layout::HasLayout>)

=item *

C<contribute_sizing_group> (L<Clay::UI::Role::Layout::HasSizingGroup>,
part of every element widget)

=back

A subclass may override a C<contribute_*> method of its superclass;
only the override runs.

The list of C<contribute_*> methods is looked up once per class and
kept, because Object::Pad classes do not change once compiled.

=head1 ATTACHING CHILDREN

Every change to the children - through
L<Clay::UI::Role::Core::Container>, L<Clay::UI::Grid> or
L</add_internal_children> - checks all new children before anything
changes, so a call that dies leaves the widget as it was. It dies when
a new child:

=over 4

=item *

is not a widget: C<Clay::UI: child is not a widget (got ...)>. A widget
is a blessed object composing C<Clay::UI::Role::Core::Element> or
L<Clay::UI::Role::Core::TextNode>;

=item *

appears twice in the call: C<Clay::UI: the same widget (...) is attached twice in one call>;

=item *

is the widget itself or one of its ancestors:
C<Clay::UI: cannot attach a widget to itself or to one of its descendants>;


=item *

is the root of a L<Clay::UI>:
C<Clay::UI: widget ... is the root of a Clay::UI and cannot become a child>;


=item *

still has a parent, even if it is this widget:
C<Clay::UI: widget ... is still attached to a parent; remove it first>
(see L<Clay::UI::Role::Layout::HasParent/ATTACHING AND REMOVING>).


=back

Every change bumps the revision (L<Clay::UI::Revision>). Widgets that
decide their children themselves may also reorder them
(L<Clay::UI::Grid/reorder_rows>); reordering detaches nothing.

A removed child is detached: its C<parent> becomes undef and its
subtree is no longer part of the UI until it is attached again. Hover,
press and focus inside the subtree are released first: a hovered
widget gets C<OnHoverStopped>, the focused widget gets C<OnBlur> (see
L<Clay::UI::Interaction>). A listener of those events that dies does
not stop the removal: the call completes and then dies with the
listener's error.

=head1 SEE ALSO

L<Clay::UI>, L<Clay::UI::Role::Core::Container>,
L<Clay::UI::Role::Core::TextNode>, L<Clay::UI::Box>,
L<Clay::UI::Revision>, L<Clay::XS::Structs>, L<Clay::Manual>.

=cut
