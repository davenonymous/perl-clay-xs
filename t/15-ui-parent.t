use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;
use Scalar::Util qw(refaddr);

sub same ($a, $b, $name) { is(refaddr($a), refaddr($b), $name) }

use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;

# -----------------------------------------------------------------------------
# Parent stamping: children attached via add_child get their parent slot
# filled before any tree walk runs.
# -----------------------------------------------------------------------------

subtest 'root widget has no parent and is its own root' => sub {
	my $root = Clay::UI::Box->new;
	is($root->parent, undef, 'root parent is undef');
	same($root->root, $root, 'root->root is itself');
};

subtest 'children added via add_child are parent-stamped' => sub {
	my $parent = Clay::UI::Box->new(id => 'p');
	my $kid    = Clay::UI::Box->new(id => 'k');
	$parent->add_child($kid);
	same($kid->parent, $parent, 'add_child stamps parent');
	same($kid->root,   $parent, 'add_child child root resolves');
};

subtest 'TextNode children are parent-stamped too' => sub {
	my $text = Clay::UI::Text->new(text => 'hi');
	my $box  = Clay::UI::Box->new;
	$box->add_child($text);
	same($text->parent, $box, 'text node parent set');
	same($text->root,   $box, 'text node root resolves');
};

# -----------------------------------------------------------------------------
# Deep chains: root walks all the way to the top, no matter the depth.
# -----------------------------------------------------------------------------

subtest 'root walks a multi-level chain' => sub {
	my $leaf = Clay::UI::Box->new(id => 'leaf');
	my $b    = Clay::UI::Box->new(id => 'b');
	$b->add_child($leaf);
	my $a    = Clay::UI::Box->new(id => 'a');
	$a->add_child($b);
	my $root = Clay::UI::Box->new(id => 'r');
	$root->add_child($a);
	same($leaf->root, $root, 'leaf->root reaches the top');
	same($b->root,    $root, 'mid-chain->root reaches the top');
	same($a->root,    $root, 'one-from-top->root reaches the top');
};

# -----------------------------------------------------------------------------
# No reparenting: a widget can be attached exactly once, ever.
# -----------------------------------------------------------------------------

subtest 'adding an already-parented widget to a second parent dies' => sub {
	my $kid = Clay::UI::Box->new(id => 'k');
	my $p1  = Clay::UI::Box->new;
	$p1->add_child($kid);
	my $p2  = Clay::UI::Box->new;
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
	my $kid = Clay::UI::Box->new(id => 'k');
	my $p   = Clay::UI::Box->new;
	$p->add_child($kid);
	like(
		dies { $p->add_child($kid) },
		qr/no reparenting/,
		'second add under same parent dies',
	);
};

subtest 'remove_child leaves the parent slot intact (permanent brick)' => sub {
	# Detached widgets are permanently bricked: their parent slot is
	# still set, so they can never be attached anywhere else. Build a
	# fresh widget per mount instead of reusing.
	my $kid = Clay::UI::Box->new(id => 'k');
	my $p1  = Clay::UI::Box->new;
	$p1->add_child($kid);
	$p1->remove_child('k');
	same($kid->parent, $p1, 'parent slot survives remove_child');
	my $p2 = Clay::UI::Box->new;
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
		my $parent = Clay::UI::Box->new;
		$parent->add_child(Clay::UI::Box->new(id => 'k'));
		($kid) = @{ $parent->children };
		same($kid->parent, $parent, 'parent set inside scope');
	}
	# $parent has now gone out of scope; the parent's children arrayref
	# was the only strong ref to $kid above, so we held $kid out via the
	# direct assignment above. The weak parent slot should now read undef.
	is($kid->parent, undef, 'parent slot collapses to undef after GC');
	same($kid->root, $kid,  'root falls back to self once chain is gone');
};

# -----------------------------------------------------------------------------
# Non-widget children still rejected at add_child.
# -----------------------------------------------------------------------------

subtest 'non-widget children are rejected by add_child' => sub {
	my $p = Clay::UI::Box->new;
	like(
		dies { $p->add_child('not a widget') },
		qr/not a widget/,
		'add_child rejects non-widgets',
	);
};

# -----------------------------------------------------------------------------
# Clay::UI back-reference: every widget reachable from the root can find
# its Clay::UI controller via $self->ui.
# -----------------------------------------------------------------------------

subtest 'unattached widget ui() is undef' => sub {
	my $w = Clay::UI::Box->new;
	is($w->ui, undef, 'no ui controller before Clay::UI->new');
};

subtest 'Clay::UI stamps itself on the root; descendants reach it via ui()' => sub {
	my $leaf = Clay::UI::Box->new(id => 'leaf');
	my $mid  = Clay::UI::Box->new(id => 'mid');
	$mid->add_child($leaf);
	my $root = Clay::UI::Box->new(id => 'root');
	$root->add_child($mid);
	my $ui   = Clay::UI->new(root => $root, width => 100, height => 100);

	same($root->ui, $ui, 'root sees its Clay::UI');
	same($mid->ui,  $ui, 'descendant sees Clay::UI through root walk');
	same($leaf->ui, $ui, 'deep descendant sees Clay::UI');
};

subtest 'second Clay::UI on the same root dies' => sub {
	my $root = Clay::UI::Box->new;
	my $ui   = Clay::UI->new(root => $root, width => 100, height => 100);
	like(
		dies { Clay::UI->new(root => $root, width => 50, height => 50) },
		qr/already bound/,
		'cannot re-attach root to a second Clay::UI',
	);
};

done_testing;
