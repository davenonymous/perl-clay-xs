use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Object::Pad;
use Clay::XS qw(:all);
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
				width  => Clay::XS::sizing_fixed(100),
				height => Clay::XS::sizing_fixed(50),
			},
		};
		return;
	}
}

my @errors;
my $error_handler = sub ($err, $userdata) { push @errors, $err };
my $measure_text  = sub { return { width => 0, height => 0 } };

sub make_ui ($root) {
	return Clay::UI->new(
		width         => 400,
		height        => 300,
		root          => $root,
		error_handler => $error_handler,
		measure_text  => $measure_text,
	);
}

# -----------------------------------------------------------------------------
# Walker emits a single rectangle for a single widget.
# -----------------------------------------------------------------------------

subtest 'single node' => sub {
	my $ui = make_ui( TestWidget->new(id => 'solo') );
	my $cmds = $ui->render;

	is( scalar(@errors), 0, 'no Clay errors' );

	my ($rect) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_RECTANGLE } @$cmds;
	ok( defined $rect, 'rectangle command emitted' );
	is( $rect->{renderData}{backgroundColor}{r}, 40, 'snake_case background_color was camelized and marshalled' );
};

# -----------------------------------------------------------------------------
# Walker recurses into children and applies parent before child.
# -----------------------------------------------------------------------------

subtest 'parent with children' => sub {
	my $ui = make_ui(
		TestWidget->new(
			id       => 'parent',
			bg       => [10, 20, 30, 255],
			children => [
				TestWidget->new( bg => [200, 100, 50, 255] ),
				TestWidget->new( bg => [50, 100, 200, 255] ),
			],
		),
	);
	my $cmds = $ui->render;

	my @rects = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_RECTANGLE } @$cmds;
	is( scalar(@rects), 3, 'three rectangles (parent + two children)' );
	is( $rects[0]{renderData}{backgroundColor}{r}, 10,  'parent first' );
	is( $rects[1]{renderData}{backgroundColor}{r}, 200, 'first child second' );
	is( $rects[2]{renderData}{backgroundColor}{r}, 50,  'second child third' );
};

# -----------------------------------------------------------------------------
# Non-Element values in a tree fail loud at construction.
# -----------------------------------------------------------------------------

subtest 'fail loud on bad root' => sub {
	like(
		dies {
			Clay::UI->new(
				width  => 400,
				height => 300,
				root   => { not => 'a widget' },
			)
		},
		qr/must be a widget/,
		'plain hashref rejected at construction',
	);
};

# -----------------------------------------------------------------------------
# Non-blessed values inside the tree fail loud at render time without
# leaving Clay's open-element stack unbalanced (no segfault on EndLayout).
# -----------------------------------------------------------------------------

subtest 'fail loud on bad child without segfault' => sub {
	# Construction now validates children (via ADJUST + add_child) so we
	# inject directly into the live children arrayref to reproduce a
	# rotten tree that only the walker can catch.
	my $parent = TestWidget->new(id => 'parent');
	push @{ $parent->children }, { not => 'a widget' };
	my $ui = make_ui($parent);
	like(
		dies { $ui->render },
		qr/not a blessed widget/,
		'plain hashref child rejected by walker',
	);

	# Survives a follow-up render with a healthy tree (proves Clay's
	# internal stack was restored).
	my $ui2 = make_ui( TestWidget->new(id => 'recover') );
	my $cmds = $ui2->render;
	ok( scalar(@$cmds) > 0, 'fresh render after a failed one still works' );
};

done_testing;
