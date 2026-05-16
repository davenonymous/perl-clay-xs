#!/usr/bin/env perl

# 06-png-render.pl - Render Clay's command list as a PNG image via Imager.
#
# Builds the same kind of showcase layout as the SVG demo, then walks the
# render commands and rasterises them with Imager (https://metacpan.org/pod/Imager).
# Text uses JetBrains Mono - point CLAY_FONT_PATH at the TTF if it lives
# somewhere other than the defaults probed below.
#
# Requires Imager with PNG output (Imager::File::PNG) and a FreeType-capable
# font driver (Imager::Font::FT2).
#
# Run with:
#
#     perl -Ilib -Iblib/lib -Iblib/arch examples/06-png-render.pl out.png

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Imager;
use Clay::Layout qw(:all);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;

# ---------------------------------------------------------------------------
# Font resolution
# ---------------------------------------------------------------------------

sub locate_font () {
    return $ENV{CLAY_FONT_PATH} if $ENV{CLAY_FONT_PATH} && -r $ENV{CLAY_FONT_PATH};

    my @candidates = (
        '/usr/share/fonts/truetype/jetbrains-mono/JetBrainsMono-Regular.ttf',
        '/usr/share/fonts/TTF/JetBrainsMono-Regular.ttf',
        '/usr/local/share/fonts/JetBrainsMono-Regular.ttf',
        '/tmp/jbmono/fonts/ttf/JetBrainsMono-Regular.ttf',
        "$ENV{HOME}/.local/share/fonts/JetBrainsMono-Regular.ttf",
    );
    for my $path (@candidates) {
        return $path if -r $path;
    }
    die "Could not find JetBrainsMono-Regular.ttf. Set CLAY_FONT_PATH to the TTF file.\n";
}

my $FONT_PATH = locate_font();
my $FONT      = Imager::Font->new(file => $FONT_PATH)
    or die "Imager font load failed ($FONT_PATH): " . Imager->errstr . "\n";

# ---------------------------------------------------------------------------
# PNG renderer
# ---------------------------------------------------------------------------

sub imager_color ($c) {
    return Imager::Color->new($c->{r}, $c->{g}, $c->{b}, $c->{a});
}

# Clay reports four independent corner radii. Imager's box() takes a single
# radius, so we pick the largest non-zero one and accept slight rounding
# differences between rectangles whose corners disagree.
sub corner_radius ($cr) {
    return 0 unless $cr;
    my $max = 0;
    for my $r ($cr->{topLeft}, $cr->{topRight}, $cr->{bottomLeft}, $cr->{bottomRight}) {
        $max = $r if $r > $max;
    }
    return $max;
}

sub draw_rectangle ($img, $cmd) {
    my $b = $cmd->{boundingBox};
    my $d = $cmd->{renderData};
    $img->box(
        color  => imager_color($d->{backgroundColor}),
        xmin   => $b->{x},
        ymin   => $b->{y},
        xmax   => $b->{x} + $b->{width}  - 1,
        ymax   => $b->{y} + $b->{height} - 1,
        filled => 1,
        r      => corner_radius($d->{cornerRadius}),
    );
}

# Borders may have different per-edge widths. Imager has no native uneven
# border, so each edge is filled as its own rectangle along the bounding box.
sub draw_border ($img, $cmd) {
    my $b   = $cmd->{boundingBox};
    my $d   = $cmd->{renderData};
    my $w   = $d->{width};
    my $col = imager_color($d->{color});
    my ($x, $y, $bw, $bh) = ($b->{x}, $b->{y}, $b->{width}, $b->{height});

    my $edge = sub ($xmin, $ymin, $xmax, $ymax) {
        return if $xmax < $xmin || $ymax < $ymin;
        $img->box(color => $col, xmin => $xmin, ymin => $ymin,
                  xmax => $xmax, ymax => $ymax, filled => 1);
    };
    $edge->($x, $y, $x + $bw - 1, $y + $w->{top} - 1)                if $w->{top};
    $edge->($x, $y + $bh - $w->{bottom}, $x + $bw - 1, $y + $bh - 1) if $w->{bottom};
    $edge->($x, $y, $x + $w->{left} - 1, $y + $bh - 1)               if $w->{left};
    $edge->($x + $bw - $w->{right}, $y, $x + $bw - 1, $y + $bh - 1)  if $w->{right};
}

# Clay's text bounding box is already laid out for the configured fontSize.
# Imager's string() places the baseline at the given y, so we offset down
# from the box top by roughly the font ascent (fontSize * 0.8).
sub draw_text ($img, $cmd) {
    my $b = $cmd->{boundingBox};
    my $d = $cmd->{renderData};
    my $fs = $d->{fontSize};
    $img->string(
        font   => $FONT,
        text   => $d->{stringContents},
        x      => $b->{x},
        y      => $b->{y} + $fs * 0.8,
        size   => $fs,
        color  => imager_color($d->{textColor}),
        aa     => 1,
    );
}

sub render_to_png ($commands, $width, $height, $path) {
    my $img = Imager->new(xsize => $width, ysize => $height, channels => 4);
    $img->box(color => Imager::Color->new(0, 0, 0, 0), filled => 1);

    my @sorted = sort { ($a->{zIndex} // 0) <=> ($b->{zIndex} // 0) } @$commands;
    for my $cmd (@sorted) {
        my $type = $cmd->{commandType};
        if    ($type == CLAY_RENDER_COMMAND_TYPE_RECTANGLE) { draw_rectangle($img, $cmd) }
        elsif ($type == CLAY_RENDER_COMMAND_TYPE_BORDER)    { draw_border($img, $cmd) }
        elsif ($type == CLAY_RENDER_COMMAND_TYPE_TEXT)      { draw_text($img, $cmd) }
        # IMAGE and custom commands are intentionally ignored.
    }

    $img->write(file => $path)
        or die "Imager write failed ($path): " . $img->errstr . "\n";
}

# ---------------------------------------------------------------------------
# Demo layout
# ---------------------------------------------------------------------------

my $out = $ARGV[0] // 'out.png';
my ($W, $H) = (720, 360);

my $WHITE = [255, 255, 255, 255];

my $LOREM = 'Clay reflows this sentence to fit the card width, '
          . 'breaking on word boundaries so each alignment value '
          . 'can be compared side by side.';

my @ALIGN_DEMO = (
    [ 'left',   CLAY_TEXT_ALIGN_LEFT   ],
    [ 'center', CLAY_TEXT_ALIGN_CENTER ],
    [ 'right',  CLAY_TEXT_ALIGN_RIGHT  ],
);

sub label ($text, $font_size = 16) {
    return Clay::UI::Text->new(
        text       => $text,
        font_size  => $font_size,
        text_color => $WHITE,
    );
}

sub build_tree () {
    my @cards;
    for my $i (0 .. 2) {
        my ($name, $align) = @{ $ALIGN_DEMO[$i] };
        push @cards, Clay::UI::Box->new(
            id => "card-$i",
            layout => {
                sizing           => { width => sizing_grow(), height => sizing_grow() },
                padding          => padding_all(10),
                child_gap        => 8,
                layout_direction => CLAY_TOP_TO_BOTTOM,
            },
            background_color => [225 - $i * 40, 138, 50 + $i * 30, 255],
            corner_radius    => 4,
            children         => [
                label("card $i ($name)"),
                Clay::UI::Text->new(
                    text           => $LOREM,
                    font_size      => 14,
                    text_color     => $WHITE,
                    text_alignment => $align,
                ),
            ],
        );
    }

    return Clay::UI::Box->new(
        id => 'root',
        layout => {
            sizing           => { width => sizing_grow(), height => sizing_grow() },
            padding          => padding_all(16),
            child_gap        => 12,
            layout_direction => CLAY_TOP_TO_BOTTOM,
        },
        background_color => [245, 246, 250, 255],
        children => [
            Clay::UI::Box->new(
                id => 'header',
                layout => {
                    sizing          => { width => sizing_grow(), height => sizing_fixed(48) },
                    padding         => padding_all(12),
                    child_alignment => { x => CLAY_ALIGN_X_LEFT, y => CLAY_ALIGN_Y_CENTER },
                },
                background_color => [50, 100, 200, 255],
                corner_radius    => 6,
                children         => [ label("Clay -> PNG demo", 20) ],
            ),
            Clay::UI::Box->new(
                id => 'body',
                layout => {
                    sizing    => { width => sizing_grow(), height => sizing_grow() },
                    padding   => padding_all(12),
                    child_gap => 12,
                },
                background_color => $WHITE,
                border_color     => [200, 200, 210, 255],
                border_width     => 2,
                corner_radius    => 6,
                children         => \@cards,
            ),
        ],
    );
}

my $ui = Clay::UI->new(
    width        => $W,
    height       => $H,
    root         => build_tree(),
    measure_text => sub ($text, $config, $userdata) {
        my $fs   = $config->{fontSize} || 16;
        my $bbox = $FONT->bounding_box(string => $text, size => $fs);
        return {
            width  => $bbox ? $bbox->advance_width : length($text) * $fs * 0.6,
            height => $fs,
        };
    },
    error_handler => sub ($err, $userdata) { warn "Clay error: $err->{errorText}\n" },
);

my $commands = $ui->render;
render_to_png($commands, $W, $H, $out);
print "Wrote $out\n";

# Tear down in a defined order so Imager's font is freed before global
# destruction touches it. The Clay context retains the measure-text closure
# that captures $FONT; if Perl frees Imager state first the closure crashes.
undef $ui;
undef $FONT;
