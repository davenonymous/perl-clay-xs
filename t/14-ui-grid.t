use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::Layout qw(:all);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;
use Clay::UI::Grid;

# Deterministic glyph width so the test can predict exact column widths from
# the test strings without depending on a real font.
my $GLYPH_W = 8;
my $LINE_H  = 16;

my @errors;
my $ctx = Clay_Initialize(
	Clay_MinMemorySize(),
	{ width => 800, height => 600 },
	sub ($err, $userdata) { push @errors, $err },
);
Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
	return { width => length($text) * $GLYPH_W, height => $LINE_H };
});

# -----------------------------------------------------------------------------
# Each column shrink-wraps to its widest cell across all rows. The widest
# string per column determines that column's final width; expected positions
# can be derived from prefix sums of those widths plus cell_gap.
# -----------------------------------------------------------------------------

subtest 'columns auto-fit widest cell across rows' => sub {
	@errors = ();
	Clay_BeginLayout();
	Clay::UI::layout(
		Clay::UI::Grid->new(
			id   => 'grid',
			rows => [
				[ Clay::UI::Text->new(text => 'A'),         # 1ch
				  Clay::UI::Text->new(text => 'longest'),   # 7ch <- col 1 max
				  Clay::UI::Text->new(text => 'XY') ],      # 2ch
				[ Clay::UI::Text->new(text => 'BBBB'),      # 4ch <- col 0 max
				  Clay::UI::Text->new(text => 'mid'),       # 3ch
				  Clay::UI::Text->new(text => 'longestZZ')],# 9ch <- col 2 max
				[ Clay::UI::Text->new(text => 'C'),         # 1ch
				  Clay::UI::Text->new(text => 'm'),         # 1ch
				  Clay::UI::Text->new(text => 'tiny') ],    # 4ch
			],
			cell_gap => 0,
			row_gap  => 0,
		),
	);
	my $cmds = Clay_EndLayout(0);
	is( scalar(@errors), 0, 'no Clay errors' );

	my $expected_col_w = [ 4 * $GLYPH_W, 7 * $GLYPH_W, 9 * $GLYPH_W ];
	my $expected_col_x = [ 0, $expected_col_w->[0], $expected_col_w->[0] + $expected_col_w->[1] ];

	my @texts = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_TEXT } @$cmds;
	is( scalar(@texts), 9, 'nine text commands emitted (3x3 grid)' );

	# Texts are emitted in row-major order. Verify each cell's bounding box
	# starts at the correct column x.
	for my $r (0 .. 2) {
		for my $c (0 .. 2) {
			my $cmd = $texts[$r * 3 + $c];
			is(
				$cmd->{boundingBox}{x}, $expected_col_x->[$c],
				sprintf("cell (%d,%d) x matches column start", $r, $c),
			);
		}
	}
};

# -----------------------------------------------------------------------------
# Group ids are assigned by Grid's ADJUST block; cells emerge from
# construction with width_group / height_group set.
# -----------------------------------------------------------------------------

subtest 'Grid assigns sizing_group ids to per-cell wrappers' => sub {
	my $grid = Clay::UI::Grid->new(
		id   => 'tagging',
		rows => [
			[ Clay::UI::Text->new(text => 'a'), Clay::UI::Text->new(text => 'b') ],
			[ Clay::UI::Text->new(text => 'c'), Clay::UI::Text->new(text => 'd') ],
		],
	);
	my $w = $grid->cell_wrappers;
	is( scalar @$w, 2, 'two row wrappers' );
	is( scalar @{ $w->[0] }, 2, 'first row has two cell wrappers' );

	# Cells in the same column share width_group; cells in the same row share height_group.
	is( $w->[0][0]->width_group, $w->[1][0]->width_group, 'col 0 wrappers share width_group' );
	is( $w->[0][1]->width_group, $w->[1][1]->width_group, 'col 1 wrappers share width_group' );
	isnt( $w->[0][0]->width_group, $w->[0][1]->width_group, 'different columns get different width_groups' );

	is( $w->[0][0]->height_group, $w->[0][1]->height_group, 'row 0 wrappers share height_group' );
	is( $w->[1][0]->height_group, $w->[1][1]->height_group, 'row 1 wrappers share height_group' );
	isnt( $w->[0][0]->height_group, $w->[1][0]->height_group, 'different rows get different height_groups' );
};

# -----------------------------------------------------------------------------
# Nested grids: inner grid's group ids must not collide with outer grid's.
# -----------------------------------------------------------------------------

subtest 'nested grids use disjoint group-id ranges' => sub {
	my $inner = Clay::UI::Grid->new(
		id   => 'inner',
		rows => [
			[ Clay::UI::Text->new(text => 'i'),  Clay::UI::Text->new(text => 'ii') ],
		],
	);
	my $outer = Clay::UI::Grid->new(
		id   => 'outer',
		rows => [
			[ $inner, Clay::UI::Text->new(text => 'right') ],
		],
	);

	my $inner_w = $inner->cell_wrappers->[0];
	my $outer_w = $outer->cell_wrappers->[0];

	# Every inner-grid group id must differ from every outer-grid group id.
	for my $iw (@$inner_w) {
		for my $ow (@$outer_w) {
			isnt( $iw->width_group,  $ow->width_group,  'inner vs outer width_group disjoint' );
			isnt( $iw->height_group, $ow->height_group, 'inner vs outer height_group disjoint' );
		}
	}
};

done_testing;
