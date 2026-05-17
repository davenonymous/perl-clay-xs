use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::XS qw(:all);

# -----------------------------------------------------------------------------
# Phase 7: pointer state, Hovered(), PointerOver(), GetPointerOverIds().
#
# Clay's pointer detection walks the most recent layout tree to populate
# pointerOverIds. That means the conventional usage is:
#
#     Clay_SetPointerState(...);   # walks the *previous* frame's tree
#     Clay_BeginLayout();
#     ... declare elements ...
#     Clay_EndLayout(...);          # builds the new tree
#
# A pointer interaction therefore requires at least one prior frame to
# have built a tree. The test below runs a two-frame sequence: frame 1
# defines geometry, frame 2 places the pointer.
# -----------------------------------------------------------------------------

my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 200, height => 200 },
    sub { },
);
Clay_SetMeasureTextFunction(sub { return { width => 0, height => 0 } });

sub build_layout () {
    Clay__OpenElementWithId( Clay_GetElementId("root") );
    Clay__ConfigureOpenElement({
        layout => {
            sizing => { width => sizing_fixed(100), height => sizing_fixed(100) },
        },
    });
        Clay__OpenElementWithId( Clay_GetElementId("button") );
        Clay__ConfigureOpenElement({
            layout => {
                sizing => { width => sizing_fixed(80), height => sizing_fixed(80) },
            },
        });
        Clay__CloseElement();
    Clay__CloseElement();
}

# ----- Frame 1: build geometry, no pointer interaction yet -------------------
Clay_BeginLayout();
build_layout();
Clay_EndLayout(0);

# ----- Frame 2: place pointer inside button, rebuild ------------------------
Clay_SetPointerState({ x => 30, y => 30 }, 0);
Clay_BeginLayout();
build_layout();
Clay_EndLayout(0);

my $button_id = Clay_GetElementId("button");

ok( Clay_PointerOver($button_id), 'PointerOver detects pointer inside button' );

my $over = Clay_GetPointerOverIds();
ok( ref($over) eq 'ARRAY', 'GetPointerOverIds returns an arrayref' );
ok( ( grep { $_->{id} == $button_id->{id} } @$over ),
    'button id is in pointer-over list' );

# ----- Frame 3: move pointer far away ---------------------------------------
Clay_SetPointerState({ x => 500, y => 500 }, 0);
Clay_BeginLayout();
build_layout();
Clay_EndLayout(0);

ok( !Clay_PointerOver($button_id), 'PointerOver false when pointer is outside' );

# ----- Pointer state round-trip ---------------------------------------------
Clay_SetPointerState({ x => 10, y => 20 }, 1);
my $state = Clay_GetPointerState();
is( $state->{position}{x}, 10, 'pointer x preserved' );
is( $state->{position}{y}, 20, 'pointer y preserved' );
is( $state->{state}, CLAY_POINTER_DATA_PRESSED_THIS_FRAME,
    'pointer state went pressed-this-frame on first press' );

done_testing;
