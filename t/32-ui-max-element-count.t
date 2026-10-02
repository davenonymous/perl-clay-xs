use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use lib 't/lib';

use Clay::XS qw(Clay_MinMemorySize);
use Clay::UI;
use Clay::UI::Test::Box;

# -----------------------------------------------------------------------------
# max_element_count sizes each Clay::UI's own context; a tree that does not
# fit fails with an error that says so.
# -----------------------------------------------------------------------------

sub make_ui ($box_count, %params) {
	my $root = Clay::UI::Test::Box->new(id => 'root');
	$root->add_child(map { Clay::UI::Test::Box->new } 1 .. $box_count);
	return Clay::UI->new(width => 100, height => 100, root => $root, %params);
}

subtest 'max_element_count is validated' => sub {
	for my $bad (0, -1, 1.5, 'many', [1]) {
		like( dies { make_ui(0, max_element_count => $bad) },
			qr/'max_element_count' must be a positive integer/, "rejects '$bad'" );
	}
};

subtest 'the default is 8192' => sub {
	is( make_ui(0)->max_element_count, 8192, 'reader reports the default' );
};

subtest 'a larger count lets a UI render a larger tree' => sub {
	my $small = make_ui(1);
	my $big   = make_ui(10_000, max_element_count => 20_000);
	is( $big->max_element_count, 20_000, 'reader reports the count' );
	ok( lives { $big->render }, '10000 boxes render' ) or note $@;
	ok( lives { $small->render }, 'the UI that was current meanwhile still renders' ) or note $@;
};

subtest "memory_size must fit this UI's count" => sub {
	make_ui(0);
	my $default_minimum = Clay_MinMemorySize();
	like( dies { make_ui(0, max_element_count => 20_000, memory_size => $default_minimum) },
		qr/'memory_size' must be an integer >= Clay_MinMemorySize\(\) \(\d+\) for max_element_count 20000/,
		'the minimum for the default count is too small' );
};

subtest 'a tree larger than max_element_count fails with a clear error' => sub {
	my $ui = make_ui(9000);
	like( dies { $ui->render },
		qr/\AClay::UI: the widget tree has more elements than max_element_count \(8192\) allows: 9001 widgets, at most 8190 fit; pass a larger max_element_count/,
		'the error names the parameter' );
};

subtest "a user error_handler gets Clay's own error" => sub {
	my @errors;
	my $ui = make_ui(9000, error_handler => sub ($error, $userdata) { push @errors, $error; return });
	ok( lives { $ui->render }, 'render returns as the handler did' ) or note $@;
	like( $errors[0]{errorText}, qr/still open layout elements/, 'the handler saw the raw Clay error' );
};

done_testing;
