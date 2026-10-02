#!/usr/bin/env perl

# 08-ui-stack.pl - Stack layout with Clay::UI: any widget with a layout
# slice puts its children on top of each other once it sets
# layout_direction => CLAY_BACK_TO_FRONT. Later children are drawn over
# earlier ones, and child_alignment places every child on its own.
# Rendered to SVG.
#
# The page shows three uses:
#   - the nine child_alignment combinations, one marker per stack,
#   - avatars with a status badge in the corner (the avatar itself is a
#     stack that centers its initials),
#   - a layered photo card: a GROW background, a caption bar at the bottom
#     and tags in the top corners. A stack has one child_alignment, so each
#     tag sits in a GROW wrapper stack that carries its own.
#
# Run with:
#
#     perl -Ilib -Iblib/lib -Iblib/arch examples/08-ui-stack.pl > /tmp/stack.svg
#     xdg-open /tmp/stack.svg   # or open it in a browser


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
my $CELL_BG  = [50,  58,  72, 255];
my $MARKER   = [240, 170,  60, 255];
my $PHOTO    = [70, 110, 150, 255];
my $SHADE    = [10,  12,  16, 180];
my $TAG_BG   = [200,  70,  80, 255];
my $WHITE    = [240, 240, 245, 255];

my %STATUS_COLOR = (
	online  => [ 80, 190, 110, 255],
	away    => [230, 180,  60, 255],
	busy    => [220,  80,  80, 255],
	offline => [130, 135, 145, 255],
);

sub label ($text, $font_size = 16) {
	return Clay::UI::Demo::Text->new(
		text       => $text,
		font_size  => $font_size,
		text_color => $WHITE,
	);
}

sub fixed_box ($width, $height, %style) {
	return Clay::UI::Demo::Box->new(
		layout => { sizing => { width => sizing_fixed($width), height => sizing_fixed($height) } },
		%style,
	);
}

sub panel (@children) {
	my $panel = Clay::UI::Demo::Box->new(
		layout => {
			sizing    => { width => sizing_grow() },
			padding   => padding_all(12),
			child_gap => 10,
		},
		background_color => $PANEL_BG,
	);
	$panel->add_child(@children);
	return $panel;
}

# One stack per child_alignment combination, each with a single marker.
sub alignment_cell ($x, $y) {
	my $cell = Clay::UI::Demo::Box->new(
		layout => {
			sizing           => { width => sizing_fixed(52), height => sizing_fixed(52) },
			padding          => padding_all(6),
			child_alignment  => { x => $x, y => $y },
			layout_direction => CLAY_BACK_TO_FRONT,
		},
		background_color => $CELL_BG,
	);
	$cell->add_child(fixed_box(16, 16, background_color => $MARKER, corner_radius => 3));
	return $cell;
}

# A stack fitting the avatar, with the badge drawn over its bottom right
# corner. The avatar is a stack too: it centers the initials on its disc.
sub avatar ($initials, $color, $status) {
	my $disc = Clay::UI::Demo::Box->new(
		layout => {
			sizing           => { width => sizing_fixed(64), height => sizing_fixed(64) },
			child_alignment  => { x => CLAY_ALIGN_X_CENTER, y => CLAY_ALIGN_Y_CENTER },
			layout_direction => CLAY_BACK_TO_FRONT,
		},
		background_color => $color,
		corner_radius    => 32,
	);
	$disc->add_child(label($initials, 22));

	my $avatar = Clay::UI::Demo::Box->new(
		layout => {
			child_alignment  => { x => CLAY_ALIGN_X_RIGHT, y => CLAY_ALIGN_Y_BOTTOM },
			layout_direction => CLAY_BACK_TO_FRONT,
		},
	);
	$avatar->add_child($disc, fixed_box(18, 18,
		background_color => $STATUS_COLOR{$status},
		corner_radius    => 9,
		border_color     => $PANEL_BG,
		border_width     => 3,
	));

	my $column = Clay::UI::Demo::Box->new(
		layout => {
			child_gap        => 6,
			child_alignment  => { x => CLAY_ALIGN_X_CENTER },
			layout_direction => CLAY_TOP_TO_BOTTOM,
		},
	);
	$column->add_child($avatar, label($status, 13));
	return $column;
}

sub tag ($text) {
	my $tag = Clay::UI::Demo::Box->new(
		layout           => { padding => { left => 8, right => 8, top => 4, bottom => 4 } },
		background_color => $TAG_BG,
		corner_radius    => 4,
	);
	$tag->add_child(label($text, 13));
	return $tag;
}

# A GROW stack covering its parent stack, placing one child in a corner of
# its own choosing.
sub corner ($x, $y, $child) {
	my $corner = Clay::UI::Demo::Box->new(
		layout => {
			sizing           => { width => sizing_grow(), height => sizing_grow() },
			padding          => padding_all(10),
			child_alignment  => { x => $x, y => $y },
			layout_direction => CLAY_BACK_TO_FRONT,
		},
	);
	$corner->add_child($child);
	return $corner;
}

# Back to front: the photo, the caption bar the card aligns to its bottom,
# then the corner tags.
sub photo_card () {
	my $card = Clay::UI::Demo::Box->new(
		layout => {
			sizing           => { width => sizing_grow(), height => sizing_fixed(200) },
			child_alignment  => { y => CLAY_ALIGN_Y_BOTTOM },
			layout_direction => CLAY_BACK_TO_FRONT,
		},
	);
	my $photo = Clay::UI::Demo::Box->new(
		layout           => { sizing => { width => sizing_grow(), height => sizing_grow() } },
		background_color => $PHOTO,
		corner_radius    => 8,
	);
	my $caption = Clay::UI::Demo::Box->new(
		layout => {
			sizing          => { width => sizing_grow(), height => sizing_fixed(44) },
			padding         => { left => 12, right => 12 },
			child_alignment => { y => CLAY_ALIGN_Y_CENTER },
		},
		background_color => $SHADE,
	);
	$caption->add_child(label('Lake at dawn', 18));
	$card->add_child(
		$photo,
		$caption,
		corner(CLAY_ALIGN_X_LEFT,  CLAY_ALIGN_Y_TOP, tag('NEW')),
		corner(CLAY_ALIGN_X_RIGHT, CLAY_ALIGN_Y_TOP, tag('12 likes')),
	);
	return $card;
}

sub build_tree () {
	my $alignments = panel(map {
		my $y = $_;
		map { alignment_cell($_, $y) } CLAY_ALIGN_X_LEFT, CLAY_ALIGN_X_CENTER, CLAY_ALIGN_X_RIGHT;
	} CLAY_ALIGN_Y_TOP, CLAY_ALIGN_Y_CENTER, CLAY_ALIGN_Y_BOTTOM);

	my $avatars = panel(
		avatar('AL', [120,  90, 170, 255], 'online'),
		avatar('BK', [ 60, 130, 120, 255], 'away'),
		avatar('CM', [170, 100,  70, 255], 'busy'),
		avatar('DS', [ 90, 100, 130, 255], 'offline'),
	);
	$avatars->layout({ %{ $avatars->layout }, child_gap => 28 });

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
		label('child_alignment places each child on its own', 20), $alignments,
		label('Avatars with a status badge drawn on top', 20), $avatars,
		label('A layered card: photo, caption, corner tags', 20), photo_card(),
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
