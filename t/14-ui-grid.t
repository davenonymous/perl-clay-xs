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
use Clay::UI::Grid::Cell;
use Object::Pad;
use Object::Pad::MetaFunctions qw(ref_field);
use Scalar::Util qw(refaddr weaken);

sub text_cell ($text) { Clay::UI::Test::Text->new(text => $text) }

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
# Group ids are assigned when a row is added: the cell wrappers carry
# width_group / height_group.
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
	# The ten grids above used up every free id, so the freed one is the
	# only id in the pool and the next grid gets it. Compare the high bits
	# of the new grid's width_group to the freed one's.
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

# -----------------------------------------------------------------------------
# row_gap is mutable: it is re-read from contribute_grid_defaults each render,
# so a write shows up in the Grid's default outer-layout child_gap. The grid
# must NOT carry an explicit layout, or contribute_grid_defaults short-circuits
# and row_gap never applies.
# -----------------------------------------------------------------------------

subtest 'row_gap is mutable' => sub {
	my $grid = Clay::UI::Test::Grid->new( id => 'rg', row_gap => 2 );
	is( $grid->to_config->{layout}{child_gap}, 2, 'initial row_gap in default layout' );

	$grid->row_gap(9);
	is( $grid->row_gap, 9, 'row_gap accessor reflects write' );
	is( $grid->to_config->{layout}{child_gap}, 9, 'to_config default layout sees new row_gap' );
};

# -----------------------------------------------------------------------------
# cell_gap is mutable: it is baked into each row Box's layout child_gap at
# row-build time, so a write must rewrite every existing row in place.
# append_row and insert_row both build new row boxes; replace_row reuses the
# existing box (already in children) and so needs no special handling.
# -----------------------------------------------------------------------------

subtest 'cell_gap is mutable and rewrites existing rows' => sub {
	my $grid = Clay::UI::Test::Grid->new( id => 'cg', cell_gap => 3 );
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'a'), Clay::UI::Test::Text->new(text => 'b') ]);
	$grid->append_row([ Clay::UI::Test::Text->new(text => 'c'), Clay::UI::Test::Text->new(text => 'd') ]);
	$grid->insert_row(1, [ Clay::UI::Test::Text->new(text => 'e'), Clay::UI::Test::Text->new(text => 'f') ]);

	is( $_->layout->{child_gap}, 3, 'each row built with initial cell_gap' )
		for @{ $grid->children };

	$grid->cell_gap(12);
	is( $grid->cell_gap, 12, 'cell_gap accessor reflects write' );
	is( $_->layout->{child_gap}, 12, 'existing row rewritten to new cell_gap' )
		for @{ $grid->children };
};

# -----------------------------------------------------------------------------
# The Grid owns its rows: no generic child mutators, and the readers
# return copies.
# -----------------------------------------------------------------------------

subtest 'Grid and its rows have no generic child mutators' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'closed');
	$grid->append_row([ text_cell('a') ]);
	for my $method (qw(add_child clear_children remove_child remove_children_with)) {
		ok( !$grid->can($method), "Grid cannot $method" );
		ok( !$grid->children->[0]->can($method), "Grid::Row cannot $method" );
	}
};

subtest 'children and cell_wrappers return copies' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'copies');
	$grid->append_row([ text_cell('a'), text_cell('b') ]);
	push @{ $grid->children }, 'junk';
	push @{ $grid->cell_wrappers }, [ 'junk' ];
	push @{ $grid->cell_wrappers->[0] }, 'junk';
	is( scalar @{ $grid->children }, 1, 'rows unchanged' );
	is( $grid->row_count, 1, 'row_count unchanged' );
	is( scalar @{ $grid->cell_wrappers->[0] }, 2, 'row wrappers unchanged' );
};

# -----------------------------------------------------------------------------
# Failed mutations leave the grid unchanged.
# -----------------------------------------------------------------------------

subtest 'a row with the same cell twice changes nothing' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'dup');
	$grid->append_row([ text_cell('a'), text_cell('b') ]);
	my $cell = Clay::UI::Grid::Cell->new;
	like( dies { $grid->append_row([ $cell, $cell ]) }, qr/attached twice in one call/, 'append_row dies' );
	is( $grid->row_count, 1, 'row_count unchanged' );
	is( scalar @{ $grid->children }, 1, 'rows unchanged' );
	is( $cell->parent, undef, 'the cell was not attached' );
	ok( lives { $grid->set_cell(0, 0, text_cell('x')) }, 'the grid keeps working' );
};

subtest 'set_cell with a cell that is already in the grid changes nothing' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'moved');
	my $first = Clay::UI::Grid::Cell->new;
	$first->add_child(text_cell('a'));
	$grid->append_row([ $first, text_cell('b') ]);
	like( dies { $grid->set_cell(0, 1, $first) }, qr/no reparenting/, 'set_cell dies' );
	my $row = $grid->children->[0]->children;
	is( scalar @$row, 2, 'row still has two cells' );
	isnt( refaddr($row->[1]), refaddr($first), 'the second cell was not replaced' );
};

subtest 'a cell cannot move to a new grid after its grid is freed' => sub {
	my $cell = Clay::UI::Grid::Cell->new;
	$cell->add_child(text_cell('reused'));
	{
		my $old = Clay::UI::Test::Grid->new(id => 'old');
		$old->append_row([ $cell ]);
	}
	my $new = Clay::UI::Test::Grid->new(id => 'new');
	like( dies { $new->append_row([ $cell ]) }, qr/no reparenting/, 'reusing the cell dies' );
};

# -----------------------------------------------------------------------------
# A user layout is merged over the Grid's default layout.
# -----------------------------------------------------------------------------

subtest 'a layout with padding keeps rows stacked and row_gap' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'padded', row_gap => 4, layout => { padding => padding_all(8) });
	$grid->append_row([ text_cell('a1'), text_cell('a2') ]);
	$grid->append_row([ text_cell('b1'), text_cell('b2') ]);
	my @texts = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_TEXT } @{ make_ui($grid)->render };
	my %at = map { $_->{renderData}{stringContents} => $_->{boundingBox} } @texts;
	is( [ $at{a1}{x}, $at{a1}{y} ], [ 8, 8 ], 'padding applies' );
	is( [ $at{b1}{x}, $at{b1}{y} ], [ 8, 8 + $LINE_H + 4 ], 'rows are stacked with row_gap between them' );
};

# -----------------------------------------------------------------------------
# Grid ids: height ids are recycled, the grid id is released on free, and
# consumers may define DESTROY.
# -----------------------------------------------------------------------------

subtest 'removed rows free their height id' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'rolling');
	${ ref_field('Clay::UI::Grid.$_next_height_local', $grid) } = (1 << 20) - 1;
	$grid->append_row([ text_cell('last fresh id') ]);
	like( dies { $grid->append_row([ text_cell('one too many') ]) }, qr/local index 1048576 out of range/,
		'the local id space is exhausted' );
	is( $grid->row_count, 1, 'the failed append left no row behind' );
	$grid->remove_row(0);
	ok( lives { $grid->append_row([ text_cell('recycled') ]) }, 'append after remove reuses the released id' );
};

subtest 'the grid id is released when the grid is freed' => sub {
	my $grid = Clay::UI::Test::Grid->new(id => 'short-lived');
	$grid->append_row([ text_cell('x') ]);
	my $grid_id = $grid->cell_wrappers->[0][0]->width_group >> 20;

	# Hold every other id, so the only free id is the one the grid returns.
	my @held;
	while (1) {
		my $id = eval { Clay::UI::Grid::_claim_grid_id() };
		last unless defined $id;
		push @held, $id;
	}
	my $weak = $grid;
	weaken $weak;
	undef $grid;
	is( $weak, undef, 'the grid was freed' );
	my $reclaimed = Clay::UI::Grid::_claim_grid_id();
	is( $reclaimed, $grid_id, 'its grid id went back to the pool' );
	Clay::UI::Grid::_release_grid_id($_) for @held, $reclaimed;
};

class DestroyingGrid :does(Clay::UI::Grid) {
	field $log :param;
	method DESTROY { $log->('consumer DESTROY ran') }
}

subtest 'a Grid consumer can define DESTROY' => sub {
	my @log;
	{ DestroyingGrid->new(id => 'd', log => sub { push @log, @_ }) }
	is( \@log, ['consumer DESTROY ran'], 'the consumer DESTROY runs' );
};

done_testing;
