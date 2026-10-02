use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use lib 't/lib';

use Object::Pad 0.800;
use Clay::UI;
use Clay::UI::Revision qw(bump_revision current_revision);
use Clay::UI::Test::Box;
use Clay::UI::Test::Text;
use Clay::UI::Test::Grid;
use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Core::Stateful;
use Clay::UI::Role::Layout::HasScroll;
use Clay::UI::Role::Interaction::Hoverable;
use Clay::UI::Role::Interaction::Focusable;

# -----------------------------------------------------------------------------
# The process-wide revision grows whenever something a frame lays out or
# draws changes, so a renderer can skip frames while it stays the same.
# -----------------------------------------------------------------------------

class ScrollPanel :strict(params) :does(Clay::UI::Role::Layout::HasScroll) {}

class HoverBox :strict(params)
	:does(Clay::UI::Role::Core::Container)
	:does(Clay::UI::Role::Interaction::Hoverable)
{}

class FocusBox :strict(params)
	:does(Clay::UI::Role::Core::Container)
	:does(Clay::UI::Role::Interaction::Focusable)
{}

sub bumps ($code) {
	my $before = current_revision();
	$code->();
	return current_revision() > $before ? 1 : 0;
}

subtest 'bump_revision increments the counter and returns it' => sub {
	my $before = current_revision();
	like( $before, qr/\A[0-9]+\z/, 'the counter is a non-negative integer' );
	is( bump_revision(), $before + 1, 'bump_revision returns the new value' );
	is( current_revision(), $before + 1, 'current_revision reports it' );
};

my $box    = Clay::UI::Test::Box->new(id => 'box');
my $text   = Clay::UI::Test::Text->new(text => 'hi');
my $scroll = ScrollPanel->new(id => 'scroll');
my $grid   = Clay::UI::Test::Grid->new(id => 'grid');
my $hover  = HoverBox->new(id => 'hover');

# [ name, write, read ] for a sample of the setters.
my @setters = (
	[ 'layout',           sub { $box->layout({ child_gap => 4 }) },             sub { $box->layout } ],
	[ 'background_color', sub { $box->background_color([1, 2, 3, 255]) },       sub { $box->background_color } ],
	[ 'border_width',     sub { $box->border_width(2) },                        sub { $box->border_width } ],
	[ 'corner_radius',    sub { $box->corner_radius(3) },                       sub { $box->corner_radius } ],
	[ 'floating',         sub { $box->floating({ z_index => 1 }) },             sub { $box->floating } ],
	[ 'width_group',      sub { $box->width_group(5) },                         sub { $box->width_group } ],
	[ 'vertical',         sub { $scroll->vertical(0) },                         sub { $scroll->vertical } ],
	[ 'text',             sub { $text->text('ho') },                            sub { $text->text } ],
	[ 'text_color',       sub { $text->text_color([9, 9, 9, 255]) },            sub { $text->text_color } ],
	[ 'row_gap',          sub { $grid->row_gap(2) },                            sub { $grid->row_gap } ],
	[ 'append_row',       sub { $grid->append_row([ Clay::UI::Test::Text->new ]) }, sub { $grid->row_count } ],
	[ 'add_state',        sub { $hover->add_state('selected') },                sub { $hover->has_state('selected') } ],
	[ 'clear_states',     sub { $hover->clear_states },                         sub { $hover->states } ],
	[ 'add_child',        sub { $box->add_child(Clay::UI::Test::Box->new(id => 'kid')) }, sub { $box->children } ],
	[ 'remove_child',     sub { $box->remove_child('kid') },                    sub { $box->get_children_with(sub { 1 }) } ],
);

subtest 'widget setters bump the revision' => sub {
	ok( bumps($_->[1]), $_->[0] ) for @setters;
};

subtest 'reading an attribute does not bump the revision' => sub {
	ok( !bumps($_->[2]), $_->[0] ) for @setters;
};

subtest 'mark_changed bumps the revision and returns the widget' => sub {
	my $returned;
	ok( bumps(sub { $returned = $box->mark_changed }), 'on an element' );
	ref_is( $returned, $box, 'which it returns' );
	ok( bumps(sub { $returned = $text->mark_changed }), 'on a text node' );
	ref_is( $returned, $text, 'which it returns' );
};

subtest 'resizing the viewport bumps the revision' => sub {
	my $ui = Clay::UI->new(width => 100, height => 100, root => Clay::UI::Test::Box->new);
	ok( bumps(sub { $ui->width(120) }),  'width' );
	ok( bumps(sub { $ui->height(80) }),  'height' );
	ok( !bumps(sub { $ui->width; $ui->height }), 'reading them does not' );
};

subtest 'hover changes bump the revision' => sub {
	my $root   = Clay::UI::Test::Box->new(id => 'page');
	my $target = HoverBox->new(id => 'target');
	$root->add_child($target);
	my $ui = Clay::UI->new(width => 100, height => 100, root => $root);

	ok( bumps(sub { $ui->interaction->update(over => [$target], down => 0) }), 'hover starts' );
	ok( !bumps(sub { $ui->interaction->update(over => [$target], down => 0) }), 'staying hovered does not' );
	ok( bumps(sub { $ui->interaction->update(over => [], down => 0) }), 'hover stops' );
};

subtest 'focus changes bump the revision' => sub {
	my $root  = Clay::UI::Test::Box->new(id => 'page');
	my $input = FocusBox->new(id => 'input');
	$root->add_child($input);
	my $ui = Clay::UI->new(width => 100, height => 100, root => $root);

	ok( bumps(sub { $ui->interaction->set_focused_widget($input) }), 'focusing' );
	ok( !bumps(sub { $ui->interaction->set_focused_widget($input) }), 'focusing the focused widget again does not' );
	ok( bumps(sub { $ui->interaction->set_focused_widget(undef) }), 'blurring' );
};

done_testing;
