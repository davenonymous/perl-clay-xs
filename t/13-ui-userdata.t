use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Scalar::Util qw(refaddr);

use Clay::Layout qw(:all);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;

use Object::Pad;
use Clay::UI::Role::Element;

class ConflictWidget :does(Clay::UI::Role::Element) {
	method contribute_user ($cfg) {
		$cfg->{user_data} = 42;
	}
}

my @errors;
my $ctx = Clay_Initialize(
	Clay_MinMemorySize(),
	{ width => 400, height => 300 },
	sub ($err, $userdata) { push @errors, $err },
);
Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
	return { width => length($text) * 8, height => 16 };
});

# -----------------------------------------------------------------------------
# Walker injects refaddr as user_data; widget_for recovers the widget from
# the render command.
# -----------------------------------------------------------------------------

subtest 'round-trip widget back-reference' => sub {
	@errors = ();

	my $child_box = Clay::UI::Box->new(
		id               => 'child',
		layout           => { sizing => { width => sizing_fixed(80), height => sizing_fixed(40) } },
		background_color => [200, 100, 50, 255],
	);
	my $text_leaf = Clay::UI::Text->new( text => 'hi', font_size => 16 );

	my $root = Clay::UI::Box->new(
		id               => 'root',
		layout           => { sizing => { width => sizing_fixed(200), height => sizing_fixed(100) } },
		background_color => [40, 50, 60, 255],
		children         => [ $child_box, $text_leaf ],
	);

	Clay_BeginLayout();
	Clay::UI::layout($root);
	my $cmds = Clay_EndLayout(0);

	is( scalar(@errors), 0, 'no Clay errors' );

	my %widgets_seen;
	for my $cmd (@$cmds) {
		next unless $cmd->{userData};
		my $w = Clay::UI::widget_for($cmd->{userData});
		next unless defined $w;
		$widgets_seen{ refaddr $w } = $w;
	}

	is( $widgets_seen{ refaddr $root },      $root,      'root widget recovered' );
	is( $widgets_seen{ refaddr $child_box }, $child_box, 'child box recovered' );
	is( $widgets_seen{ refaddr $text_leaf }, $text_leaf, 'text leaf recovered' );
};

# -----------------------------------------------------------------------------
# A widget that sets user_data itself collides with the auto-injection.
# -----------------------------------------------------------------------------

subtest 'conflict on user-supplied user_data' => sub {
	Clay_BeginLayout();
	like(
		dies { Clay::UI::layout( ConflictWidget->new(id => 'x') ) },
		qr/set user_data in its config/,
		'widget that sets user_data dies with a clear message',
	);
	Clay_EndLayout(0);
};

# -----------------------------------------------------------------------------
# widget_for returns undef for unknown / falsy values.
# -----------------------------------------------------------------------------

subtest 'widget_for guards' => sub {
	is( Clay::UI::widget_for(undef), undef, 'undef -> undef' );
	is( Clay::UI::widget_for(0),     undef, '0 -> undef (Clay default for non-user elements)' );
	is( Clay::UI::widget_for(999),   undef, 'unknown integer -> undef' );
};

done_testing;
