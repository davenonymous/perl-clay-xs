use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Object::Pad;
use Clay::UI::Role::Element;
use Clay::UI::Role::HasLayout;
use Clay::UI::Role::HasBackground;
use Clay::UI::Role::HasBorder;
use Clay::UI::Role::HasCornerRadius;
use Clay::UI::Role::HasClip;
use Clay::UI::Role::HasFloating;

# -----------------------------------------------------------------------------
# A widget composing every mixin. The Element role's to_config walks
# all composed roles and calls each contribute_* method, so the user
# does not have to wire them up by hand.
# -----------------------------------------------------------------------------

class TestKitchenSink :does(Clay::UI::Role::Element)
                      :does(Clay::UI::Role::HasLayout)
                      :does(Clay::UI::Role::HasBackground)
                      :does(Clay::UI::Role::HasBorder)
                      :does(Clay::UI::Role::HasCornerRadius)
                      :does(Clay::UI::Role::HasClip)
                      :does(Clay::UI::Role::HasFloating)
{}

# -----------------------------------------------------------------------------
# Each mixin in isolation: only its slice appears.
# -----------------------------------------------------------------------------

subtest 'HasLayout alone' => sub {
	class TL :does(Clay::UI::Role::Element) :does(Clay::UI::Role::HasLayout) {}
	my $cfg = TL->new( layout => { padding => { left => 8, right => 8, top => 0, bottom => 0 } } )->to_config;
	is( $cfg, { layout => { padding => { left => 8, right => 8, top => 0, bottom => 0 } } }, 'layout slice only' );
};

subtest 'HasBackground alone' => sub {
	class TB :does(Clay::UI::Role::Element) :does(Clay::UI::Role::HasBackground) {}
	my $cfg = TB->new( background_color => [10, 20, 30, 255] )->to_config;
	is( $cfg, { background_color => [10, 20, 30, 255] }, 'background slice only' );
};

subtest 'HasBorder scalar shorthand expands' => sub {
	class TBd :does(Clay::UI::Role::Element) :does(Clay::UI::Role::HasBorder) {}
	my $cfg = TBd->new( border_color => [100, 100, 100, 255], border_width => 2 )->to_config;
	is(
		$cfg,
		{
			border => {
				color => [100, 100, 100, 255],
				width => { left => 2, right => 2, top => 2, bottom => 2, between_children => 0 },
			},
		},
		'scalar width expanded to four sides',
	);
};

subtest 'HasBorder hashref width passes through' => sub {
	class TBd2 :does(Clay::UI::Role::Element) :does(Clay::UI::Role::HasBorder) {}
	my $cfg = TBd2->new(
		border_color => [50, 50, 50, 255],
		border_width => { left => 1, right => 0, top => 1, bottom => 0, between_children => 0 },
	)->to_config;
	is( $cfg->{border}{width}{left}, 1, 'hashref width unchanged' );
	is( $cfg->{border}{width}{right}, 0, 'hashref width unchanged' );
};

subtest 'HasCornerRadius scalar shorthand expands' => sub {
	class TC :does(Clay::UI::Role::Element) :does(Clay::UI::Role::HasCornerRadius) {}
	my $cfg = TC->new( corner_radius => 6 )->to_config;
	is(
		$cfg,
		{ corner_radius => { top_left => 6, top_right => 6, bottom_left => 6, bottom_right => 6 } },
		'scalar radius expanded to four corners',
	);
};

subtest 'HasClip alone' => sub {
	class TCl :does(Clay::UI::Role::Element) :does(Clay::UI::Role::HasClip) {}
	my $cfg = TCl->new(
		clip => { horizontal => 1, vertical => 1, child_offset => { x => 0, y => 0 } },
	)->to_config;
	is( $cfg->{clip}{horizontal}, 1, 'clip slice only' );
};

subtest 'HasFloating alone' => sub {
	class TF :does(Clay::UI::Role::Element) :does(Clay::UI::Role::HasFloating) {}
	my $cfg = TF->new( floating => { attach_to => 1 } )->to_config;
	is( $cfg, { floating => { attach_to => 1 } }, 'floating slice only' );
};

# -----------------------------------------------------------------------------
# Composition: every mixin together produces the union of slices.
# -----------------------------------------------------------------------------

subtest 'kitchen sink composes all slices' => sub {
	my $cfg = TestKitchenSink->new(
		layout           => { padding => { left => 1, right => 1, top => 1, bottom => 1 } },
		background_color => [10, 20, 30, 255],
		border_color     => [50, 50, 50, 255],
		border_width     => 1,
		corner_radius    => 4,
		clip             => { horizontal => 1, vertical => 0, child_offset => { x => 0, y => 0 } },
		floating         => { attach_to => 0 },
	)->to_config;

	ok( exists $cfg->{layout},           'layout slice present' );
	ok( exists $cfg->{background_color}, 'background slice present' );
	ok( exists $cfg->{border},           'border slice present' );
	ok( exists $cfg->{corner_radius},    'corner_radius slice present' );
	ok( exists $cfg->{clip},             'clip slice present' );
	ok( exists $cfg->{floating},         'floating slice present' );
};

# -----------------------------------------------------------------------------
# Undefined fields contribute nothing.
# -----------------------------------------------------------------------------

subtest 'unset mixins are silent' => sub {
	my $cfg = TestKitchenSink->new->to_config;
	is( $cfg, {}, 'no slices when no fields supplied' );
};

done_testing;
