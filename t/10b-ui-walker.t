use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Object::Pad;
use Clay::Layout qw(:all);
use Clay::UI;
use Clay::UI::Role::Element;

# -----------------------------------------------------------------------------
# Minimal widget class consuming the Element role. Exercises the Phase 1
# walker without needing the Phase 2 mixin machinery.
# -----------------------------------------------------------------------------

class TestWidget :does(Clay::UI::Role::Element) {
	field $bg :param :reader = [40, 50, 60, 200];

	method contribute_test ($cfg) {
		$cfg->{background_color} = $bg;
		$cfg->{layout} = {
			sizing => {
				width  => Clay::Layout::sizing_fixed(100),
				height => Clay::Layout::sizing_fixed(50),
			},
		};
		return;
	}
}

my @errors;
my $ctx = Clay_Initialize(
	Clay_MinMemorySize(),
	{ width => 400, height => 300 },
	sub ($err, $userdata) { push @errors, $err },
);
Clay_SetMeasureTextFunction(sub { return { width => 0, height => 0 } });

# -----------------------------------------------------------------------------
# Walker emits a single rectangle for a single widget.
# -----------------------------------------------------------------------------

subtest 'single node' => sub {
	Clay_BeginLayout();
	Clay::UI::layout( TestWidget->new(id => 'solo') );
	my $cmds = Clay_EndLayout(0);

	is( scalar(@errors), 0, 'no Clay errors' );

	my ($rect) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_RECTANGLE } @$cmds;
	ok( defined $rect, 'rectangle command emitted' );
	is( $rect->{renderData}{backgroundColor}{r}, 40, 'snake_case background_color was camelized and marshalled' );
};

# -----------------------------------------------------------------------------
# Walker recurses into children and applies parent before child.
# -----------------------------------------------------------------------------

subtest 'parent with children' => sub {
	Clay_BeginLayout();
	Clay::UI::layout(
		TestWidget->new(
			id       => 'parent',
			bg       => [10, 20, 30, 255],
			children => [
				TestWidget->new( bg => [200, 100, 50, 255] ),
				TestWidget->new( bg => [50, 100, 200, 255] ),
			],
		),
	);
	my $cmds = Clay_EndLayout(0);

	my @rects = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_RECTANGLE } @$cmds;
	is( scalar(@rects), 3, 'three rectangles (parent + two children)' );
	is( $rects[0]{renderData}{backgroundColor}{r}, 10,  'parent first' );
	is( $rects[1]{renderData}{backgroundColor}{r}, 200, 'first child second' );
	is( $rects[2]{renderData}{backgroundColor}{r}, 50,  'second child third' );
};

# -----------------------------------------------------------------------------
# Non-Element values in a tree fail loud.
# -----------------------------------------------------------------------------

subtest 'fail loud on bad node' => sub {
	Clay_BeginLayout();
	like(
		dies { Clay::UI::layout( { not => 'a widget' } ) },
		qr/not a blessed widget/,
		'plain hashref rejected',
	);
	# Clean up the half-open layout state from the failed call.
	Clay_EndLayout(0);
};

done_testing;
