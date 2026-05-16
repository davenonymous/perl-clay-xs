package Clay::UI::Role::Element;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Object::Pad::MOP::Class;
use Scalar::Util qw(blessed);
no warnings 'experimental';

use Clay::UI::Role::HasSizingGroup;
use Clay::UI::Role::HasParent;

our $VERSION = '0.01';

role Clay::UI::Role::Element :does(Clay::UI::Role::HasSizingGroup)
                              :does(Clay::UI::Role::HasParent) {
	no warnings 'experimental';

	field $id       :param :reader = undef;
	field $children :param :reader = [];

	ADJUST {
		for my $kid (@$children) {
			_validate_child($kid);
			$kid->_set_parent($self);
		}
	}

	method resolve_id ($path) {
		return $id if defined $id;
		return 'anon:' . join('/', @$path);
	}

	method add_child (@kids) {
		_validate_child($_) for @kids;
		$_->_set_parent($self) for @kids;
		push @$children, @kids;
		return $self;
	}

	sub _validate_child ($kid) {
		return if blessed($kid)
			&& ( $kid->DOES('Clay::UI::Role::Element')
			  || $kid->DOES('Clay::UI::Role::TextNode') );
		die "Clay::UI: child is not a widget (got "
			. (ref($kid) || 'non-ref') . ")";
	}

	method clear_children () {
		@$children = ();
		return $self;
	}

	method remove_child ($target_id) {
		@$children = grep {
			!( $_->DOES('Clay::UI::Role::Element')
				&& defined $_->id
				&& $_->id eq $target_id )
		} @$children;
		return $self;
	}

	method remove_children_with ($predicate) {
		@$children = grep { !$predicate->($_) } @$children;
		return $self;
	}

	method get_children_with ($predicate) {
		return grep { $predicate->($_) } @$children;
	}

	method to_config {
		my %config;
		my $meta = Object::Pad::MOP::Class->for_class(ref $self);
		for my $provider ($meta->all_roles, $meta) {
			for my $method ($provider->direct_methods) {
				my $name = $method->name;
				next unless $name =~ /^contribute_/;
				$self->$name(\%config);
			}
		}
		return \%config;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Element - base role for high-level Clay widget nodes

=head1 SYNOPSIS

	use Object::Pad;

	class My::Widget :does(Clay::UI::Role::Element)
	                 :does(Clay::UI::Role::HasBackground)
	{
		# to_config is inherited from Element; it collects every
		# contribute_* method from composed roles automatically.
	}

	my $tree = My::Widget->new(
		id               => 'my-root',
		background_color => [255, 0, 0, 255],
	);

=head1 DESCRIPTION

Object::Pad role consumed by every L<Clay::UI> widget class. Provides the
two structural fields the walker needs (an optional C<id>, and a
C<children> arrayref) and a default C<to_config> that auto-discovers
contribution methods from composed mixin roles (see
L<Clay::UI::Role::HasLayout>, L<Clay::UI::Role::HasBackground>, ...).

=head1 FIELDS

=head2 id (optional)

If set, the user-supplied string is used verbatim as the Clay element id.
If omitted, the walker derives a stable id from the tree path via
L</resolve_id>.

=head2 children (optional, default C<[]>)

Arrayref of nested widget instances. Each element must consume
C<Clay::UI::Role::Element> or C<Clay::UI::Role::TextNode>. Children
passed at construction are validated and parent-stamped identically to
L</add_child>, so the same no-reparenting rule applies to widgets
handed to the constructor.

=head1 METHODS

=head2 to_config

Walks every role composed into the widget class. For each role's
direct methods whose name begins with C<contribute_>, calls
C<< $self->$name(\%config) >> so the role can write its own slice into
the configuration hash. Returns the assembled hashref.

Widgets normally do not override C<to_config>; they declare fields and
let the mixins contribute their slices. Override C<to_config> only when
you intend to bypass the mixin pipeline entirely - Object::Pad roles
have no C<SUPER>, so an override loses every C<contribute_*> call.

=head2 resolve_id($path)

Returns the user-supplied id if set, otherwise returns
C<"anon:$joined_path">. The walker uses the result to call
C<Clay_GetElementId>, which hashes the string into a stable Clay id.

=head2 add_child(@kids)

Appends one or more widgets to C<children>. Each argument must be a
blessed instance consuming C<Clay::UI::Role::Element> or
C<Clay::UI::Role::TextNode>; anything else dies with a descriptive
error. Returns C<$self> so calls chain:

	$root->add_child($header)->add_child($body, $footer);

Stamps the parent reference (see L<Clay::UI::Role::HasParent>) on every
kid. Dies if a kid already has a parent: a widget can be attached
exactly once, and that includes re-adding it under the same parent
(idempotent-builder patterns must construct fresh widgets per call).
See L<Clay::UI::Role::HasParent/NO REPARENTING> for the full contract.

=head2 clear_children

Empties C<children> in place and returns C<$self>.

=head2 remove_child($id)

Removes every direct child whose C<id> equals C<$id>. Text nodes have
no id and are never removed. Unknown ids are silently ignored. Returns
C<$self>.

=head2 remove_children_with($predicate)

Removes every direct child for which C<< $predicate->($child) >> is
true. C<$_> is also bound to the current child inside the block.
Returns C<$self>.

=head2 get_children_with($predicate)

Returns the list of direct children for which C<< $predicate->($child) >>
is true. C<$_> is also set to the current child inside the block, so
both calling styles work:

	my @foos = $root->get_children_with(sub { $_->id =~ /^foo_/ });
	my @bars = $root->get_children_with(sub { $_[0]->isa('My::Bar') });

Does not recurse into descendants.

=cut
