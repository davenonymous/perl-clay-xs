use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::Layout qw(:all);

# -----------------------------------------------------------------------------
# Phase 3: a rich ElementDeclaration passes through Clay's open/configure/
# close pipeline without raising errors. We do not have a Perl-callable
# inspector for the marshalled struct (Clay does not expose one), so the
# check here is "Clay accepts the declaration and produces the matching
# render commands". The shape of those commands implicitly verifies the
# borders, corner radius, etc. were marshalled correctly.
# -----------------------------------------------------------------------------

my @errors;
my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 400, height => 300 },
    sub ($err, $userdata) { push @errors, $err },
);
Clay_SetMeasureTextFunction(sub { return { width => 0, height => 0 } });

Clay_BeginLayout();

Clay__OpenElementWithId( Clay_GetElementId("container") );
Clay__ConfigureOpenElement({
    layout => {
        sizing  => {
            width  => sizing_fixed(300),
            height => sizing_fixed(200),
        },
        padding         => { left => 10, right => 10, top => 5, bottom => 5 },
        childGap        => 4,
        childAlignment  => { x => CLAY_ALIGN_X_CENTER, y => CLAY_ALIGN_Y_CENTER },
        layoutDirection => CLAY_TOP_TO_BOTTOM,
    },
    backgroundColor => [40, 50, 60, 200],
    overlayColor    => [255, 0, 0, 50],
    cornerRadius    => { topLeft => 6, topRight => 6, bottomLeft => 0, bottomRight => 0 },
    border          => {
        color => [100, 100, 100, 255],
        width => { left => 1, right => 1, top => 1, bottom => 1, betweenChildren => 0 },
    },
});
Clay__CloseElement();

my $cmds = Clay_EndLayout(0);

is( scalar(@errors), 0, 'no Clay errors for rich declaration' );
ok( scalar(@$cmds) >= 2, 'at least 2 commands emitted (rect + border + overlay markers)' );

# A backgroundColor + cornerRadius produces a RECTANGLE command.
my ($rect) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_RECTANGLE } @$cmds;
ok( defined $rect, 'rectangle command present' );
is( $rect->{renderData}{backgroundColor}{r},   40, 'background r' );
is( $rect->{renderData}{cornerRadius}{topLeft}, 6, 'cornerRadius topLeft' );
is( $rect->{renderData}{cornerRadius}{bottomRight}, 0, 'cornerRadius bottomRight' );

# A border block produces a BORDER command.
my ($border) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_BORDER } @$cmds;
ok( defined $border, 'border command present' );
is( $border->{renderData}{color}{r}, 100, 'border color r' );
is( $border->{renderData}{width}{left}, 1, 'border width left' );

# An overlayColor produces OVERLAY_COLOR_START + END markers.
my @overlay = grep {
    $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_START
 || $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_END
} @$cmds;
is( scalar(@overlay), 2, 'overlay start + end markers emitted' );

# -----------------------------------------------------------------------------
# Floating element check.
# -----------------------------------------------------------------------------

Clay_BeginLayout();
Clay__OpenElementWithId( Clay_GetElementId("parent") );
Clay__ConfigureOpenElement({
    layout => { sizing => { width => sizing_fixed(200), height => sizing_fixed(200) } },
});
    Clay__OpenElementWithId( Clay_GetElementId("floater") );
    Clay__ConfigureOpenElement({
        layout   => { sizing => { width => sizing_fixed(50), height => sizing_fixed(50) } },
        floating => {
            attachTo     => CLAY_ATTACH_TO_PARENT,
            attachPoints => {
                element => CLAY_ATTACH_POINT_LEFT_TOP,
                parent  => CLAY_ATTACH_POINT_LEFT_TOP,
            },
            offset       => { x => 10, y => 10 },
            zIndex       => 5,
        },
        backgroundColor => [200, 200, 0, 255],
    });
    Clay__CloseElement();
Clay__CloseElement();

my $cmds2 = Clay_EndLayout(0);
my @floater_rects = grep {
       $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_RECTANGLE
    && $_->{boundingBox}{x} > 0
    && $_->{boundingBox}{width} == 50
} @$cmds2;
ok( scalar(@floater_rects) >= 1, 'floating rectangle emitted somewhere' );
is( $floater_rects[0]{zIndex}, 5, 'zIndex propagated from floating config' );

done_testing;
