use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::XS qw(:all);

# -----------------------------------------------------------------------------
# Phase 4: full Init -> BeginLayout -> Element -> EndLayout cycle.
#
# We declare a single root rectangle of fixed size and confirm exactly one
# RECTANGLE render command is emitted with the bounding box we expect.
# -----------------------------------------------------------------------------

my @errors;
my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 320, height => 240 },
    sub ($err, $userdata) { push @errors, $err },
);

ok( defined $ctx, 'Clay_Initialize returned a context' );
isa_ok( $ctx, ['Clay::XS::Context'], 'context is blessed' );

Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
    # Cheap monospace approximation. Sufficient for our test, which
    # does not declare any text elements.
    my $fs = $config->{fontSize} || 16;
    return { width => length($text) * $fs, height => $fs };
});

Clay_BeginLayout();

Clay__OpenElementWithId( Clay_GetElementId("root") );
Clay__ConfigureOpenElement({
    layout => {
        sizing => {
            width  => sizing_fixed(200),
            height => sizing_fixed(100),
        },
    },
    backgroundColor => { r => 10, g => 20, b => 30, a => 255 },
    cornerRadius    => corner_radius_all(4),
});
Clay__CloseElement();

my $commands = Clay_EndLayout(0);

ok( defined $commands && ref($commands) eq 'ARRAY', 'EndLayout returns an arrayref' );
is( scalar(@errors), 0, 'no errors during layout' )
    or diag( "errors: ", join("; ", map { $_->{errorText} } @errors) );

is( scalar(@$commands), 1, 'one render command emitted' );

my $cmd = $commands->[0];
is( $cmd->{commandType}, CLAY_RENDER_COMMAND_TYPE_RECTANGLE, 'command type is RECTANGLE' );
is( $cmd->{boundingBox}{width},  200, 'bounding box width' );
is( $cmd->{boundingBox}{height}, 100, 'bounding box height' );

is( $cmd->{renderData}{backgroundColor}{r}, 10, 'background r' );
is( $cmd->{renderData}{backgroundColor}{a}, 255, 'background a' );
is( $cmd->{renderData}{cornerRadius}{topLeft}, 4, 'corner radius topLeft' );

# Confirm Clay_GetElementData can find the element after end_layout.
my $data = Clay_GetElementData( Clay_GetElementId("root") );
ok( $data->{found}, 'GetElementData found the element' );
is( $data->{boundingBox}{width}, 200, 'GetElementData width matches' );

done_testing;
