use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::XS qw(:all);

# -----------------------------------------------------------------------------
# Phase 8: scrolling containers.
#
# Build a container with vertical clip enabled and contents taller than
# the container. Scroll downward and verify the scroll container data
# reflects the new offset.
# -----------------------------------------------------------------------------

my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 100, height => 100 },
    sub { },
);
Clay_SetMeasureTextFunction(sub { return { width => 0, height => 0 } });

sub build () {
    Clay__OpenElementWithId( Clay_GetElementId("scroll") );
    Clay__ConfigureOpenElement({
        layout => {
            sizing          => { width => sizing_fixed(100), height => sizing_fixed(50) },
            layoutDirection => CLAY_TOP_TO_BOTTOM,
        },
        clip => { vertical => 1, childOffset => Clay_GetScrollOffset() },
    });
        for my $i (0 .. 5) {
            Clay__OpenElementWithId( Clay_GetElementIdWithIndex("row", $i) );
            Clay__ConfigureOpenElement({
                layout          => { sizing => { width => sizing_fixed(100), height => sizing_fixed(20) } },
                backgroundColor => [50 * (1 + ($i % 2)), 60, 70, 255],
            });
            Clay__CloseElement();
        }
    Clay__CloseElement();
}

# Frame 1: build the layout so the scroll container exists.
Clay_BeginLayout();
build();
Clay_EndLayout(0);

# Frame 2: place the pointer over the scroll container so Clay routes
# wheel input there, then apply scroll, then rebuild.
Clay_SetPointerState({ x => 50, y => 25 }, 0);
Clay_UpdateScrollContainers(0, { x => 0, y => -5 }, 1.0);
Clay_BeginLayout();
build();
Clay_EndLayout(0);

my $scroll_id   = Clay_GetElementId("scroll");
my $scroll_data = Clay_GetScrollContainerData($scroll_id);

ok( $scroll_data->{found}, 'GetScrollContainerData found the container' );
ok( $scroll_data->{config}{vertical}, 'clip vertical is true' );
ok( $scroll_data->{contentDimensions}{height} > 50,
    'content is taller than container' );

is( $scroll_data->{scrollContainerDimensions}{width},  100, 'container width' );
is( $scroll_data->{scrollContainerDimensions}{height},  50, 'container height' );

# Negative wheel scroll means the content moves up (scrollPosition.y becomes negative).
ok( $scroll_data->{scrollPosition}{y} < 0,
    "scrollPosition.y is negative after scrolling down (got $scroll_data->{scrollPosition}{y})" );

done_testing;
