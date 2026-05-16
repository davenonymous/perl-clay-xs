use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::Layout qw(:all);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;
use Clay::UI::Button;
use Clay::UI::ScrollPanel;

my @errors;
my $error_handler = sub ($err, $userdata) { push @errors, $err };
my $measure_text  = sub ($text, $config, $userdata) {
	return { width => length($text) * ($config->{fontSize} // 16), height => $config->{fontSize} // 16 };
};

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
# Box composes every property mixin; declaration round-trips through Clay.
# -----------------------------------------------------------------------------

subtest 'Box with all styling slices' => sub {
	@errors = ();
	my $ui = make_ui(
		Clay::UI::Box->new(
			id               => 'styled',
			layout           => {
				sizing  => { width => sizing_fixed(200), height => sizing_fixed(100) },
				padding => { left => 8, right => 8, top => 4, bottom => 4 },
			},
			background_color => [40, 50, 60, 255],
			border_color     => [100, 100, 100, 255],
			border_width     => 1,
			corner_radius    => 4,
		),
	);
	my $cmds = $ui->render;

	is( scalar(@errors), 0, 'no Clay errors' );

	my ($rect) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_RECTANGLE } @$cmds;
	ok( defined $rect, 'rectangle emitted' );
	is( $rect->{renderData}{backgroundColor}{r}, 40, 'background r' );
	is( $rect->{renderData}{cornerRadius}{topLeft}, 4, 'corner expanded to four sides' );

	my ($border) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_BORDER } @$cmds;
	ok( defined $border, 'border emitted' );
	is( $border->{renderData}{width}{left}, 1, 'border width left' );
};

# -----------------------------------------------------------------------------
# Text leaf dispatches to Clay__OpenTextElement.
# -----------------------------------------------------------------------------

subtest 'Text inside a Box' => sub {
	@errors = ();
	my $ui = make_ui(
		Clay::UI::Box->new(
			id       => 'wrapper',
			layout   => { sizing => { width => sizing_fixed(200), height => sizing_fixed(50) } },
			children => [
				Clay::UI::Text->new(
					text       => 'hello',
					font_size  => 16,
					text_color => [255, 255, 255, 255],
				),
			],
		),
	);
	my $cmds = $ui->render;

	is( scalar(@errors), 0, 'no Clay errors' );

	my ($txt) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_TEXT } @$cmds;
	ok( defined $txt, 'text command emitted' );
	is( $txt->{renderData}{textColor}{r}, 255, 'text color r' );
	is( $txt->{renderData}{fontSize}, 16, 'font size' );
};

# -----------------------------------------------------------------------------
# Stateful: ScrollPanel demands an id.
# -----------------------------------------------------------------------------

subtest 'ScrollPanel requires id' => sub {
	like(
		dies { Clay::UI::ScrollPanel->new },
		qr/requires an explicit 'id'/,
		'missing id fails loud',
	);

	my $panel = Clay::UI::ScrollPanel->new(
		id     => 'log',
		layout => { sizing => { width => sizing_grow(), height => sizing_fixed(100) } },
	);
	ok( defined $panel, 'with id constructs' );
};

# -----------------------------------------------------------------------------
# ScrollPanel emits a clip slice via its custom contribute_scroll method.
# -----------------------------------------------------------------------------

subtest 'ScrollPanel emits scroll container' => sub {
	@errors = ();
	my $ui = make_ui(
		Clay::UI::ScrollPanel->new(
			id     => 'log',
			layout => { sizing => { width => sizing_fixed(200), height => sizing_fixed(100) } },
		),
	);
	my $cmds = $ui->render;

	is( scalar(@errors), 0, 'no Clay errors' );

	# A scroll container emits SCISSOR_START + SCISSOR_END markers.
	my @scissors = grep {
		$_->{commandType} == CLAY_RENDER_COMMAND_TYPE_SCISSOR_START
	 || $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_SCISSOR_END
	} @$cmds;
	is( scalar(@scissors), 2, 'scissor start + end emitted (proves clip slice landed)' );

	# Scroll container should now be queryable.
	my $data = Clay_GetScrollContainerData( Clay_GetElementId('log') );
	ok( $data->{found}, 'scroll container registered with Clay' );
};

# -----------------------------------------------------------------------------
# Button hover + click callback dispatch.
# -----------------------------------------------------------------------------

subtest 'Button dispatches hover and click' => sub {
	@errors = ();

	my @hover_calls;
	my @click_calls;

	my $button = Clay::UI::Button->new(
		id               => 'btn',
		layout           => { sizing => { width => sizing_fixed(100), height => sizing_fixed(40) } },
		background_color => [70, 130, 200, 255],
		on_hover         => sub ($id, $pointer, $ud) { push @hover_calls, $pointer->{position} },
		on_click         => sub ($id, $pointer, $ud) { push @click_calls, $pointer->{position} },
	);
	my $ui = make_ui($button);

	# Frame 1: build geometry (no pointer state yet).
	$ui->render;

	# Warm-up: Clay's pointer state struct is zero-initialised, which
	# means the FIRST Clay_SetPointerState call dispatches hover with
	# state=PRESSED_THIS_FRAME (0) regardless of isPointerDown. Push one
	# unpressed-and-out-of-bounds state to settle Clay into RELEASED
	# before the real test frames begin.
	$ui->render( pointer_state => { x => -100, y => -100, down => 0 } );

	@hover_calls = ();
	@click_calls = ();

	# Frame 2: pointer hovering, not pressed.
	$ui->render( pointer_state => { x => 50, y => 20, down => 0 } );

	is( scalar(@hover_calls), 1, 'on_hover fired while pointer over element' );
	is( scalar(@click_calls), 0, 'on_click did not fire without press' );

	# Frame 3: button pressed. Clay's hover dispatch uses the CURRENT
	# state (still RELEASED) and only transitions to PRESSED_THIS_FRAME
	# after dispatching. So the press is observed on frame 4.
	$ui->render( pointer_state => { x => 50, y => 20, down => 1 } );

	is( scalar(@hover_calls), 2, 'on_hover fired again' );
	is( scalar(@click_calls), 0, 'on_click pending: state transitioned to PRESSED_THIS_FRAME post-dispatch' );

	# Frame 4: dispatch now sees PRESSED_THIS_FRAME.
	$ui->render( pointer_state => { x => 50, y => 20, down => 1 } );

	is( scalar(@click_calls), 1, 'on_click fired once the PRESSED_THIS_FRAME state was visible' );
};

# -----------------------------------------------------------------------------
# Text without an Element wrapper at root level still works.
# -----------------------------------------------------------------------------

subtest 'bare Text at root' => sub {
	@errors = ();
	my $ui = make_ui(
		Clay::UI::Box->new(
			id => 'root',
			layout => { sizing => { width => sizing_grow(), height => sizing_grow() } },
			children => [ Clay::UI::Text->new( text => 'standalone' ) ],
		),
	);
	my $cmds = $ui->render;

	is( scalar(@errors), 0, 'no Clay errors' );
	my ($txt) = grep { $_->{commandType} == CLAY_RENDER_COMMAND_TYPE_TEXT } @$cmds;
	ok( defined $txt, 'text leaf rendered' );
};

done_testing;
