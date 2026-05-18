use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use lib "t/lib";

use Clay::XS qw(:all);
use Clay::UI;
use Clay::UI::Test::Box;
use Clay::UI::Test::Text;
use Clay::UI::Test::Grid;

# Deterministic glyph width so the test can predict exact column widths from
# the test strings without depending on a real font.
my $GLYPH_W = 8;
my $LINE_H  = 16;

my @errors;
my $error_handler = sub ($err, $userdata) { push @errors, $err };
my $measure_text  = sub ($text, $config, $userdata) {
	return { width => length($text) * $GLYPH_W, height => $LINE_H };
};

sub make_ui ($root) {
	return Clay::UI->new(
		width         => 800,
		height        => 600,
		root          => $root,
		error_handler => $error_handler,
		measure_text  => $measure_text,
	);
}

# -----------------------------------------------------------------------------
# Each column shrink-wraps to its widest cell across all rows. The widest
# string per column determines that column's final width; expected positions
# can be derived from prefix sums of those widths plus cell_gap.
# -----------------------------------------------------------------------------

subtest 'columns auto-fit widest cell across rows' => sub {
	@errors = ();
	my $grid = Clay::UI::Test::Grid->new(
		id       => 'grid',
		cell_gap => 0,
		row_gap  => 0,
	);
	$grid->append_row([
		Clay::UI::Test::Text->new(text => 'A'),         # 1ch
		Clay::UI::Test::Text->new(text => 'longest'),   # 7ch <- col 1 max
		Clay::UI::Test::Text->new(text => 'XY'),        # 2ch
	]);
	$grid->append_row([
		Clay::UI::Test::Text->new(text => 'BBBB'),      # 4ch <- col 0 max
		Clay::UI::Test::Text->new(text => 'mid'),       # 3ch
		Clay::UI::Test::Text->new(text => 'longestZZ'), # 9ch <- col 2 max
	]);
	$grid->append_row([
		Clay::UI::Test::Text->new(text => 'C'),         # 1ch
		Clay::UI::Test::Text->new(text => 'm'),         # 1ch
		Clay::UI::Test::Text->new(text => 'tiny'),      # 4ch
	]);
	my $ui = make_ui($grid);
	my $cmds = $ui->render;
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
	my $grid = Clay::UI::Test::Grid->new(id => 'tagging');
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'a'), Clay::UI::Test::Text->new(text => 'b') ]);
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'c'), Clay::UI::Test::Text->new(text => 'd') ]);
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
	my $inner = Clay::UI::Test::Grid->new(id => 'inner');
	$inner->append_row([ Clay::UI::Test::Text->new(text => 'i'), Clay::UI::Test::Text->new(text => 'ii') ]);
	my $outer = Clay::UI::Test::Grid->new(id => 'outer');
	$outer->append_row([ $inner, Clay::UI::Test::Text->new(text => 'right') ]);

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

# -----------------------------------------------------------------------------
# Mutation: set_cell, append_row, insert_row, remove_row, replace_row all
# preserve per-column width_group / per-row height_group sharing.
# -----------------------------------------------------------------------------

subtest 'set_cell preserves column/row sizing groups' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'mut-set');
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'a'), Clay::UI::Test::Text->new(text => 'b') ]);
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'c'), Clay::UI::Test::Text->new(text => 'd') ]);
	my $w = $grid->cell_wrappers;
	my $col0_w = $w->[0][0]->width_group;
	my $row0_h = $w->[0][0]->height_group;

	$grid->set_cell(0, 0, Clay::UI::Test::Text->new(text => 'A'));
	is( $grid->cell_wrappers->[0][0]->width_group,  $col0_w, 'replaced cell keeps column width_group' );
	is( $grid->cell_wrappers->[0][0]->height_group, $row0_h, 'replaced cell keeps row height_group' );
	is(
		$grid->cell_wrappers->[0][0]->width_group,
		$grid->cell_wrappers->[1][0]->width_group,
		'col 0 still equalized after set_cell',
	);
};

subtest 'append_row extends with fresh height_group and reuses column ids' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'mut-append');
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'a'), Clay::UI::Test::Text->new(text => 'b') ]);
	my $col0_w = $grid->cell_wrappers->[0][0]->width_group;
	my $row0_h = $grid->cell_wrappers->[0][0]->height_group;

	$grid->append_row([
		Clay::UI::Test::Text->new(text => 'x'),
		Clay::UI::Test::Text->new(text => 'y'),
	]);
	is( scalar @{ $grid->cell_wrappers }, 2, 'two rows after append' );
	is( $grid->cell_wrappers->[1][0]->width_group, $col0_w, 'new row column 0 reuses width id' );
	isnt( $grid->cell_wrappers->[1][0]->height_group, $row0_h, 'new row has fresh height id' );
	is(
		$grid->cell_wrappers->[1][0]->height_group,
		$grid->cell_wrappers->[1][1]->height_group,
		'new row cells share the same height id',
	);
};

subtest 'append_row widens column-id cache when new row is longer' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'mut-wide');
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'a') ]);
	$grid->append_row([
		Clay::UI::Test::Text->new(text => 'p'),
		Clay::UI::Test::Text->new(text => 'q'),
		Clay::UI::Test::Text->new(text => 'r'),
	]);
	my $w = $grid->cell_wrappers->[1];
	isnt( $w->[0]->width_group, $w->[1]->width_group, 'distinct columns get distinct width ids' );
	isnt( $w->[1]->width_group, $w->[2]->width_group, 'distinct columns get distinct width ids' );
};

subtest 'remove_row drops row and keeps remaining ids intact' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'mut-remove');
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'a') ]);
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'b') ]);
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'c') ]);
	my $row0_h = $grid->cell_wrappers->[0][0]->height_group;
	my $row2_h = $grid->cell_wrappers->[2][0]->height_group;

	$grid->remove_row(1);
	is( scalar @{ $grid->cell_wrappers }, 2, 'two rows after remove' );
	is( $grid->cell_wrappers->[0][0]->height_group, $row0_h, 'row 0 height id unchanged' );
	is( $grid->cell_wrappers->[1][0]->height_group, $row2_h, 'former row 2 height id unchanged' );
};

subtest 'replace_row reuses existing height_group' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'mut-replace');
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'a'), Clay::UI::Test::Text->new(text => 'b') ]);
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'c'), Clay::UI::Test::Text->new(text => 'd') ]);
	my $row1_h = $grid->cell_wrappers->[1][0]->height_group;
	$grid->replace_row(1, [
		Clay::UI::Test::Text->new(text => 'X'),
		Clay::UI::Test::Text->new(text => 'Y'),
	]);
	is( $grid->cell_wrappers->[1][0]->height_group, $row1_h, 'row 1 height id preserved on replace' );
	is(
		$grid->cell_wrappers->[1][0]->width_group,
		$grid->cell_wrappers->[0][0]->width_group,
		'column 0 still equalized',
	);
};

subtest 'mutated grid renders correctly' => sub {
	@errors = ();
	my $grid = Clay::UI::Test::Grid->new(
		id       => 'mut-render',
		cell_gap => 0,
		row_gap  => 0,
	);
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'A'),    Clay::UI::Test::Text->new(text => 'BB') ]);
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'CCC'),  Clay::UI::Test::Text->new(text => 'D') ]);
	$grid->append_row([
		Clay::UI::Test::Text->new(text => 'EEEEE'),    # 5ch, widens col 0
		Clay::UI::Test::Text->new(text => 'FF'),
	]);
	my $ui   = make_ui($grid);
	my $cmds = $ui->render;
	is( scalar(@errors), 0, 'no Clay errors after mutation' );

	my @texts = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_TEXT } @$cmds;
	is( scalar(@texts), 6, 'six text commands after append (3 rows x 2 cols)' );

	# Column 0 should be 5 chars wide (widest is 'EEEEE'). Column 1 starts at x = 5 * GLYPH_W.
	my $expected_col1_x = 5 * $GLYPH_W;
	for my $r (0 .. 2) {
		is( $texts[$r * 2 + 1]{boundingBox}{x}, $expected_col1_x,
			"row $r col 1 starts at widened col 0 boundary" );
	}
};

# -----------------------------------------------------------------------------
# Grid-id pool: destruction recycles ids; exhaustion dies with a clear message.
# -----------------------------------------------------------------------------

subtest 'grid-id is recycled on destruction' => sub {
	# Hold references so the grids do not get GC'd prematurely.
	my @grids;
	for my $i (1 .. 10) {
		my $g = Clay::UI::Test::Grid->new(id => "g$i");
		$g->append_row([ Clay::UI::Test::Text->new(text => 'x') ]);
		push @grids, $g;
	}
	# Destroying a grid should free its grid-id back to the pool.
	my $before = $grids[5]->cell_wrappers->[0][0]->width_group;
	$grids[5] = undef;   # release one slot
	my $fresh = Clay::UI::Test::Grid->new(id => 'replacement');
	$fresh->append_row([ Clay::UI::Test::Text->new(text => 'y') ]);
	ok( defined $fresh, 'allocated a grid after releasing one' );
	# The freed grid-id is the most recently freed, so the free-list pops it
	# for the next claim. Confirm by comparing the high bits of the new
	# grid's width_group to the freed one's.
	my $high_bits = sub { $_[0] >> 20 };
	is(
		$high_bits->($fresh->cell_wrappers->[0][0]->width_group),
		$high_bits->($before),
		'recycled grid-id was reused for the next grid',
	);
};

subtest 'grid-id pool exhaustion dies loudly' => sub {
	# Drain the pool synthetically by calling the internal claim until it
	# fails. This is intrusive but the cleanest way to exercise the die.
	my @held_ids;
	my $err;
	{
		local $@;
		eval {
			while (1) {
				push @held_ids, Clay::UI::Grid::_claim_grid_id();
			}
			1;
		};
		$err = $@;
	}
	like( $err, qr/grid-id pool exhausted/, 'die message mentions exhaustion' );
	# Restore the pool so later tests (and other test files) are unaffected.
	Clay::UI::Grid::_release_grid_id($_) for @held_ids;
};

done_testing;
