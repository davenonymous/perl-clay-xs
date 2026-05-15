use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::Layout qw(:all);

ok( defined &Clay_MinMemorySize, 'Clay_MinMemorySize is loaded' );

my $size = Clay_MinMemorySize();
ok( $size > 0, "Clay_MinMemorySize() returned a positive value ($size)" );

# A representative set of constants - confirms BOOT installed them.
is( CLAY_LEFT_TO_RIGHT,           0, 'CLAY_LEFT_TO_RIGHT == 0' );
is( CLAY_TOP_TO_BOTTOM,           1, 'CLAY_TOP_TO_BOTTOM == 1' );
is( CLAY__SIZING_TYPE_FIT,        0, 'CLAY__SIZING_TYPE_FIT == 0' );
is( CLAY_RENDER_COMMAND_TYPE_RECTANGLE, 1, 'CLAY_RENDER_COMMAND_TYPE_RECTANGLE == 1' );

done_testing;
