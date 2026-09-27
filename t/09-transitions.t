use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::XS qw(:all);

# -----------------------------------------------------------------------------
# Transition handlers. Clay's transition callbacks carry no element id, so
# the binding installs one handler set per context that serves every
# transitioning element (see src/clay_perl.h).
#
# This test verifies:
#   - Clay_SetTransitionHandlers installs and replaces handlers cleanly
#   - the handler receives the transition arguments and what it writes
#     into current is what gets drawn
#   - Clay_EaseOut eases every selected property
#   - an exiting element keeps its text
# -----------------------------------------------------------------------------

my @handler_args;

my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 100, height => 100 },
    sub { },
);
Clay_SetMeasureTextFunction(sub { return { width => 0, height => 0 } });

Clay_SetTransitionHandlers(
    # handler: return true (complete) after first call to keep the test deterministic
    sub ($args, $userdata) {
        push @handler_args, $args;
        return 1;
    },
    # setInitialState: identity
    sub ($target, $properties, $userdata) { return $target },
    # setFinalState: identity
    sub ($initial, $properties, $userdata) { return $initial },
    "transition-userdata",
);

# Frame 1: element with no transition.
sub build_frame ($bg) {
    Clay__OpenElementWithId( Clay_GetElementId("box") );
    Clay__ConfigureOpenElement({
        layout          => { sizing => { width => sizing_fixed(50), height => sizing_fixed(50) } },
        backgroundColor => $bg,
        transition => {
            duration   => 0.5,
            properties => CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR,
        },
    });
    Clay__CloseElement();
}

Clay_BeginLayout();
build_frame([255, 0, 0, 255]);
Clay_EndLayout(0.016);

# Frame 2: change the background colour - should trigger a transition.
Clay_BeginLayout();
build_frame([0, 255, 0, 255]);
my $cmds = Clay_EndLayout(0.016);

ok( ref($cmds) eq 'ARRAY', 'layout produced commands during transition' );
ok( scalar(@handler_args) >= 1, 'the handler ran for the background change' );
is( $handler_args[0]{target}{backgroundColor}, { r => 0, g => 255, b => 0, a => 255 },
    'it received the new colour as target' );
is( $handler_args[0]{properties}, CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR,
    'and the configured properties' );

# Test removal: install null handlers; subsequent frames must still work.
Clay_SetTransitionHandlers(undef, undef, undef, undef);
Clay_BeginLayout();
build_frame([0, 0, 255, 255]);
my $cmds_after = Clay_EndLayout(0.016);
ok( ref($cmds_after) eq 'ARRAY', 'pipeline still works after handlers removed' );

# Test Clay_EaseOut helper.
# At elapsed=duration the lerp finishes; current.boundingBox.x should
# equal target.boundingBox.x and complete should be true.
my $finished = Clay_EaseOut({
    transitionState => CLAY_TRANSITION_STATE_TRANSITIONING,
    elapsedTime     => 1.0,
    duration        => 1.0,
    properties      => CLAY_TRANSITION_PROPERTY_X,
    initial => { boundingBox => { x =>  0, y => 0, width => 100, height => 100 } },
    target  => { boundingBox => { x => 50, y => 0, width => 100, height => 100 } },
});
ok( $finished->{complete}, 'Clay_EaseOut reports completion at elapsed == duration' );
is( $finished->{current}{boundingBox}{x}, 50,
    'eased x reaches target at completion' );

# Halfway through, current should be between initial and target.
my $mid = Clay_EaseOut({
    transitionState => CLAY_TRANSITION_STATE_TRANSITIONING,
    elapsedTime     => 0.25,
    duration        => 1.0,
    properties      => CLAY_TRANSITION_PROPERTY_X,
    initial => { boundingBox => { x =>  0, y => 0, width => 100, height => 100 } },
    target  => { boundingBox => { x => 50, y => 0, width => 100, height => 100 } },
});
ok( !$mid->{complete}, 'Clay_EaseOut reports in-progress when elapsed < duration' );
ok( $mid->{current}{boundingBox}{x} > 0
 && $mid->{current}{boundingBox}{x} < 50,
    'eased x is between initial and target during transition' );

# Colours and border widths ease too. At t = 0.5 the ease-out curve
# 1 - (1 - t)^3 gives a lerp amount of 0.875.
my $colour = Clay_EaseOut({
    elapsedTime => 0.5,
    duration    => 1.0,
    properties  => CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR | CLAY_TRANSITION_PROPERTY_BORDER_WIDTH,
    initial => { backgroundColor => [255, 0, 0, 255], borderWidth => { left => 0,  top => 8 } },
    target  => { backgroundColor => [0, 0, 255, 255], borderWidth => { left => 16, top => 0 } },
});
is( $colour->{current}{backgroundColor}, { r => 31.875, g => 0, b => 223.125, a => 255 },
    'backgroundColor eases between initial and target' );
is( $colour->{current}{borderWidth}{left}, 14, 'borderWidth eases (left)' );
is( $colour->{current}{borderWidth}{top},   1, 'borderWidth eases (top)' );

like( dies { Clay_EaseOut({ initial => [1, 2, 3] }) }, qr/Clay_EaseOut: initial: expected a hash reference/,
    'a non-hash initial croaks' );
like( dies { Clay_EaseOut({ current => 'oops' }) }, qr/Clay_EaseOut: current: expected a hash reference/,
    'a non-hash current croaks' );

# -----------------------------------------------------------------------------
# An element playing its exit transition keeps rendering its own text while
# the rest of the frame's text changes.
# -----------------------------------------------------------------------------

subtest 'exiting element keeps its text' => sub {
    Clay_SetTransitionHandlers(sub { 0 }, undef, sub ($initial, $properties, $userdata) { $initial });
    my $frame = sub ($with_toast, $body) {
        Clay_BeginLayout();
        Clay__OpenElementWithId( Clay_GetElementId("page") );
        Clay__ConfigureOpenElement({ layout => { layoutDirection => CLAY_TOP_TO_BOTTOM } });
        if ($with_toast) {
            Clay__OpenElementWithId( Clay_GetElementId("toast") );
            Clay__ConfigureOpenElement({
                transition => { duration => 1, properties => CLAY_TRANSITION_PROPERTY_X,
                                exit => { hasSetFinal => 1 } },
            });
            Clay__OpenTextElement("TOAST-MESSAGE-TEXT", {});
            Clay__CloseElement();
        }
        Clay__OpenTextElement($body, {});
        Clay__CloseElement();
        return [ map { $_->{renderData}{stringContents} }
                 grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_TEXT } @{ Clay_EndLayout(0.016) } ];
    };
    $frame->(1, "first body");
    $frame->(1, "second body");
    for my $body ("X" x 40, "Y" x 40, "Z" x 40) {
        is( $frame->(0, $body), [ "TOAST-MESSAGE-TEXT", $body ], "exiting toast text intact next to '$body'" );
    }
    Clay_SetTransitionHandlers();
};

# -----------------------------------------------------------------------------
# What the handler writes into current is what gets drawn.
# -----------------------------------------------------------------------------

subtest 'the state the handler writes is drawn' => sub {
    Clay_SetTransitionHandlers(sub ($args, $userdata) {
        $args->{current}{backgroundColor} = { r => 1, g => 2, b => 3, a => 255 };
        return 0;
    });
    my $colour_of = sub ($bg) {
        Clay_BeginLayout();
        build_frame($bg);
        my ($rect) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_RECTANGLE } @{ Clay_EndLayout(0.016) };
        return $rect->{renderData}{backgroundColor};
    };
    $colour_of->([255, 0, 0, 255]);
    is( $colour_of->([0, 255, 0, 255]), { r => 1, g => 2, b => 3, a => 255 },
        'the rectangle has the colour the handler set' );
    Clay_SetTransitionHandlers();
};

done_testing;
