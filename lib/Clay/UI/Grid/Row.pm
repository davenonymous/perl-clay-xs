package Clay::UI::Grid::Row;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Box;

our $VERSION = '0.01';

class Clay::UI::Grid::Row :does(Clay::UI::Box) {}

1;

__END__

=head1 NAME

Clay::UI::Grid::Row - internal row container class for Clay::UI::Grid

=head1 DESCRIPTION

Concrete consumer of the L<Clay::UI::Box> role used by L<Clay::UI::Grid>
to build its per-row C<LEFT_TO_RIGHT> containers. Has no body of its
own: it exists only so Grid has an instantiable class to call
C<< ->new(layout => ...) >> on now that C<Clay::UI::Box> is a role.

Not intended for direct use by application code; if you want a plain
styled container, consume L<Clay::UI::Box> in your own class.

=cut
