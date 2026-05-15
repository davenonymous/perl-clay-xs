use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::Layout qw(:all);

# -----------------------------------------------------------------------------
# Phase 2.4: the sizing / padding / border / corner-radius helper subs.
# These are the Perl analogues of the CLAY_SIZING_* / CLAY_PADDING_ALL /
# CLAY_BORDER_* / CLAY_CORNER_RADIUS macros from clay.h.
# -----------------------------------------------------------------------------

subtest 'sizing helpers' => sub {
    my $fit = sizing_fit(10, 100);
    is( $fit->{type}, CLAY__SIZING_TYPE_FIT, 'sizing_fit type' );
    is( $fit->{min}, 10, 'sizing_fit min' );
    is( $fit->{max}, 100, 'sizing_fit max' );

    my $grow = sizing_grow();
    is( $grow->{type}, CLAY__SIZING_TYPE_GROW, 'sizing_grow defaults to no bounds' );
    is( $grow->{min}, 0, 'sizing_grow min defaults to 0' );

    my $fixed = sizing_fixed(50);
    is( $fixed->{type}, CLAY__SIZING_TYPE_FIXED, 'sizing_fixed type' );
    is( $fixed->{min}, 50, 'sizing_fixed encodes size as min' );
    is( $fixed->{max}, 50, 'sizing_fixed encodes size as max' );

    my $pct = sizing_percent(0.5);
    is( $pct->{type}, CLAY__SIZING_TYPE_PERCENT, 'sizing_percent type' );
    is( $pct->{percent}, 0.5, 'sizing_percent value' );
};

subtest 'padding/border/corner helpers' => sub {
    my $pad = padding_all(8);
    is( $pad->{left},   8, 'padding_all left' );
    is( $pad->{right},  8, 'padding_all right' );
    is( $pad->{top},    8, 'padding_all top' );
    is( $pad->{bottom}, 8, 'padding_all bottom' );

    my $bw = border_all(2);
    is( $bw->{left},            2, 'border_all left' );
    is( $bw->{betweenChildren}, 2, 'border_all betweenChildren' );

    my $bo = border_outside(3);
    is( $bo->{left},            3, 'border_outside left' );
    is( $bo->{betweenChildren}, 0, 'border_outside betweenChildren is 0' );

    my $cr = corner_radius_all(12);
    is( $cr->{topLeft},     12, 'corner_radius_all topLeft' );
    is( $cr->{bottomRight}, 12, 'corner_radius_all bottomRight' );
};

done_testing;
