package Clay::UI::Role::TextNode;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

our $VERSION = '0.01';

role Clay::UI::Role::TextNode {
	method text;
	method text_config;
}

1;

__END__

=head1 NAME

Clay::UI::Role::TextNode - marker role for Clay::UI text-leaf widgets

=head1 DESCRIPTION

Marker role consumed by L<Clay::UI::Text> (and any user-defined text
widget). The walker checks C<< $node->DOES('Clay::UI::Role::TextNode') >>
and, if true, calls C<< $node->text >> + C<< $node->text_config >> and
dispatches to C<Clay__OpenTextElement> instead of the normal open /
configure / close flow.

=head1 REQUIRED METHODS

=head2 text

Returns the string to render.

=head2 text_config

Returns the text-element config hashref (snake_case keys allowed;
the walker camelizes).

=cut
