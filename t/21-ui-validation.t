use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use lib 't/lib';

use Clay::XS qw(:all);
use Clay::UI;
use Clay::UI::Grid::Cell;
use Clay::UI::Events::OnPress;
use Clay::UI::Test::Box;
use Clay::UI::Test::Text;
use Clay::UI::Test::Grid;

use Object::Pad;
use Clay::UI::Role::Core::Stateful;
use Clay::UI::Role::Core::TextNode;
use Clay::UI::Role::Layout::HasScroll;
use Clay::UI::Role::Interaction::Hoverable;

class ScrollPanel :strict(params) :does(Clay::UI::Role::Layout::HasScroll) {}

# -----------------------------------------------------------------------------
# Input is validated where it enters Clay::UI: constructor parameters,
# render arguments and widget attributes.
# -----------------------------------------------------------------------------

sub make_ui ($root) {
	return Clay::UI->new(width => 100, height => 100, root => $root,
		measure_text => sub ($text, $config, $userdata) { return { width => 1, height => 1 } });
}

subtest 'misspelled constructor parameters die' => sub {
	like( dies { Clay::UI->new(width => 1, height => 1, root => Clay::UI::Test::Box->new, error_hanlder => sub { }) },
		qr/Unrecognised parameters for Clay::UI constructor: 'error_hanlder'/, 'Clay::UI' );
	like( dies { Clay::UI::Grid::Cell->new(bg_color => [1, 2, 3, 255]) },
		qr/Unrecognised parameters for Clay::UI::Grid::Cell constructor: 'bg_color'/, 'Grid::Cell' );
	like( dies { Clay::UI::Events::OnPress->new(bubble => 1) },
		qr/Unrecognised parameters for Clay::UI::Events::OnPress constructor: 'bubble'/, 'an event' );
	like( dies { Clay::UI::Test::Box->new(backgroud_color => [1, 2, 3, 255]) },
		qr/Unrecognised parameters for Clay::UI::Test::Box constructor: 'backgroud_color'/,
		'a consumer class declared :strict(params)' );
};

subtest 'render arguments are validated' => sub {
	my $ui = make_ui(Clay::UI::Test::Box->new(id => 'root'));
	like( dies { $ui->render(pointer => {}) }, qr/unknown argument\(s\): pointer/, 'unknown argument' );
	like( dies { $ui->render(pointer_state => [1, 2]) }, qr/'pointer_state' must be a hashref/, 'pointer_state type' );
	like( dies { $ui->render(pointer_state => { x => 1, y => 2, pressed => 1 }) },
		qr/unknown pointer_state key\(s\): pressed/, 'unknown pointer_state key' );
	like( dies { $ui->render(pointer_state => { x => 'left', y => 2 }) },
		qr/pointer_state 'x' must be a number/, 'non-numeric pointer position' );
	like( dies { $ui->render(delta_time => -1) }, qr/'delta_time' must be a finite number >= 0/, 'negative delta_time' );
	like( dies { $ui->render(scroll_delta => 5) }, qr/'scroll_delta' must be/, 'scalar scroll_delta' );
	like( dies { $ui->render(scroll_delta => { x => 0, yy => -1 }) }, qr/unknown scroll_delta key\(s\): yy/,
		'misspelled scroll_delta key' );
	like( dies { $ui->render(enable_drag_scrolling => {}) }, qr/'enable_drag_scrolling' must be a plain boolean/,
		'reference as a flag' );
	ok( lives { $ui->render(pointer_state => { x => 1, y => 2 }, scroll_delta => [0, -1], enable_drag_scrolling => 1) },
		'valid arguments are accepted' );
};

# -----------------------------------------------------------------------------
# Widget attributes: one invalid value per attribute dies at construction
# and through the accessor, naming the attribute.
# -----------------------------------------------------------------------------

my @invalid = (
	[ 'Clay::UI::Test::Box',  background_color => 'red',                       qr/'background_color' must be a colour/ ],
	[ 'Clay::UI::Test::Box',  background_color => [1, 2, 3],                   qr/'background_color' must be a colour/ ],
	[ 'Clay::UI::Test::Box',  background_color => { red => 1 },                qr/'background_color' has unknown key 'red'/ ],
	[ 'Clay::UI::Test::Box',  border_color     => [1, 2, 'x', 4],              qr/'border_color\[2\]' must be a finite number/ ],
	[ 'Clay::UI::Test::Box',  border_width     => { lft => 1 },                qr/'border_width' has unknown key 'lft'/ ],
	[ 'Clay::UI::Test::Box',  corner_radius    => 'round',                     qr/'corner_radius' must be a finite number/ ],
	[ 'Clay::UI::Test::Box',  layout           => [],                          qr/'layout' must be a hashref/ ],
	[ 'Clay::UI::Test::Box',  layout           => { padding => 8 },            qr/'layout\.padding' must be a hashref/ ],
	[ 'Clay::UI::Test::Box',  layout           => { child_gapp => 50 },        qr/'layout' has unknown key 'child_gapp'/ ],
	[ 'Clay::UI::Test::Box',  layout           => { sizing => { width => 5 } }, qr/'layout\.sizing\.width' must be a sizing hashref/ ],
	[ 'Clay::UI::Test::Box',  layout           => { layout_direction => 7 },   qr/'layout\.layout_direction' must be one of the Clay constants 0\.\.1/ ],
	[ 'Clay::UI::Test::Box',  floating         => { attach_too => 1 },         qr/'floating' has unknown key 'attach_too'/ ],
	[ 'Clay::UI::Test::Box',  floating         => { offset => 'up' },          qr/'floating\.offset' must be \[x, y\]/ ],
	[ 'Clay::UI::Test::Box',  width_group      => -1,                          qr/'width_group' must be an integer in 0\.\.1048575/ ],
	[ 'Clay::UI::Test::Box',  height_group     => 2**20,                       qr/'height_group' must be an integer in 0\.\.1048575/ ],
	[ 'Clay::UI::Test::Box',  id               => '',                          qr/'id' must be a non-empty string/ ],
	[ 'Clay::UI::Test::Box',  id               => 'anon:0:/0',                 qr/'id' must not start with 'anon:'/ ],
	[ 'ScrollPanel',          child_offset     => 5,                           qr/'child_offset' must be \[x, y\]/ ],
	[ 'ScrollPanel',          vertical         => [],                          qr/'vertical' must be a plain boolean value/ ],
	[ 'Clay::UI::Test::Text', text             => undef,                       qr/'text' must be a defined string/ ],
	[ 'Clay::UI::Test::Text', font_size        => 'big',                       qr/'font_size' must be a finite number/ ],
	[ 'Clay::UI::Test::Text', text_color       => 'black',                     qr/'text_color' must be a colour/ ],
	[ 'Clay::UI::Test::Text', wrap_mode        => 9,                           qr/'wrap_mode' must be one of the Clay constants 0\.\.2/ ],
	[ 'Clay::UI::Test::Text', text_alignment   => 'left',                      qr/'text_alignment' must be one of the Clay constants/ ],
	[ 'Clay::UI::Test::Grid', row_gap          => 'wide',                      qr/'row_gap' must be a finite number/ ],
	[ 'Clay::UI::Test::Grid', cell_gap         => undef,                       qr/'cell_gap' must be a finite number/ ],
);

subtest 'user ids cannot collide with derived ids' => sub {
	my $root = Clay::UI::Test::Box->new;
	$root->add_child(Clay::UI::Test::Box->new);
	my $ui = Clay::UI->new(width => 100, height => 100, root => $root);
	ok( lives { $ui->render }, 'derived ids render' );
	like( dies { Clay::UI::Test::Box->new(id => 'anon:0:/0') }, qr/reserved for the ids Clay::UI derives/,
		'the id the first child of an id-less root gets cannot be claimed' );
	ok( lives { Clay::UI::Test::Box->new(id => 'my-anon:1') }, "'anon:' elsewhere in an id is fine" );
};

subtest 'invalid attributes die at construction and through accessors' => sub {
	for my $case (@invalid) {
		my ($class, $name, $value, $error) = @$case;
		my %base = $class eq 'ScrollPanel' ? (id => 'scroll') : ();
		my $label = "$class $name => " . (ref $value ? ref $value : $value // 'undef');
		like( dies { $class->new(%base, $name => $value) }, $error, "$label at construction" );
		next if $name eq 'id';
		my $widget = $class->new(%base);
		like( dies { $widget->$name($value) }, $error, "$label through the accessor" );
	}
};

# Every key src/marshal.c reads is accepted, in snake_case and camelCase.
my %marshal_keys = (
	layout          => [qw(sizing padding child_gap child_alignment layout_direction)],
	padding         => [qw(left right top bottom)],
	child_alignment => [qw(x y)],
	sizing_axis     => [qw(type min max percent)],
	floating        => [qw(offset expand parent_id z_index attach_points pointer_capture_mode attach_to clip_to)],
	attach_points   => [qw(element parent)],
	color           => [qw(r g b a)],
	border_width    => [qw(left right top bottom between_children)],
	corner_radius   => [qw(top_left top_right bottom_left bottom_right)],
);
my %sample = (
	sizing => { width => sizing_fit() }, padding => padding_all(1), child_alignment => { x => 1 },
	offset => [1, 2], expand => { width => 1, height => 2 }, attach_points => { element => 1 },
);

subtest 'every key Clay::XS reads is accepted' => sub {
	for my $style ('snake_case', 'camelCase') {
		my $key = sub ($snake) { $style eq 'snake_case' ? $snake : Clay::UI::_keys::camelize_string($snake) };
		my %layout = map { $key->($_) => $sample{$_} // 1 } @{ $marshal_keys{layout} };
		$layout{ $key->('padding') } = { map { $key->($_) => 1 } @{ $marshal_keys{padding} } };
		$layout{ $key->('child_alignment') } = { map { $key->($_) => 1 } @{ $marshal_keys{child_alignment} } };
		$layout{sizing} = { width => { map { $key->($_) => 1 } @{ $marshal_keys{sizing_axis} } } };
		my %floating = map { $key->($_) => $sample{$_} // 1 } @{ $marshal_keys{floating} };
		$floating{ $key->('attach_points') } = { map { $key->($_) => 1 } @{ $marshal_keys{attach_points} } };
		ok( lives {
			Clay::UI::Test::Box->new(
				layout           => \%layout,
				floating         => \%floating,
				background_color => { map { $_ => 1 } @{ $marshal_keys{color} } },
				border_width     => { map { $key->($_) => 1 } @{ $marshal_keys{border_width} } },
				corner_radius    => { map { $key->($_) => 1 } @{ $marshal_keys{corner_radius} } },
			);
		}, "$style keys" ) or diag $@;
	}
};

subtest 'hover roles cannot be composed onto a text node' => sub {
	my $ok = eval q{
		class HoverText :does(Clay::UI::Role::Core::TextNode) :does(Clay::UI::Role::Interaction::Hoverable) {
			method text { 'x' }
			method text_config { {} }
		}
		1;
	};
	ok( $ok, 'the class compiles' ) or diag $@;
	like( dies { HoverText->new }, qr/wrap the text in an Element/, 'constructing it dies' );
};

done_testing;
