package Clay::UI;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Scalar::Util qw(blessed);

use Clay::Layout qw(
	Clay_GetElementId
	Clay__OpenElementWithId
	Clay__ConfigureOpenElement
	Clay__CloseElement
	Clay__OpenTextElement
);
use Clay::UI::_keys qw(camelize_keys);

our $VERSION = '0.01';

sub layout ($root) {
	_walk($root, []);
	return;
}

sub _walk ($node, $path) {
	unless (blessed $node) {
		die "Clay::UI: tree node is not a blessed widget (got " . (ref($node) || 'non-ref') . ")";
	}

	if ($node->DOES('Clay::UI::Role::TextNode')) {
		Clay__OpenTextElement($node->text, camelize_keys($node->text_config));
		return;
	}

	unless ($node->DOES('Clay::UI::Role::Element')) {
		die "Clay::UI: tree node " . ref($node) . " does not consume Clay::UI::Role::Element or TextNode";
	}

	my $id      = $node->resolve_id($path);
	my $element = Clay_GetElementId($id);

	Clay__OpenElementWithId($element);

	my $config = $node->to_config;
	Clay__ConfigureOpenElement(camelize_keys($config));

	$node->install_hover_callback if $node->DOES('Clay::UI::Role::Hoverable');

	my $children = $node->children;
	for my $index (0 .. $#$children) {
		_walk($children->[$index], [ @$path, "$id/$index" ]);
	}

	Clay__CloseElement();
	return;
}

1;

__END__

=head1 NAME

Clay::UI - Perl-idiomatic high-level layer over Clay::Layout

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::Layout qw(Clay_Initialize Clay_BeginLayout Clay_EndLayout);
	use Clay::UI;

	class My::Root :does(Clay::UI::Role::Element) {
		method to_config { return { background_color => [40, 50, 60, 255] } }
	}

	my $ctx = Clay_Initialize(...);
	Clay_BeginLayout();
	Clay::UI::layout( My::Root->new(id => 'root') );
	my $commands = Clay_EndLayout(0);

=head1 DESCRIPTION

C<Clay::UI> sits on top of the low-level L<Clay::Layout> binding. Users
build a declarative tree of widget objects (each consuming
L<Clay::UI::Role::Element>) and the walker translates the tree into the
open / configure / close call sequence Clay expects.

The low-level API is untouched and remains independently usable.

=head1 FUNCTIONS

=head2 layout($root)

Walks C<$root> and its children, emitting Clay open/configure/close calls
for each node. Must be invoked between C<Clay_BeginLayout> and
C<Clay_EndLayout>. Returns nothing.

=head1 SEE ALSO

L<Clay::UI::Role::Element>, L<Clay::Layout>.

=cut
