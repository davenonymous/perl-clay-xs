#!/usr/bin/env perl

# 03-svg-render.pl - Render Clay's command list as an SVG image.
#
# Provides a generic render_to_svg(\@commands, $width, $height) function
# that handles RECTANGLE, BORDER, and TEXT commands (the three types this
# binding emits today; IMAGE is acknowledged but skipped). Demo builds a
# small showcase layout and prints the SVG to stdout.
#
# Run with:
#
#     perl -Ilib -Iblib/lib -Iblib/arch examples/03-svg-render.pl > out.svg

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Clay::XS qw(:all);

# ---------------------------------------------------------------------------
# SVG renderer
# ---------------------------------------------------------------------------

sub xml_escape ($text) {
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    return $text;
}

sub rgba_to_css ($c) {
    return sprintf 'rgba(%d,%d,%d,%.3f)', $c->{r}, $c->{g}, $c->{b}, $c->{a} / 255;
}

# Clay stores per-corner radii; SVG <rect> only supports a single rx/ry. When
# the four corners differ we approximate with rx = average, which is the
# pragmatic choice for a debug/preview renderer.
sub corner_radius ($cr) {
    return 0 unless $cr;
    my @r = ($cr->{topLeft}, $cr->{topRight}, $cr->{bottomLeft}, $cr->{bottomRight});
    my $sum = 0; $sum += $_ for @r;
    return $sum / 4;
}

sub render_rectangle ($cmd) {
    my $b  = $cmd->{boundingBox};
    my $d  = $cmd->{renderData};
    my $r  = corner_radius($d->{cornerRadius});
    my $rx = $r ? sprintf(' rx="%g" ry="%g"', $r, $r) : '';
    return sprintf
        qq{  <rect x="%g" y="%g" width="%g" height="%g"%s fill="%s"/>\n},
        $b->{x}, $b->{y}, $b->{width}, $b->{height}, $rx,
        rgba_to_css($d->{backgroundColor});
}

# Borders in Clay can have independent top/right/bottom/left widths. SVG's
# native stroke is uniform, so we emit one <line> per non-zero edge. Corner
# radii on borders are uncommon and ignored for clarity.
sub render_border ($cmd) {
    my $b   = $cmd->{boundingBox};
    my $d   = $cmd->{renderData};
    my $w   = $d->{width};
    my $css = rgba_to_css($d->{color});
    my ($x, $y, $bw, $bh) = ($b->{x}, $b->{y}, $b->{width}, $b->{height});

    my @lines;
    my $edge = sub ($width, $x1, $y1, $x2, $y2) {
        return unless $width;
        push @lines, sprintf
            qq{  <line x1="%g" y1="%g" x2="%g" y2="%g" stroke="%s" stroke-width="%g"/>\n},
            $x1, $y1, $x2, $y2, $css, $width;
    };
    $edge->($w->{top},    $x,       $y,       $x + $bw, $y);
    $edge->($w->{bottom}, $x,       $y + $bh, $x + $bw, $y + $bh);
    $edge->($w->{left},   $x,       $y,       $x,       $y + $bh);
    $edge->($w->{right},  $x + $bw, $y,       $x + $bw, $y + $bh);
    return join '', @lines;
}

# Clay reports the text bounding box already laid out for the configured
# fontSize, so we place the baseline near the bottom of that box. SVG's
# <text> y is the baseline, so y = box.y + box.height gets us close enough
# for a preview without needing real font metrics.
sub render_text ($cmd) {
    my $b = $cmd->{boundingBox};
    my $d = $cmd->{renderData};
    return sprintf
        qq{  <text x="%g" y="%g" font-size="%g" font-family="sans-serif" fill="%s" xml:space="preserve">%s</text>\n},
        $b->{x}, $b->{y} + $b->{height}, $d->{fontSize},
        rgba_to_css($d->{textColor}),
        xml_escape($d->{stringContents});
}

sub render_to_svg ($commands, $width, $height) {
    my @sorted = sort { ($a->{zIndex} // 0) <=> ($b->{zIndex} // 0) } @$commands;

    my $svg = sprintf
        qq{<svg xmlns="http://www.w3.org/2000/svg" width="%g" height="%g" viewBox="0 0 %g %g">\n},
        $width, $height, $width, $height;

    for my $cmd (@sorted) {
        my $type = $cmd->{commandType};
        $svg .=
            $type == CLAY_RENDER_COMMAND_TYPE_RECTANGLE ? render_rectangle($cmd) :
            $type == CLAY_RENDER_COMMAND_TYPE_BORDER    ? render_border($cmd)    :
            $type == CLAY_RENDER_COMMAND_TYPE_TEXT      ? render_text($cmd)      :
            sprintf(qq{  <!-- skipped commandType=%d -->\n}, $type);
    }

    $svg .= "</svg>\n";
    return $svg;
}

# ---------------------------------------------------------------------------
# Demo layout
# ---------------------------------------------------------------------------

my ($W, $H) = (480, 280);

my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => $W, height => $H },
    sub ($err, $userdata) { warn "Clay error: $err->{errorText}\n" },
);

# Monospace approximation. Good enough to place text inside its box.
Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
    my $fs = $config->{fontSize} || 16;
    return { width => length($text) * $fs * 0.55, height => $fs };
});

Clay_BeginLayout();

Clay__OpenElementWithId( Clay_GetElementId("root") );
Clay__ConfigureOpenElement({
    layout => {
        sizing          => { width => sizing_grow(), height => sizing_grow() },
        padding         => padding_all(16),
        childGap        => 12,
        layoutDirection => CLAY_TOP_TO_BOTTOM,
    },
    backgroundColor => [245, 246, 250, 255],
});

    Clay__OpenElementWithId( Clay_GetElementId("header") );
    Clay__ConfigureOpenElement({
        layout          => {
            sizing         => { width => sizing_grow(), height => sizing_fixed(48) },
            padding        => padding_all(12),
            childAlignment => { x => CLAY_ALIGN_X_LEFT, y => CLAY_ALIGN_Y_CENTER },
        },
        backgroundColor => [50, 100, 200, 255],
        cornerRadius    => corner_radius_all(6),
    });
        Clay__OpenTextElement(
            "Clay -> SVG demo",
            { fontSize => 20, textColor => [255, 255, 255, 255] },
        );
    Clay__CloseElement();

    Clay__OpenElementWithId( Clay_GetElementId("body") );
    Clay__ConfigureOpenElement({
        layout => {
            sizing   => { width => sizing_grow(), height => sizing_grow() },
            padding  => padding_all(12),
            childGap => 12,
        },
        backgroundColor => [255, 255, 255, 255],
        border          => { color => [200, 200, 210, 255], width => border_all(2) },
        cornerRadius    => corner_radius_all(6),
    });

        for my $i (0 .. 2) {
            Clay__OpenElementWithId( Clay_GetElementIdWithIndex("card", $i) );
            Clay__ConfigureOpenElement({
                layout => {
                    sizing         => { width => sizing_grow(), height => sizing_grow() },
                    padding        => padding_all(8),
                    childAlignment => { x => CLAY_ALIGN_X_CENTER, y => CLAY_ALIGN_Y_CENTER },
                },
                backgroundColor => [225 - $i * 40, 138, 50 + $i * 30, 255],
                cornerRadius    => corner_radius_all(4),
            });
                Clay__OpenTextElement(
                    "card $i",
                    { fontSize => 16, textColor => [255, 255, 255, 255] },
                );
            Clay__CloseElement();
        }

    Clay__CloseElement();

Clay__CloseElement();

my $commands = Clay_EndLayout(0);
print render_to_svg($commands, $W, $H);
