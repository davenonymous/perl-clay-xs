use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use lib "t/lib";
use Scalar::Util qw(refaddr);

sub same ($a, $b, $name) { is(refaddr($a), refaddr($b), $name) }

use Object::Pad 0.800;
use Clay::UI;
use Clay::UI::Test::Box;
use Clay::UI::Test::Grid;
use Clay::UI::Test::Text;
use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Interaction::Focusable;

class FocusBox :strict(params)
	:does(Clay::UI::Role::Core::Container)
	:does(Clay::UI::Role::Interaction::Focusable)
{}

# -----------------------------------------------------------------------------
# Parent stamping: children attached via add_child get their parent slot
# filled before any tree walk runs.
# -----------------------------------------------------------------------------

subtest 'root widget has no parent and is its own root' => sub {
	my $root = Clay::UI::Test::Box->new;
	is($root->parent, undef, 'root parent is undef');
	same($root->root, $root, 'root->root is itself');
};

subtest 'children added via add_child are parent-stamped' => sub {
	my $parent = Clay::UI::Test::Box->new(id => 'p');
	my $kid    = Clay::UI::Test::Box->new(id => 'k');
	$parent->add_child($kid);
	same($kid->parent, $parent, 'add_child stamps parent');
	same($kid->root,   $parent, 'add_child child root resolves');
};

subtest 'TextNode children are parent-stamped too' => sub {
	my $text = Clay::UI::Test::Text->new(text => 'hi');
	my $box  = Clay::UI::Test::Box->new;
	$box->add_child($text);
	same($text->parent, $box, 'text node parent set');
	same($text->root,   $box, 'text node root resolves');
};

# -----------------------------------------------------------------------------
# Deep chains: root walks all the way to the top, no matter the depth.
# -----------------------------------------------------------------------------

subtest 'root walks a multi-level chain' => sub {
	my $leaf = Clay::UI::Test::Box->new(id => 'leaf');
	my $b    = Clay::UI::Test::Box->new(id => 'b');
	$b->add_child($leaf);
	my $a    = Clay::UI::Test::Box->new(id => 'a');
	$a->add_child($b);
	my $root = Clay::UI::Test::Box->new(id => 'r');
	$root->add_child($a);
	same($leaf->root, $root, 'leaf->root reaches the top');
	same($b->root,    $root, 'mid-chain->root reaches the top');
	same($a->root,    $root, 'one-from-top->root reaches the top');
};

# -----------------------------------------------------------------------------
# No reparenting: a widget can be attached exactly once, ever.
# -----------------------------------------------------------------------------

subtest 'adding an already-parented widget to a second parent dies' => sub {
	my $kid = Clay::UI::Test::Box->new(id => 'k');
	my $p1  = Clay::UI::Test::Box->new;
	$p1->add_child($kid);
	my $p2  = Clay::UI::Test::Box->new;
	like(
		dies { $p2->add_child($kid) },
		qr/no reparenting/,
		'second-parent attempt dies with descriptive message',
	);
};

subtest 'adding the same widget twice to the same parent also dies' => sub {
	# Re-add is treated identically to a conflict: the parent slot is
	# write-once, no exceptions. Idempotent-builder patterns must build
	# fresh widgets per call rather than re-attaching cached ones.
	my $kid = Clay::UI::Test::Box->new(id => 'k');
	my $p   = Clay::UI::Test::Box->new;
	$p->add_child($kid);
	like(
		dies { $p->add_child($kid) },
		qr/no reparenting/,
		'second add under same parent dies',
	);
};

subtest 'remove_child detaches the widget for good' => sub {
	# Removal detaches: the parent slot is cleared and the widget becomes
	# the root of its own subtree, but it can never be attached again.
	my $kid = Clay::UI::Test::Box->new(id => 'k');
	my $p1  = Clay::UI::Test::Box->new;
	$p1->add_child($kid);
	$p1->remove_child('k');
	is($kid->parent, undef, 'parent slot cleared by remove_child');
	same($kid->root, $kid, 'the removed widget is the root of its subtree');
	my $p2 = Clay::UI::Test::Box->new;
	like(
		dies { $p2->add_child($kid) },
		qr/no reparenting/,
		'detached widget still cannot be reattached',
	);
};

# -----------------------------------------------------------------------------
# Weak-ref behaviour: the parent slot does not keep the parent alive.
# -----------------------------------------------------------------------------

subtest 'parent slot is a weak reference' => sub {
	my $kid;
	{
		my $parent = Clay::UI::Test::Box->new;
		$parent->add_child(Clay::UI::Test::Box->new(id => 'k'));
		($kid) = @{ $parent->children };
		same($kid->parent, $parent, 'parent set inside scope');
	}
	# $parent is gone; $kid survives through the lexical above, and its
	# weak parent slot reads undef.
	is($kid->parent, undef, 'parent slot collapses to undef after GC');
	same($kid->root, $kid,  'root falls back to self once chain is gone');
};

# -----------------------------------------------------------------------------
# add_child rejects non-widget children.
# -----------------------------------------------------------------------------

subtest 'non-widget children are rejected by add_child' => sub {
	my $p = Clay::UI::Test::Box->new;
	like(
		dies { $p->add_child('not a widget') },
		qr/not a widget/,
		'add_child rejects non-widgets',
	);
};

# -----------------------------------------------------------------------------
# add_child validates the whole call before changing anything.
# -----------------------------------------------------------------------------

subtest 'a failed add_child changes nothing' => sub {
	my $p     = Clay::UI::Test::Box->new(id => 'p');
	my $new   = Clay::UI::Test::Box->new(id => 'new');
	my $other = Clay::UI::Test::Box->new;
	my $old   = Clay::UI::Test::Box->new(id => 'old');
	$other->add_child($old);

	like( dies { $p->add_child($new, $old) }, qr/has been attached before; no reparenting/,
		'an already-parented kid fails the call' );
	is( $new->parent, undef, 'the valid kid was not parented' );
	is( scalar @{ $p->children }, 0, 'the parent has no new children' );
	ok( lives { $p->add_child($new) }, 'the valid kid can still be attached' );

	my $k = Clay::UI::Test::Box->new(id => 'k');
	like( dies { $p->add_child($k, $k) }, qr/attached twice in one call/, 'a duplicate within one call dies' );
	is( $k->parent, undef, 'and leaves the kid unattached' );
};

subtest 'cycles are rejected' => sub {
	my $s = Clay::UI::Test::Box->new(id => 's');
	like( dies { $s->add_child($s) }, qr/cannot attach a widget to itself or to one of its descendants/,
		'a widget cannot be its own child' );

	my $top  = Clay::UI::Test::Box->new(id => 'top');
	my $leaf = Clay::UI::Test::Box->new(id => 'leaf');
	$top->add_child($leaf);
	like( dies { $leaf->add_child($top) }, qr/cannot attach a widget to itself or to one of its descendants/,
		'an ancestor cannot become a child' );
	same( $leaf->root, $top, 'the tree is unchanged' );
};

subtest 'a Clay::UI root cannot become a child' => sub {
	my $root = Clay::UI::Test::Box->new(id => 'root');
	my $ui   = Clay::UI->new(root => $root, width => 100, height => 100);
	like( dies { Clay::UI::Test::Box->new->add_child($root) }, qr/is the root of a Clay::UI/,
		'bound root rejected' );
};

subtest 'children returns a copy' => sub {
	my $p = Clay::UI::Test::Box->new;
	$p->add_child(Clay::UI::Test::Box->new);
	push @{ $p->children }, 'junk';
	is( scalar @{ $p->children }, 1, 'changing the returned array does not change the widget' );
};

subtest 'a removed widget whose old parent is gone still cannot be reattached' => sub {
	my $kid = Clay::UI::Test::Box->new(id => 'k');
	{
		my $parent = Clay::UI::Test::Box->new;
		$parent->add_child($kid);
	}
	is( $kid->parent, undef, 'the old parent is gone' );
	like( dies { Clay::UI::Test::Box->new->add_child($kid) }, qr/no reparenting/, 'reattaching dies' );
	like( dies { Clay::UI->new(root => $kid, width => 10, height => 10) }, qr/'root' must not have a parent/,
		'and it cannot become a Clay::UI root either' );
};

# -----------------------------------------------------------------------------
# Clay::UI back-reference: every widget reachable from the root can find
# its Clay::UI controller via $self->ui.
# -----------------------------------------------------------------------------

subtest 'unattached widget ui() is undef' => sub {
	my $w = Clay::UI::Test::Box->new;
	is($w->ui, undef, 'no ui controller before Clay::UI->new');
};

subtest 'a removed subtree has no controller' => sub {
	my $root   = Clay::UI::Test::Box->new(id => 'root');
	my $branch = Clay::UI::Test::Box->new(id => 'branch');
	my $leaf   = Clay::UI::Test::Box->new(id => 'leaf');
	$branch->add_child($leaf);
	$root->add_child($branch);
	my $ui = Clay::UI->new(root => $root, width => 100, height => 100);
	same($leaf->ui, $ui, 'attached leaf reaches the controller');
	$root->remove_child('branch');
	is($branch->ui, undef, 'removed widget has no controller');
	is($leaf->ui,   undef, 'nor do its descendants');
};

subtest 'a dying OnBlur listener does not stop the detachment' => sub {
	my $root  = Clay::UI::Test::Box->new(id => 'root');
	my $panel = Clay::UI::Test::Box->new(id => 'panel');
	my $input = FocusBox->new(id => 'input');
	$panel->add_child($input);
	$root->add_child($panel);
	my $ui = Clay::UI->new(root => $root, width => 100, height => 100);
	$ui->set_focused_widget($input);
	$input->on('OnBlur', sub ($e) { die "blur listener bug\n" });

	like( dies { $root->remove_child('panel') }, qr/^blur listener bug$/, 'remove_child dies with the listener error' );
	is( scalar @{ $root->children }, 0, 'the panel was removed' );
	is( $panel->parent, undef, 'and detached' );
	is( $input->ui, undef, 'its subtree has no controller' );
	is( $ui->get_focused_widget, undef, 'focus was released' );
	like( dies { $ui->set_focused_widget($input) }, qr/does not belong to this Clay::UI/,
		'the removed widget cannot be focused again' );

	my $grid = Clay::UI::Test::Grid->new(id => 'grid');
	my $cell = FocusBox->new(id => 'cell');
	$grid->append_row([ $cell ]);
	my $grid_ui = Clay::UI->new(root => $grid, width => 100, height => 100);
	$grid_ui->set_focused_widget($cell);
	$cell->on('OnBlur', sub ($e) { die "blur listener bug\n" });
	like( dies { $grid->remove_row(0) }, qr/^blur listener bug$/, 'remove_row dies with the listener error' );
	is( $grid->row_count, 0, 'the row was removed' );
	is( $cell->ui, undef, 'the cell is detached' );
	is( $grid_ui->get_focused_widget, undef, 'focus was released' );
};

subtest 'Clay::UI stamps itself on the root; descendants reach it via ui()' => sub {
	my $leaf = Clay::UI::Test::Box->new(id => 'leaf');
	my $mid  = Clay::UI::Test::Box->new(id => 'mid');
	$mid->add_child($leaf);
	my $root = Clay::UI::Test::Box->new(id => 'root');
	$root->add_child($mid);
	my $ui   = Clay::UI->new(root => $root, width => 100, height => 100);

	same($root->ui, $ui, 'root sees its Clay::UI');
	same($mid->ui,  $ui, 'descendant sees Clay::UI through root walk');
	same($leaf->ui, $ui, 'deep descendant sees Clay::UI');
};

subtest 'a widget with a parent cannot be a Clay::UI root' => sub {
	my $app   = Clay::UI::Test::Box->new(id => 'app');
	my $panel = Clay::UI::Test::Box->new(id => 'panel');
	$app->add_child($panel);
	like(
		dies { Clay::UI->new(root => $panel, width => 100, height => 100) },
		qr/'root' must not have a parent/,
		'Clay::UI->new rejects a parented root',
	);
};

subtest 'second Clay::UI on the same root dies' => sub {
	my $root = Clay::UI::Test::Box->new;
	my $ui   = Clay::UI->new(root => $root, width => 100, height => 100);
	like(
		dies { Clay::UI->new(root => $root, width => 50, height => 50) },
		qr/already bound/,
		'cannot re-attach root to a second Clay::UI',
	);
};

done_testing;
