use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::XS qw(:all);

# -----------------------------------------------------------------------------
# Phase 10: transition callback wiring.
#
# Transitions in Clay v0.14 deliver a single handler per element. The
# binding's design (see clay_perl.h notes) installs per-context handlers
# that fire for every transitioning element; per-element dispatch is a
# future enhancement.
#
# This test verifies:
#   - Clay_SetTransitionHandlers installs and replaces handlers cleanly
#   - An element with a transition config does not crash the pipeline
#   - The handler trampoline does not corrupt Clay's internal state
#     when the Perl handler is absent or returns sensible values
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

# We cannot reliably assert how many times the handler fired (it depends on
# Clay's internal transition lifecycle), only that things did not crash.
# At minimum, declaring a transition config must not produce errors.
ok( 1, 'transition pipeline survived without crashing' );

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

done_testing;
