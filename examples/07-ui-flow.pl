#!/usr/bin/env perl

# 07-ui-flow.pl - Flow layout with Clay::UI: any widget with a layout slice
# wraps its children onto new lines once it sets
# layout_direction => CLAY_LEFT_TO_RIGHT_WRAP. Rendered to SVG.
#
# The page shows two wrap containers:
#   - a tag cloud whose lines keep their natural height
#     (line_sizing => CLAY_LINE_SIZING_FIT) and are centered line by line,
#   - a fixed-height gallery whose lines share the leftover height
#     (CLAY_LINE_SIZING_GROW, the default), with separators drawn between
#     neighbours and between lines (border_width => { between_children }).
#
# Run with:
#
#     perl -Ilib -Iblib/lib -Iblib/arch examples/07-ui-flow.pl > /tmp/flow.svg
#     xdg-open /tmp/flow.svg   # or open it in a browser

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use lib "examples/lib";

use Clay::XS qw(:all);
use Clay::UI;
use Clay::UI::Demo::Box;
use Clay::UI::Demo::Text;

# ---------------------------------------------------------------------------
# SVG renderer (lifted from examples/03-svg-render.pl).
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

sub render_text ($cmd) {
	my $b = $cmd->{boundingBox};
	my $d = $cmd->{renderData};
	return sprintf
		qq{  <text x="%g" y="%g" font-size="%g" font-family="sans-serif" fill="%s" xml:space="preserve">%s</text>\n},
		$b->{x}, $b->{y} + $b->{height} - 4, $d->{fontSize},
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
# Layout.
# ---------------------------------------------------------------------------

my $PAGE_BG  = [22,  26,  32, 255];
my $PANEL_BG = [34,  40,  50, 255];
my $TAG_BG   = [55,  90, 140, 255];
my $CARD_BG  = [60,  70,  86, 255];
my $LINE     = [110, 120, 140, 255];
my $WHITE    = [240, 240, 245, 255];

sub label ($text, $font_size = 16) {
	return Clay::UI::Demo::Text->new(
		text       => $text,
		font_size  => $font_size,
		text_color => $WHITE,
	);
}

sub tag ($text) {
	my $tag = Clay::UI::Demo::Box->new(
		layout           => { padding => { left => 10, right => 10, top => 4, bottom => 4 } },
		background_color => $TAG_BG,
		corner_radius    => 10,
	);
	$tag->add_child(label($text, 14));
	return $tag;
}

sub card ($title, $width) {
	my $card = Clay::UI::Demo::Box->new(
		layout => {
			sizing           => { width => sizing_grow($width), height => sizing_grow() },
			padding          => padding_all(10),
			child_alignment  => { y => CLAY_ALIGN_Y_CENTER },
		},
		background_color => $CARD_BG,
	);
	$card->add_child(label($title));
	return $card;
}

sub build_tree () {
	my $tags = Clay::UI::Demo::Box->new(
		layout => {
			sizing           => { width => sizing_grow() },
			padding          => padding_all(12),
			child_gap        => 8,
			line_gap         => 8,
			child_alignment  => { x => CLAY_ALIGN_X_CENTER },
			layout_direction => CLAY_LEFT_TO_RIGHT_WRAP,
			line_sizing      => CLAY_LINE_SIZING_FIT,
		},
		background_color => $PANEL_BG,
	);
	$tags->add_child(tag($_)) for qw(
		perl layout clay xs flexbox wrap lines gaps alignment
		sizing-groups grids scrolling transitions render-commands svg
	);

	my $gallery = Clay::UI::Demo::Box->new(
		layout => {
			sizing           => { width => sizing_grow(), height => sizing_fixed(260) },
			padding          => padding_all(12),
			child_gap        => 12,
			line_gap         => 12,
			layout_direction => CLAY_LEFT_TO_RIGHT_WRAP,
		},
		background_color => $PANEL_BG,
		border_color     => $LINE,
		border_width     => { between_children => 2 },
	);
	$gallery->add_child(card(@$_)) for (
		[ 'Mountains', 180 ], [ 'Harbour', 140 ], [ 'Old town', 160 ],
		[ 'Forest', 120 ], [ 'Lake at dawn', 220 ], [ 'Market', 130 ], [ 'Bridge', 150 ],
	);

	my $page = Clay::UI::Demo::Box->new(
		id     => 'Page',
		layout => {
			sizing           => { width => sizing_grow(), height => sizing_grow() },
			padding          => padding_all(24),
			child_gap        => 16,
			layout_direction => CLAY_TOP_TO_BOTTOM,
		},
		background_color => $PAGE_BG,
	);
	$page->add_child(
		label('Tags (lines fit their content, centered)', 20), $tags,
		label('Gallery (lines grow into the leftover height)', 20), $gallery,
	);
	return $page;
}

my ($W, $H) = (640, 600);

my $ui = Clay::UI->new(
	width         => $W,
	height        => $H,
	root          => build_tree(),
	measure_text  => sub ($text, $config, $userdata) {
		my $fs = $config->{fontSize} || 16;
		return { width => length($text) * $fs * 0.55, height => $fs };
	},
	error_handler => sub ($err, $userdata) { warn "Clay error: $err->{errorText}\n" },
);

my $commands = $ui->render;
print render_to_svg($commands, $W, $H);
