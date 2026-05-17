use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::XS qw(:all);

# -----------------------------------------------------------------------------
# Phase 5: nested elements and text.
#
# Build a 3-level layout:
#
#     root  (220x140)
#       inner row (top-to-bottom)
#         label (text)
#         body  (filled rectangle)
#
# Confirm the render command stream contains:
#   - one rectangle for root
#   - one text command with the right contents
#   - one rectangle for body
# -----------------------------------------------------------------------------

my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 320, height => 240 },
    sub ($err, $userdata) { },
);

Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
    my $fs = $config->{fontSize} || 16;
    return { width => length($text) * $fs * 0.5, height => $fs };
});

Clay_BeginLayout();

Clay__OpenElementWithId( Clay_GetElementId("root") );
Clay__ConfigureOpenElement({
    layout => {
        sizing => {
            width  => sizing_fixed(220),
            height => sizing_fixed(140),
        },
        padding         => padding_all(10),
        childGap        => 6,
        layoutDirection => CLAY_TOP_TO_BOTTOM,
    },
    backgroundColor => [200, 200, 200, 255],
});

    Clay__OpenElementWithId( Clay_GetElementId("label") );
    Clay__OpenTextElement(
        "hello clay",
        { fontSize => 14, textColor => [0, 0, 0, 255] },
    );
    Clay__CloseElement();

    Clay__OpenElementWithId( Clay_GetElementId("body") );
    Clay__ConfigureOpenElement({
        layout          => { sizing => { width => sizing_grow(), height => sizing_grow() } },
        backgroundColor => [50, 100, 200, 255],
    });
    Clay__CloseElement();

Clay__CloseElement();

my $commands = Clay_EndLayout(0);

my %by_type;
push @{ $by_type{ $_->{commandType} } }, $_ for @$commands;

ok( exists $by_type{ +CLAY_RENDER_COMMAND_TYPE_RECTANGLE }, 'has rectangle commands' );
ok( exists $by_type{ +CLAY_RENDER_COMMAND_TYPE_TEXT },      'has at least one text command' );

is(
    scalar @{ $by_type{ +CLAY_RENDER_COMMAND_TYPE_RECTANGLE } },
    2,
    'two rectangles emitted (root + body)',
);

my $text_cmd = $by_type{ +CLAY_RENDER_COMMAND_TYPE_TEXT }[0];
is( $text_cmd->{renderData}{stringContents}, "hello clay", 'text contents preserved' );
is( $text_cmd->{renderData}{fontSize}, 14, 'text font size preserved' );

# Confirm element data lookups work post-layout.
my $body = Clay_GetElementData( Clay_GetElementId("body") );
ok( $body->{found}, 'body element found' );
ok( $body->{boundingBox}{height} > 0, 'body has nonzero height' );

# Element id hashing produces stable, repeatable values.
my $id_a = Clay__HashString("foo", 0);
my $id_b = Clay__HashString("foo", 0);
is( $id_a->{id}, $id_b->{id}, 'HashString is deterministic' );

my $id_c = Clay__HashStringWithOffset("foo", 1, 0);
isnt( $id_a->{id}, $id_c->{id}, 'HashStringWithOffset changes the hash' );

done_testing;
