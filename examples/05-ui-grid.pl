#!/usr/bin/env perl

# 05-ui-grid.pl - Auto-sized data table built with Clay::UI::Grid,
# rendered to SVG so you can visually confirm the per-column auto-fit.
#
# Each column shrink-wraps to its widest cell across all rows in a
# single layout pass, courtesy of the sizing-group patch on Clay.
#
# Run with:
#
#     perl -Ilib -Iblib/lib -Iblib/arch examples/05-ui-grid.pl > /tmp/grid.svg
#     xdg-open /tmp/grid.svg   # or open it in a browser

use v5.22;
use warnings;
use feature 'signatures';

use lib "examples/lib";
no warnings 'experimental::signatures';

use Clay::XS qw(:all);
use Clay::UI;
use Clay::UI::Demo::Box;
use Clay::UI::Grid::Cell;
use Clay::UI::Demo::Text;
use Clay::UI::Demo::Grid;

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
# Layout: a page-wide grid with deliberately uneven column widths to make
# the auto-fit obvious in the rendered SVG. Cell styling is applied to the
# Grid wrapper (which carries the equalized column width); the cell content
# is a plain Text leaf, so what you see in the SVG IS the equalized box.
# ---------------------------------------------------------------------------

my $HEADER_BG = [55,  90, 140, 255];
my $CELL_BG   = [40,  46,  56, 255];
my $ALT_BG    = [50,  56,  68, 255];
my $BORDER    = [90, 100, 120, 255];
my $WHITE     = [240, 240, 245, 255];

sub label ($text, $font_size = 16) {
	return Clay::UI::Demo::Text->new(
		text       => $text,
		font_size  => $font_size,
		text_color => $WHITE,
	);
}

sub header_cell ($text) {
	my $cell = Clay::UI::Grid::Cell->new(
		layout           => { padding => { left => 12, right => 12, top => 8, bottom => 8 } },
		background_color => $HEADER_BG,
		border_color     => $BORDER,
		border_width     => 1,
	);
	$cell->add_child(label($text, 18));
	return $cell;
}

sub body_cell ($text, $r) {
	my $cell = Clay::UI::Grid::Cell->new(
		layout           => { padding => { left => 12, right => 12, top => 8, bottom => 8 } },
		background_color => ($r % 2 ? $ALT_BG : $CELL_BG),
		border_color     => $BORDER,
		border_width     => 1,
	);
	$cell->add_child(label($text));
	return $cell;
}

my ($W, $H) = (820, 320);

my @data = (
	[ 'Region',           'Q1',     'Q2',     'Q3',     'Q4 forecast' ],
	[ 'North America',    '$1.2M',  '$1.5M',  '$1.8M',  '$2.1M'       ],
	[ 'Europe',           '$0.9M',  '$1.1M',  '$1.3M',  '$1.4M'       ],
	[ 'APAC',             '$0.4M',  '$0.7M',  '$1.0M',  '$1.3M'       ],
	[ 'Latin America',    '$0.2M',  '$0.3M',  '$0.5M',  '$0.7M'       ],
);

sub build_tree () {
	my $grid = Clay::UI::Demo::Grid->new(
		id       => 'Report',
		cell_gap => 0,
		row_gap  => 0,
	);
	$grid->append_row([ map { header_cell($_) } @{ $data[0] } ]);
	for my $r (1 .. $#data) {
		$grid->append_row([ map { body_cell($_, $r) } @{ $data[$r] } ]);
	}

	my $page = Clay::UI::Demo::Box->new(
		id => 'Page',
		layout => {
			sizing           => { width => sizing_grow(), height => sizing_grow() },
			padding          => padding_all(24),
			child_gap        => 16,
			layout_direction => CLAY_TOP_TO_BOTTOM,
		},
		background_color => [22, 26, 32, 255],
	);
	$page->add_child(
		Clay::UI::Demo::Text->new(
			text       => 'Quarterly numbers (auto-sized grid)',
			font_size  => 22,
			text_color => $WHITE,
		),
		$grid,
	);
	return $page;
}

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
