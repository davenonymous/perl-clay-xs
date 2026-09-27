use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::XS qw(:all);

# -----------------------------------------------------------------------------
# The Perl-side text measurement callback.
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

sub text_frame ($text, $config) {
    Clay_BeginLayout();
    Clay__OpenElementWithId( Clay_GetElementId("root") );
    Clay__ConfigureOpenElement({
        layout => { sizing => { width => sizing_grow(), height => sizing_grow() } },
    });
        Clay__OpenTextElement($text, $config);
    Clay__CloseElement();
    my $frame = Clay_EndLayout(0);
    my ($cmd) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_TEXT } @$frame;
    return $cmd;
}

# A failing measurer makes Clay_EndLayout croak with its error; once the
# measurer works again the text is measured afresh (no cached zero size).
Clay_SetMeasureTextFunction(sub { die "measurer exploded\n" });
like( dies { text_frame("ouch", { fontSize => 12 }) }, qr/^measurer exploded$/,
    'Clay_EndLayout croaks with the measurer error' );

Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
    return { width => length($text) * 10, height => 12 };
});
is( text_frame("ouch", { fontSize => 12 })->{boundingBox}{width}, 40,
    'a working measurer measures the same text correctly on the next frame' );

# Strings are characters: the measurer sees the decoded text.
{
    use utf8;
    my @seen;
    Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
        push @seen, $text;
        return { width => length($text), height => 10 };
    });
    text_frame("日本語 déjà", { fontSize => 10 });
    ok( ( grep { $_ eq "日本語" } @seen ), 'measurer receives CJK characters' );
    ok( ( grep { $_ eq "déjà" } @seen ),   'measurer receives accented characters' );
}

# A measurer that calls Clay_GetElementId while Clay reads the text must not
# disturb the text Clay holds.
Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
    Clay_GetElementId("measure-" . ("x" x 64)) for 1 .. 50;
    return { width => length($text), height => 10 };
});
is( text_frame("unchanged words here", { fontSize => 10 })->{renderData}{stringContents},
    "unchanged words here", 'text survives id lookups from inside the measurer' );

done_testing;
