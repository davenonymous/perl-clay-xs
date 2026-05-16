package Clay::UI::Role::Element;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;
use Object::Pad::MOP::Class;
no warnings 'experimental';

our $VERSION = '0.01';

role Clay::UI::Role::Element {
	no warnings 'experimental';

	field $id       :param :reader = undef;
	field $children :param :reader = [];

	method resolve_id ($path) {
		return $id if defined $id;
		return 'anon:' . join('/', @$path);
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
C<Clay::UI::Role::Element>.

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

=cut
