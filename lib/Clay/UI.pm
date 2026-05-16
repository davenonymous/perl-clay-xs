package Clay::UI;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Scalar::Util qw(blessed refaddr weaken);

use Clay::Layout qw(
	Clay_GetElementId
	Clay__OpenElementWithId
	Clay__ConfigureOpenElement
	Clay__CloseElement
	Clay__OpenTextElement
);
use Clay::UI::_keys qw(camelize_keys);

our $VERSION = '0.01';

my %widget_registry;

sub layout ($root) {
	%widget_registry = ();
	_walk($root, []);
	return;
}

sub widget_for ($user_data) {
	return undef unless defined $user_data && $user_data;
	return $widget_registry{$user_data};
}

sub _attach_back_reference ($config, $node) {
	if (exists $config->{user_data} || exists $config->{userData}) {
		die "Clay::UI: widget " . ref($node)
			. " set user_data in its config; Clay::UI auto-injects a refaddr"
			. " back-reference here. Use one mechanism or the other, not both.";
	}
	my $addr = refaddr($node);
	$config->{user_data} = $addr;
	$widget_registry{$addr} = $node;
	weaken $widget_registry{$addr};
	return;
}

sub _walk ($node, $path) {
	unless (blessed $node) {
		die "Clay::UI: tree node is not a blessed widget (got " . (ref($node) || 'non-ref') . ")";
	}

	if ($node->DOES('Clay::UI::Role::TextNode')) {
		my $text_config = $node->text_config;
		_attach_back_reference($text_config, $node);
		Clay__OpenTextElement($node->text, camelize_keys($text_config));
		return;
	}

	unless ($node->DOES('Clay::UI::Role::Element')) {
		die "Clay::UI: tree node " . ref($node) . " does not consume Clay::UI::Role::Element or TextNode";
	}

	# Build and validate the config BEFORE opening the Clay element so a
	# config-time exception cannot leave Clay's open-element stack
	# unbalanced (which would SEGV at EndLayout).
	my $config = $node->to_config;
	_attach_back_reference($config, $node);
	my $camelized = camelize_keys($config);

	my $id      = $node->resolve_id($path);
	my $element = Clay_GetElementId($id);

	Clay__OpenElementWithId($element);
	Clay__ConfigureOpenElement($camelized);

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

Resets the internal widget-back-reference registry on entry (see
L</widget_for>).

=head2 widget_for($user_data)

Given the C<userData> integer carried on a render command, returns the
widget object that produced it (or C<undef> if the widget has been
garbage-collected since the last C<layout> call). The walker
auto-injects C<refaddr($widget)> as each element's C<user_data> so
renderers can recover the originating widget without threading
explicit state.

	for my $cmd (@$render_commands) {
		my $widget = Clay::UI::widget_for($cmd->{userData});
		# dispatch on ref $widget, read fields, etc.
	}

Lifetime: registry entries are weak references. Keep the widget tree
alive until you have finished consuming render commands, otherwise
C<widget_for> will return C<undef> for collected widgets.

Conflict: a widget's C<to_config> (or C<text_config>) must NOT set
C<user_data> itself; C<layout> dies if it sees one already present.

=head1 SEE ALSO

L<Clay::UI::Role::Element>, L<Clay::Layout>.

=cut
