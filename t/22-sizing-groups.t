use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::XS qw(:all);

# -----------------------------------------------------------------------------
# Sizing groups (patches/0001-clay-sizing-groups.patch): members sharing a
# group id on an axis are equalized once per frame, nested groups converge,
# GROW containers and minimum sizes are propagated, and every member stays
# within its own max.
# -----------------------------------------------------------------------------

my @errors;
my $ctx = Clay_Initialize(Clay_MinMemorySize(), { width => 1000, height => 1000 },
	sub ($error, $userdata) { push @errors, $error });
Clay_SetMeasureTextFunction(sub { return { width => 0, height => 0 } });

sub el ($name, $decl, @children) {
	Clay__OpenElementWithId(Clay_GetElementId($name));
	Clay__ConfigureOpenElement($decl);
	$_->() for @children;
	Clay__CloseElement();
}

sub fixed ($name, $width, $height = 10) {
	return sub { el($name, { layout => { sizing => { width => sizing_fixed($width), height => sizing_fixed($height) } } }) };
}

sub box_of ($name) {
	return Clay_GetElementData(Clay_GetElementId($name))->{boundingBox};
}

sub frame (@content) {
	Clay_BeginLayout();
	$_->() for @content;
	return Clay_EndLayout(0.016);
}

subtest 'an unrelated transition does not change the result' => sub {
	my $layout = sub ($with_transition) {
		return sub {
			el('col', { layout => { layoutDirection => CLAY_TOP_TO_BOTTOM, sizing => { width => sizing_fixed(400) } } },
				sub { el('row0', { layout => { sizing => { width => sizing_grow() } } },
					sub { el('A', { layout => { sizing => { width => sizing_grow(), height => sizing_fixed(10) } },
					                sizingGroup => { width => 7 } }) }) },
				sub { el('row1', { layout => { sizing => { width => sizing_grow() } } },
					sub { el('B', { layout => { sizing => { width => sizing_grow(), height => sizing_fixed(10) } },
					                sizingGroup => { width => 7 } }) },
					fixed('S', 300)) },
				($with_transition
					? sub { el('T', { layout => { sizing => { width => sizing_fixed(10), height => sizing_fixed(10) } },
					                  transition => { duration => 1, properties => CLAY_TRANSITION_PROPERTY_X } }) }
					: ()),
			);
		};
	};
	for my $with_transition (0, 1) {
		frame($layout->($with_transition)) for 1 .. 2;
		my $label = $with_transition ? 'with a transition' : 'without a transition';
		is( box_of('B')->{width}, 100, "B keeps the space next to S ($label)" );
		is( box_of('S')->{x},     100, "S stays inside the column ($label)" );
	}
};

subtest 'nested groups converge' => sub {
	my $cell = sub ($name, $group, @children) {
		return sub { el($name, { sizingGroup => { width => $group } }, @children) };
	};
	my $row = sub ($name, @cells) {
		return sub { el($name, { layout => { layoutDirection => CLAY_LEFT_TO_RIGHT } }, @cells) };
	};
	frame(sub {
		el('outer', { layout => { layoutDirection => CLAY_TOP_TO_BOTTOM } },
			$row->('orow0', $cell->('O00', 1, sub {
				el('inner', { layout => { layoutDirection => CLAY_TOP_TO_BOTTOM } },
					$row->('irow0', $cell->('I00', 101, fixed('f00', 10)), $cell->('I01', 102, fixed('f01', 50))),
					$row->('irow1', $cell->('I10', 101, fixed('f10', 50)), $cell->('I11', 102, fixed('f11', 10))));
			})),
			$row->('orow1', $cell->('O10', 1, fixed('f2', 70))));
	});
	is( box_of('O00')->{width}, 100, 'outer cell with the inner grid' );
	is( box_of('O10')->{width}, 100, 'its column partner' );
	is( box_of('I01')->{x} + box_of('I01')->{width}, 100, 'inner content ends inside its cell' );
};

subtest 'GROW rows are widened like FIT rows' => sub {
	my $cell = sub ($name, $group, $width) {
		return sub { el($name, { sizingGroup => { width => $group } }, fixed("$name-f", $width)) };
	};
	frame(sub {
		el('table', { layout => { layoutDirection => CLAY_TOP_TO_BOTTOM } },
			sub { el('row0', { layout => { sizing => { width => sizing_grow() } } }, $cell->('A', 1, 50),  $cell->('B', 2, 100)) },
			sub { el('row1', { layout => { sizing => { width => sizing_grow() } } }, $cell->('C', 1, 100), $cell->('D', 2, 50)) });
	});
	is( box_of('table')->{width}, 200, 'the table fits both columns' );
	is( box_of('B')->{x} + box_of('B')->{width}, box_of('row0')->{width}, 'no cell overflows its row' );
};

subtest 'a member keeps its own max' => sub {
	frame(sub {
		el('col', { layout => { layoutDirection => CLAY_TOP_TO_BOTTOM } },
			sub { el('capped', { layout => { sizing => { width => sizing_fit(0, 50) } }, sizingGroup => { width => 3 } }, fixed('a', 30)) },
			sub { el('wide',   { layout => { sizing => { width => sizing_fit() } },       sizingGroup => { width => 3 } }, fixed('b', 100)) });
	});
	is( box_of('capped')->{width}, 50,  'the capped member stops at its max' );
	is( box_of('wide')->{width},   100, 'the other member takes the group size' );
};

subtest 'height groups survive the second layout pass' => sub {
	frame(
		sub {
			el('stack', { layout => { layoutDirection => CLAY_TOP_TO_BOTTOM } },
				sub { el('short', { layout => { layoutDirection => CLAY_TOP_TO_BOTTOM }, sizingGroup => { height => 5 } }, fixed('s', 10, 20)) },
				sub { el('tall',  { layout => { layoutDirection => CLAY_TOP_TO_BOTTOM }, sizingGroup => { height => 5 } }, fixed('t', 10, 50)) });
		},
		sub { el('T', { layout => { sizing => { width => sizing_fixed(10), height => sizing_fixed(10) } },
		                transition => { duration => 1, properties => CLAY_TRANSITION_PROPERTY_X } }) },
	);
	is( box_of('short')->{height}, 50, 'the short member is raised to the group height' );
	is( box_of('tall')->{y}, 50, 'its sibling is placed after it' );
};

subtest 'cyclic nesting terminates and reports an error' => sub {
	@errors = ();
	my $padded = sub ($name, $group, @children) {
		return sub { el($name, { layout => { padding => { left => 5 } }, sizingGroup => { width => $group } }, @children) };
	};
	frame(sub {
		el('root', { layout => { layoutDirection => CLAY_TOP_TO_BOTTOM } },
			$padded->('X1', 1, $padded->('Y1', 2, fixed('y1', 10))),
			$padded->('Y2', 2, $padded->('X2', 1, fixed('x2', 10))));
	});
	is( scalar(@errors), 1, 'one error reported' );
	is( $errors[0]{errorType}, CLAY_ERROR_TYPE_SIZING_GROUP_CYCLE, 'as a sizing-group cycle' );
	like( $errors[0]{errorText}, qr/did not converge/, 'with a descriptive text' );
};

done_testing;
