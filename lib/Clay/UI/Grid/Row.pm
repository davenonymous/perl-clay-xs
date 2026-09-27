package Clay::UI::Grid::Row;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Core::Element;
use Clay::UI::Role::Layout::HasLayout;

our $VERSION = '0.01';

class Clay::UI::Grid::Row :strict(params)
	:does(Clay::UI::Role::Core::Element)
	:does(Clay::UI::Role::Layout::HasLayout)
{}

1;

__END__

=head1 NAME

Clay::UI::Grid::Row - internal row container class for Clay::UI::Grid

=head1 DESCRIPTION

The C<LEFT_TO_RIGHT> container L<Clay::UI::Grid> builds for each row. It
composes L<Clay::UI::Role::Core::Element> and
L<Clay::UI::Role::Layout::HasLayout> only: it has no public child
mutators, because the Grid alone decides which cells a row holds (through
C<append_row>, C<insert_row>, C<replace_row> and C<set_cell>).

Not intended for direct use by application code; if you want a plain
styled container, consume L<Clay::UI::Box> in your own class.

=cut
