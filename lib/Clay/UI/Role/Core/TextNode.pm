package Clay::UI::Role::Core::TextNode;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Revision qw(bump_revision);
use Clay::UI::Role::Layout::HasParent;
use Clay::UI::Role::Events::Listener;

our $VERSION = '0.01';

role Clay::UI::Role::Core::TextNode :does(Clay::UI::Role::Layout::HasParent)
                              :does(Clay::UI::Role::Events::Listener) {
	method text;
	method text_config;

	method mark_changed () {
		bump_revision();
		return $self;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Role::Core::TextNode - marker role for Clay::UI text-leaf widgets

=head1 DESCRIPTION

Marker role consumed by L<Clay::UI::Text> (and any user-defined text
widget). The walker checks C<< $node->DOES('Clay::UI::Role::Core::TextNode') >>
and, if true, calls C<< $node->text >> + C<< $node->text_config >> and
dispatches to C<Clay__OpenTextElement> instead of the normal open /
configure / close flow.

=head1 REQUIRED METHODS

=head2 text

Returns the string to render.

=head2 text_config

Returns the text-element config hashref (snake_case keys allowed;
the walker camelizes).

=head1 METHODS

=head2 mark_changed

	$widget->mark_changed;

Bumps the process-wide revision (L<Clay::UI::Revision>) and returns
C<$self>. L<Clay::UI::Text>'s accessors bump it themselves; a text
widget class that keeps state of its own calls C<mark_changed> from its
setters so that renderers skipping unchanged frames see the change.

=cut
