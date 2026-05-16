#!/usr/bin/env perl

# 04-ui-sidebar.pl - The 02-sidebar-demo.pl layout, rebuilt on Clay::UI.
#
# Same render output as the low-level version; the only difference is
# the surface area. Open / configure / close calls are replaced by
# Clay::UI::Box / Text / layout walk.
#
# Run with:
#
#     perl -Ilib -Iblib/lib -Iblib/arch examples/04-ui-sidebar.pl

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Clay::Layout qw(:all);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;

my $COLOR_LIGHT  = [224, 215, 210, 255];
my $COLOR_RED    = [168,  66,  28, 255];
my $COLOR_ORANGE = [225, 138,  50, 255];

sub sidebar_item ($index) {
	return Clay::UI::Box->new(
		id               => "SidebarItem-$index",
		layout           => { sizing => { width => sizing_grow(), height => sizing_fixed(50) } },
		background_color => $COLOR_ORANGE,
	);
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

sub build_tree () {
	return Clay::UI::Box->new(
		id => 'OuterContainer',
		layout => {
			sizing    => { width => sizing_grow(), height => sizing_grow() },
			padding   => padding_all(16),
			child_gap => 16,
		},
		background_color => [250, 250, 255, 255],
		children => [
			Clay::UI::Box->new(
				id => 'SideBar',
				layout => {
					layout_direction => CLAY_TOP_TO_BOTTOM,
					sizing           => { width => sizing_fixed(300), height => sizing_grow() },
					padding          => padding_all(16),
					child_gap        => 16,
				},
				background_color => $COLOR_LIGHT,
				children => [
					Clay::UI::Box->new(
						id => 'ProfilePictureOuter',
						layout => {
							sizing          => { width => sizing_grow() },
							padding         => padding_all(16),
							child_gap       => 16,
							child_alignment => { x => CLAY_ALIGN_X_LEFT, y => CLAY_ALIGN_Y_CENTER },
						},
						background_color => $COLOR_RED,
						children => [
							Clay::UI::Box->new(
								id     => 'ProfilePicture',
								layout => { sizing => { width => sizing_fixed(60), height => sizing_fixed(60) } },
							),
							Clay::UI::Text->new(
								text       => 'Clay - UI Library',
								font_size  => 24,
								text_color => [255, 255, 255, 255],
							),
						],
					),
					map { sidebar_item($_) } 0 .. 4,
				],
			),
			Clay::UI::Box->new(
				id => 'MainContent',
				layout => { sizing => { width => sizing_grow(), height => sizing_grow() } },
				background_color => $COLOR_LIGHT,
			),
		],
	);
}

# Frame 1: geometry.
Clay_BeginLayout();
Clay::UI::layout( build_tree() );
my $frame1 = Clay_EndLayout(0);
printf "Frame 1: %d render commands\n", scalar @$frame1;

# Frame 2: hover the third sidebar item.
Clay_SetPointerState({ x => 160, y => 320 }, 0);
Clay_BeginLayout();
Clay::UI::layout( build_tree() );
my $frame2 = Clay_EndLayout(0);

my @over = @{ Clay_GetPointerOverIds() };
printf "Frame 2: %d elements under pointer\n", scalar @over;
for my $id (@over) {
	printf "  id=%u\n", $id->{id};
}

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
