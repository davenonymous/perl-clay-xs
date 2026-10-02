use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::XS qw(:all);

# -----------------------------------------------------------------------------
# check_struct walks a value against a struct schema without a Clay
# context or frame. It accepts what parse mode accepts, and is strict about
# unknown keys, array lengths and references used as booleans.
# -----------------------------------------------------------------------------

sub check_error ($type, $value, $root = undef) {
	my $error = dies { check_struct($type, $value, $root) };
	return $error;
}

subtest 'valid values pass' => sub {
	my @valid = (
		[ Clay_Color             => [ 1, 2, 3, 4 ] ],
		[ Clay_Color             => { r => 1, a => 255 } ],
		[ Clay_Vector2           => [ 1.5, -2 ] ],
		[ Clay_Dimensions        => { width => 10, height => 20 } ],
		[ Clay_CornerRadius      => 4 ],
		[ Clay_Padding           => padding_all(65535) ],
		[ Clay_SizingAxis        => sizing_fit(0, 9**9**9) ],
		[ Clay_SizingAxis        => sizing_percent(0.5) ],
		[ Clay_FloatingElementConfig => { zIndex => -32768, parentId => Clay_GetElementId('p') } ],
		[ Clay_TextElementConfig => { fontSize => 16, wrapMode => CLAY_TEXT_WRAP_NONE } ],
		[ Clay_ElementDeclaration => {
			layout => { sizing => { width => sizing_grow() }, childGap => 4 },
			backgroundColor => [ 0, 0, 0, 255 ],
			clip => { vertical => 1, childOffset => [ 0, -10 ] },
			transition => { duration => 0.2, enter => { hasSetInitial => 1 } },
		} ],
		[ Clay_Padding => undef ],
	);
	for my $case (@valid) {
		ok( lives { check_struct(@$case) }, "$case->[0] accepts a valid value" ) or note $@;
	}
};

subtest 'range and type errors name the field' => sub {
	my @cases = (
		[ Clay_Padding => { left => -5 }, qr/^Clay_Padding\.left: expected an integer in 0\.\.65535, got '-5'/ ],
		[ Clay_LayoutConfig => { childGap => 70000 }, qr/^Clay_LayoutConfig\.childGap: expected an integer in 0\.\.65535/ ],
		[ Clay_LayoutConfig => { layoutDirection => 4 }, qr/layoutDirection: expected an integer in 0\.\.3/ ],
		[ Clay_FloatingElementConfig => { zIndex => 40000 }, qr/zIndex: expected an integer in -32768\.\.32767/ ],
		[ Clay_Color => { r => 'red' }, qr/^Clay_Color\.r: expected a finite number, got 'red'/ ],
		[ Clay_SizingAxis => { min => 0, max => -9**9**9 }, qr/max: expected a finite number or \+Inf/ ],
		[ Clay_LayoutConfig => { padding => { top => 1.5 } }, qr/^Clay_LayoutConfig\.padding\.top: expected an integer/ ],
	);
	for my $case (@cases) {
		my ($type, $value, $message) = @$case;
		like( check_error($type, $value), $message, "$type: $message" );
	}
};

subtest 'shape errors carry the schema hint' => sub {
	my $error = check_error('Clay_LayoutConfig', { padding => 8 }, 'layout');
	like( "$error", qr/^layout\.padding: expected a hash reference, got '8' \(padding_all\(N\) builds one\)/,
		'hint appended to the message' );
	is( $error->hint, 'padding_all(N) builds one', 'hint reader' );

	like( check_error('Clay_Sizing', { width => 100 }),
		qr/width: expected a hash reference, got '100' \(sizing_fit, sizing_grow, sizing_fixed or sizing_percent build one\)/,
		'sizing axis hint' );
	like( check_error('Clay_ElementDeclaration', { backgroundColor => 'red' }),
		qr/backgroundColor: expected a hash or array reference, got 'red' at /,
		'no hint where the schema has none' );
};

subtest 'unknown keys are rejected at every level' => sub {
	my $error = check_error('Clay_LayoutConfig', { childGapp => 1, zz => 2 });
	like( "$error", qr/^Clay_LayoutConfig: expected only the keys sizing, padding, childGap, childAlignment, layoutDirection, lineGap, lineSizing, got the unknown keys 'childGapp', 'zz'/,
		'unknown keys listed, sorted' );
	is( $error->unknown_keys, [ 'childGapp', 'zz' ], 'unknown_keys reader' );
	is( $error->known_keys, [qw(sizing padding childGap childAlignment layoutDirection lineGap lineSizing)], 'known_keys reader' );

	like( check_error('Clay_ElementDeclaration', { border => { width => { lft => 1 } } }),
		qr/^Clay_ElementDeclaration\.border\.width: expected only the keys left, right, top, bottom, betweenChildren, got the unknown key 'lft'/,
		'nested unknown key' );
	like( check_error('Clay_TransitionElementConfig', { exit => { hasSetInitial => 1 } }),
		qr/exit: expected only the keys trigger, siblingOrdering, hasSetFinal/,
		'anonymous transition structs know their keys' );
};

subtest 'sizing axis keys follow the axis type' => sub {
	like( check_error('Clay_SizingAxis', { type => CLAY__SIZING_TYPE_PERCENT, min => 1 }),
		qr/expected only the keys type, percent, got the unknown key 'min'/, 'percent axis has no min' );
	like( check_error('Clay_SizingAxis', { type => CLAY__SIZING_TYPE_FIXED, percent => 1 }),
		qr/expected only the keys min, max, type, got the unknown key 'percent'/, 'fixed axis has no percent' );
};

subtest 'arrays need one element per field' => sub {
	like( check_error('Clay_Color', [ 1, 2, 3 ]), qr/^Clay_Color: expected an array of 4 numbers, got an array of 3 elements/,
		'short colour' );
	like( check_error('Clay_Vector2', [ 1, 2, 3 ]), qr/expected an array of 2 numbers, got an array of 3 elements/,
		'long vector' );
};

subtest 'booleans must be plain values' => sub {
	like( check_error('Clay_ClipElementConfig', { vertical => {} }),
		qr/^Clay_ClipElementConfig\.vertical: expected a plain boolean value, got a HASH reference/, 'reference rejected' );
	ok( lives { check_struct('Clay_ClipElementConfig', { vertical => 'yes', horizontal => 0 }) }, 'plain values accepted' );
};

subtest 'parse mode stays lenient' => sub {
	my $ctx = Clay_Initialize(Clay_MinMemorySize(), { width => 100, height => 100 });
	Clay_BeginLayout();
	Clay__OpenElement();
	ok( lives { Clay__ConfigureOpenElement({ layout => { childGapp => 1 }, backgroundColor => [ 1, 2, 3 ] }) },
		'unknown keys and short arrays are ignored by Clay__ConfigureOpenElement' );
	Clay__CloseElement();
	Clay_EndLayout(0);
};

subtest 'the error object' => sub {
	my $error = check_error('Clay_Padding', { left => -5 }, 'padding');
	isa_ok( $error, 'Clay::XS::StructError' );
	is( $error->path, [ 'padding', 'left' ], 'path starts at the root' );
	is( $error->expected, 'an integer in 0..65535', 'expected' );
	is( $error->got, "'-5'", 'got' );
	ok( $error ? 1 : 0, 'true in boolean context' );
	is( $error->message, "padding.left: expected an integer in 0..65535, got '-5'", 'message without location' );
	my $line  = __LINE__; my $located = dies { check_struct('Clay_Padding', 8) };
	is( [ $located->file, $located->line ], [ __FILE__, $line ], 'file and line of the caller' );
	like( "$located", qr/ at \Q${\__FILE__}\E line $line\.\n\z/, 'stringifies with the location' );
	is( check_error('Clay_Padding', { left => -5 })->path, [ 'Clay_Padding', 'left' ], 'default root is the type name' );
};

subtest 'unknown type names' => sub {
	my $error = check_error('Clay_Nope', {});
	ok( !ref $error, 'plain string' );
	like( $error, qr/^check_struct: unknown struct type 'Clay_Nope'/, 'message' );
};

done_testing;
