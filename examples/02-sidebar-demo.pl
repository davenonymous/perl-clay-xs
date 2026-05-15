#!/usr/bin/env perl

# 02-sidebar-demo.pl - Port of the README's sidebar example.
#
# Reproduces the layout shown in clay's README using only the low-level
# Clay::Layout primitives. Demonstrates loops, helper subs, hover state,
# and a complete two-pass interactive pipeline.
#
# Run with:
#
#     perl -Ilib -Iblib/lib -Iblib/arch examples/02-sidebar-demo.pl

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Clay::Layout qw(:all);
use JSON::PP;

my $COLOR_LIGHT  = [224, 215, 210, 255];
my $COLOR_RED    = [168,  66,  28, 255];
my $COLOR_ORANGE = [225, 138,  50, 255];

# A reusable "sidebar item" component. Just a Perl sub.
sub sidebar_item ($index) {
    Clay__OpenElementWithId( Clay_GetElementIdWithIndex("SidebarItem", $index) );
    Clay__ConfigureOpenElement({
        layout          => { sizing => { width => sizing_grow(), height => sizing_fixed(50) } },
        backgroundColor => $COLOR_ORANGE,
    });
    Clay__CloseElement();
}

my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 1024, height => 768 },
    sub ($err, $userdata) { warn "Clay error: $err->{errorText}\n" },
);

Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
    my $fs = $config->{fontSize} || 16;
    return { width => length($text) * $fs * 0.55, height => $fs };
});

sub build_layout () {
    Clay__OpenElementWithId( Clay_GetElementId("OuterContainer") );
    Clay__ConfigureOpenElement({
        layout => {
            sizing   => { width => sizing_grow(), height => sizing_grow() },
            padding  => padding_all(16),
            childGap => 16,
        },
        backgroundColor => [250, 250, 255, 255],
    });

        Clay__OpenElementWithId( Clay_GetElementId("SideBar") );
        Clay__ConfigureOpenElement({
            layout => {
                layoutDirection => CLAY_TOP_TO_BOTTOM,
                sizing          => { width  => sizing_fixed(300), height => sizing_grow() },
                padding         => padding_all(16),
                childGap        => 16,
            },
            backgroundColor => $COLOR_LIGHT,
        });

            Clay__OpenElementWithId( Clay_GetElementId("ProfilePictureOuter") );
            Clay__ConfigureOpenElement({
                layout => {
                    sizing         => { width => sizing_grow() },
                    padding        => padding_all(16),
                    childGap       => 16,
                    childAlignment => { x => CLAY_ALIGN_X_LEFT, y => CLAY_ALIGN_Y_CENTER },
                },
                backgroundColor => $COLOR_RED,
            });
                Clay__OpenElementWithId( Clay_GetElementId("ProfilePicture") );
                Clay__ConfigureOpenElement({
                    layout => { sizing => { width => sizing_fixed(60), height => sizing_fixed(60) } },
                });
                Clay__CloseElement();

                Clay__OpenTextElement(
                    "Clay - UI Library",
                    { fontSize => 24, textColor => [255, 255, 255, 255] },
                );
            Clay__CloseElement();

            sidebar_item($_) for 0 .. 4;

        Clay__CloseElement();

        Clay__OpenElementWithId( Clay_GetElementId("MainContent") );
        Clay__ConfigureOpenElement({
            layout          => { sizing => { width => sizing_grow(), height => sizing_grow() } },
            backgroundColor => $COLOR_LIGHT,
        });
        Clay__CloseElement();

    Clay__CloseElement();
}

# First frame: build geometry. We need this before pointer interaction
# can detect anything.
Clay_BeginLayout();
build_layout();
my $frame1 = Clay_EndLayout(0);
printf "Frame 1: %d render commands\n", scalar @$frame1;

# Second frame: simulate a pointer hover over the third sidebar item.
Clay_SetPointerState({ x => 160, y => 320 }, 0);
Clay_BeginLayout();
build_layout();
my $frame2 = Clay_EndLayout(0);

my @over = @{ Clay_GetPointerOverIds() };
printf "Frame 2: %d elements under pointer\n", scalar @over;
for my $id (@over) {
    printf "  id=%u\n", $id->{id};
}

# Print the per-type breakdown so the reader can see what the renderer
# would have to handle.
my %by_type;
$by_type{ $_->{commandType} }++ for @$frame2;
print "\nRender command type breakdown:\n";
for my $type (sort keys %by_type) {
    my $name = (
        CLAY_RENDER_COMMAND_TYPE_RECTANGLE() == $type ? 'RECTANGLE' :
        CLAY_RENDER_COMMAND_TYPE_TEXT()      == $type ? 'TEXT'      :
        CLAY_RENDER_COMMAND_TYPE_BORDER()    == $type ? 'BORDER'    :
        CLAY_RENDER_COMMAND_TYPE_IMAGE()     == $type ? 'IMAGE'     :
        "type=$type"
    );
    printf "  %-12s %d\n", $name, $by_type{$type};
}
