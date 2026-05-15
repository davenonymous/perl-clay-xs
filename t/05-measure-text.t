use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::Layout qw(:all);

# -----------------------------------------------------------------------------
# Phase 6: Perl-side text measurement callback.
#
# Install a measurer that records every call, returns a deterministic
# size, and verifies the contract: each text element emitted in the
# layout triggers at least one measurement, and the returned text
# render command reflects the measured size.
# -----------------------------------------------------------------------------

my @calls;

my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 800, height => 200 },
    sub { },
);

Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
    push @calls, {
        text       => $text,
        font_size  => $config->{fontSize},
        font_id    => $config->{fontId},
        user_data  => $userdata,
    };
    return { width => length($text) * $config->{fontSize}, height => $config->{fontSize} };
}, "user-payload-42");

Clay_BeginLayout();
Clay__OpenElementWithId( Clay_GetElementId("root") );
Clay__ConfigureOpenElement({
    layout => { sizing => { width => sizing_grow(), height => sizing_grow() } },
});
    Clay__OpenTextElement(
        "hello",
        { fontSize => 20, fontId => 7, textColor => [0,0,0,255] },
    );
Clay__CloseElement();
my $cmds = Clay_EndLayout(0);

# The measurer must have been called at least once.
ok( scalar(@calls) > 0, 'measurer was invoked' );

# Every call must have observed the configured fontSize, fontId, and userdata.
my $first = $calls[0];
is( $first->{font_size},  20, 'fontSize propagates to measurer' );
is( $first->{font_id},     7, 'fontId propagates to measurer' );
is( $first->{user_data}, 'user-payload-42', 'userdata propagates' );

# The emitted text command should reflect the measured dimensions.
my ($text_cmd) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_TEXT } @$cmds;
ok( defined $text_cmd, 'text render command emitted' );
is( $text_cmd->{renderData}{fontSize}, 20, 'text command fontSize matches' );

# A failing measurer must not crash; Clay survives swallowed exceptions.
Clay_SetMeasureTextFunction(sub { die "measurer exploded" });
Clay_BeginLayout();
Clay__OpenElementWithId( Clay_GetElementId("root") );
Clay__ConfigureOpenElement({
    layout => { sizing => { width => sizing_grow(), height => sizing_grow() } },
});
    Clay__OpenTextElement("ouch", { fontSize => 12 });
Clay__CloseElement();
my $cmds2 = Clay_EndLayout(0);

ok( defined $cmds2 && ref($cmds2) eq 'ARRAY',
    'layout still produces a render command stream after measurer dies' );

done_testing;
