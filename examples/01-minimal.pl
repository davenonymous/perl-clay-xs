#!/usr/bin/env perl

# 01-minimal.pl - The smallest useful Clay::XS demo.
#
# Builds a single layout, dumps the resulting render commands as
# JSON to stdout. Run with:
#
#     perl -Ilib -Iblib/lib -Iblib/arch examples/01-minimal.pl

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Clay::XS qw(:all);
use JSON::PP;

my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 320, height => 240 },
    sub ($err, $userdata) {
        warn "Clay error: $err->{errorText}\n";
    },
);

# Clay measures text through this function; a context that lays out text
# needs one. A monospace approximation is enough here.
Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
    my $fs = $config->{fontSize} || 16;
    return { width => length($text) * $fs * 0.5, height => $fs };
});

Clay_BeginLayout();

Clay__OpenElementWithId( Clay_GetElementId("root") );
Clay__ConfigureOpenElement({
    layout => {
        sizing          => { width => sizing_grow(), height => sizing_grow() },
        padding         => padding_all(16),
        childGap        => 8,
        layoutDirection => CLAY_TOP_TO_BOTTOM,
    },
    backgroundColor => [240, 240, 240, 255],
});

    Clay__OpenElementWithId( Clay_GetElementId("header") );
    Clay__ConfigureOpenElement({
        layout          => { sizing => { width => sizing_grow(), height => sizing_fixed(40) } },
        backgroundColor => [50, 100, 200, 255],
        cornerRadius    => corner_radius_all(4),
    });
        Clay__OpenTextElement(
            "Clay::XS demo",
            { fontSize => 18, textColor => [255, 255, 255, 255] },
        );
    Clay__CloseElement();

    Clay__OpenElementWithId( Clay_GetElementId("body") );
    Clay__ConfigureOpenElement({
        layout          => { sizing => { width => sizing_grow(), height => sizing_grow() } },
        backgroundColor => [255, 255, 255, 255],
        border          => { color => [200, 200, 200, 255], width => border_all(1) },
        cornerRadius    => corner_radius_all(4),
    });
    Clay__CloseElement();

Clay__CloseElement();

my $commands = Clay_EndLayout(0);

# Pretty-print the render commands. A real application would dispatch
# on $cmd->{commandType} to draw each one.
print JSON::PP->new->canonical(1)->pretty->encode($commands);
