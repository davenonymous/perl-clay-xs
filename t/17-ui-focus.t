use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;
use Scalar::Util qw(refaddr);

use Object::Pad 0.800;

use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Role::Core::Element;
use Clay::UI::Role::Interaction::Focusable;
use Clay::UI::Role::Interaction::HasFocusOrder;

sub same ($a, $b, $name) { is(refaddr($a), refaddr($b), $name) }

# -----------------------------------------------------------------------------
# Test fixtures.
# -----------------------------------------------------------------------------

class TestInput
	:does(Clay::UI::Role::Core::Element)
	:does(Clay::UI::Role::Interaction::Focusable)
{
	field $disabled :param :reader = 0;
	ADJUST { $self->can_focus(0) if $disabled }
}

# Container that always returns the same widget first, then defers.
class TestOverride
	:does(Clay::UI::Role::Core::Element)
	:does(Clay::UI::Role::Interaction::HasFocusOrder)
{
	use Scalar::Util qw(refaddr);
	field $target :param :reader;

	method get_next_focus {
		my $current = $self->ui->get_focused_widget;
		# If we don't already point at our target, jump to it.
		return $target if !defined($current) || refaddr($current) != refaddr($target);
		# Otherwise behave like the default order would.
		return $self->default_next_focus;
	}

	method get_previous_focus { $self->default_previous_focus }
}

# Helper: build a UI with a box that contains the given children.
sub make_ui (@children) {
	my $root = Clay::UI::Box->new(id => 'root', children => [@children]);
	return Clay::UI->new(root => $root, width => 100, height => 100);
}

# -----------------------------------------------------------------------------
# Focusable defaults.
# -----------------------------------------------------------------------------

subtest 'Focusable defaults: can_focus returns 1; is_focused false before focus' => sub {
	my $a  = TestInput->new(id => 'a');
	my $ui = make_ui($a);

	is($a->can_focus, 1, 'can_focus default is 1');
	is($a->is_focused, 0, 'is_focused starts false');
	is($ui->get_focused_widget, undef, 'no widget focused initially');
};

subtest 'can_focus override (disabled widget)' => sub {
	my $a = TestInput->new(id => 'a', disabled => 1);
	make_ui($a);
	is($a->can_focus, 0, 'disabled widget can_focus is 0');
};

# -----------------------------------------------------------------------------
# set_focused_widget validation.
# -----------------------------------------------------------------------------

subtest 'set_focused_widget rejects non-Focusable widgets' => sub {
	my $a  = TestInput->new(id => 'a');
	my $b  = Clay::UI::Box->new(id => 'b');   # not Focusable
	my $ui = make_ui($a, $b);

	like(
		dies { $ui->set_focused_widget($b) },
		qr/must consume Clay::UI::Role::Interaction::Focusable/,
		'rejects non-Focusable widget',
	);
};

subtest 'set_focused_widget rejects can_focus == 0 widgets' => sub {
	my $a  = TestInput->new(id => 'a', disabled => 1);
	my $ui = make_ui($a);

	like(
		dies { $ui->set_focused_widget($a) },
		qr/not currently focusable/,
		'rejects disabled widget',
	);
};

subtest 'set_focused_widget rejects widgets from a different Clay::UI' => sub {
	my $a   = TestInput->new(id => 'a');
	my $ui1 = make_ui($a);
	my $b   = TestInput->new(id => 'b');
	my $ui2 = make_ui($b);

	like(
		dies { $ui1->set_focused_widget($b) },
		qr/does not belong to this Clay::UI/,
		'rejects foreign widget',
	);
};

# -----------------------------------------------------------------------------
# Focus events.
# -----------------------------------------------------------------------------

subtest 'set_focused_widget fires OnFocus / OnBlur on edge transitions' => sub {
	my $a  = TestInput->new(id => 'a');
	my $b  = TestInput->new(id => 'b');
	my $ui = make_ui($a, $b);

	my @log;
	$a->on('OnFocus', sub ($e) { push @log, 'a:focus' });
	$a->on('OnBlur',  sub ($e) { push @log, 'a:blur' });
	$b->on('OnFocus', sub ($e) { push @log, 'b:focus' });
	$b->on('OnBlur',  sub ($e) { push @log, 'b:blur' });

	$ui->set_focused_widget($a);
	is(\@log, ['a:focus'], 'OnFocus fires on initial focus');
	is($a->is_focused, 1, 'a->is_focused now true');

	@log = ();
	$ui->set_focused_widget($b);
	is(\@log, ['a:blur', 'b:focus'], 'blur previous then focus new');
	is($a->is_focused, 0, 'a no longer focused');
	is($b->is_focused, 1, 'b now focused');

	@log = ();
	$ui->set_focused_widget(undef);
	is(\@log, ['b:blur'], 'undef blurs without refiring OnFocus');
	is($b->is_focused, 0, 'b blurred');
	is($ui->get_focused_widget, undef, 'controller cleared');
};

subtest 'setting focus to the already-focused widget is a no-op' => sub {
	my $a  = TestInput->new(id => 'a');
	my $ui = make_ui($a);

	my @log;
	$a->on('OnFocus', sub ($e) { push @log, 'focus' });
	$a->on('OnBlur',  sub ($e) { push @log, 'blur' });

	$ui->set_focused_widget($a);
	$ui->set_focused_widget($a);   # idempotent
	is(\@log, ['focus'], 'no refire on same target');
};

subtest 'setting focus to undef when already unfocused is a no-op' => sub {
	my $a  = TestInput->new(id => 'a');
	my $ui = make_ui($a);

	my @log;
	$a->on('OnBlur', sub ($e) { push @log, 'blur' });

	$ui->set_focused_widget(undef);
	is(\@log, [], 'no events when blurring with no current focus');
};

# -----------------------------------------------------------------------------
# Default focus order: depth-first pre-order, skipping non-focusable.
# -----------------------------------------------------------------------------

subtest 'focus_next from undef focuses the first Focusable' => sub {
	my $a  = TestInput->new(id => 'a');
	my $b  = TestInput->new(id => 'b');
	my $c  = TestInput->new(id => 'c');
	my $ui = make_ui($a, $b, $c);

	$ui->focus_next;
	same($ui->get_focused_widget, $a, 'focus lands on first widget');
};

subtest 'focus_next traverses pre-order and wraps around' => sub {
	my $a  = TestInput->new(id => 'a');
	my $b  = TestInput->new(id => 'b');
	my $c  = TestInput->new(id => 'c');
	my $ui = make_ui($a, $b, $c);

	$ui->set_focused_widget($a);
	$ui->focus_next;
	same($ui->get_focused_widget, $b, 'a -> b');
	$ui->focus_next;
	same($ui->get_focused_widget, $c, 'b -> c');
	$ui->focus_next;
	same($ui->get_focused_widget, $a, 'c wraps to a');
};

subtest 'focus_previous wraps from first to last' => sub {
	my $a  = TestInput->new(id => 'a');
	my $b  = TestInput->new(id => 'b');
	my $c  = TestInput->new(id => 'c');
	my $ui = make_ui($a, $b, $c);

	$ui->set_focused_widget($a);
	$ui->focus_previous;
	same($ui->get_focused_widget, $c, 'a -> c (wrap)');
	$ui->focus_previous;
	same($ui->get_focused_widget, $b, 'c -> b');
};

subtest 'focus_previous from undef focuses the last Focusable' => sub {
	my $a  = TestInput->new(id => 'a');
	my $b  = TestInput->new(id => 'b');
	my $ui = make_ui($a, $b);
	$ui->focus_previous;
	same($ui->get_focused_widget, $b, 'previous from undef -> last');
};

subtest 'widgets with can_focus == 0 are skipped' => sub {
	my $a  = TestInput->new(id => 'a');
	my $x  = TestInput->new(id => 'x', disabled => 1);
	my $b  = TestInput->new(id => 'b');
	my $ui = make_ui($a, $x, $b);

	$ui->set_focused_widget($a);
	$ui->focus_next;
	same($ui->get_focused_widget, $b, 'disabled widget skipped in default chain');
};

subtest 'default order is depth-first (children before next sibling)' => sub {
	my $deep = TestInput->new(id => 'deep');
	my $a    = Clay::UI::Box->new(id => 'a', children => [$deep]);
	my $b    = TestInput->new(id => 'b');
	my $root = Clay::UI::Box->new(id => 'root', children => [$a, $b]);
	my $ui   = Clay::UI->new(root => $root, width => 100, height => 100);

	$ui->focus_next;
	same($ui->get_focused_widget, $deep, 'descended into first child first');
	$ui->focus_next;
	same($ui->get_focused_widget, $b, 'then on to sibling');
};

# -----------------------------------------------------------------------------
# HasFocusOrder override.
# -----------------------------------------------------------------------------

subtest 'HasFocusOrder takes over when ancestor of focused widget' => sub {
	my $a       = TestInput->new(id => 'a');
	my $b       = TestInput->new(id => 'b');
	my $target  = TestInput->new(id => 'target');
	# Container's subtree contains $a; the override always jumps to $target first.
	my $override = TestOverride->new(id => 'ov', target => $target, children => [$a]);
	my $root    = Clay::UI::Box->new(id => 'root', children => [$override, $b, $target]);
	my $ui      = Clay::UI->new(root => $root, width => 100, height => 100);

	# Focus $a (inside the override subtree)
	$ui->set_focused_widget($a);
	$ui->focus_next;
	same($ui->get_focused_widget, $target, 'override redirected to target');
};

subtest 'default_next_focus helper returns what default order would say' => sub {
	my $a       = TestInput->new(id => 'a');
	my $b       = TestInput->new(id => 'b');
	my $target  = TestInput->new(id => 'target');
	my $override = TestOverride->new(id => 'ov', target => $target, children => [$a]);
	my $root    = Clay::UI::Box->new(id => 'root', children => [$override, $b, $target]);
	my $ui      = Clay::UI->new(root => $root, width => 100, height => 100);

	# Focus $target so the override decides to defer to default_next_focus.
	# But $target is outside override's subtree - to trigger override, focus
	# must be on a widget under the override OR be the override itself.
	# Direct test: focus $a, call focus_next twice - first goes to $target,
	# then since focus is at $target (outside override) the override no longer
	# applies and default order kicks in.
	$ui->set_focused_widget($a);
	$ui->focus_next;
	same($ui->get_focused_widget, $target, 'first jump to target via override');
	$ui->focus_next;
	# Now focused is $target which is NOT under $override; default order
	# from $target wraps to first focusable in tree which is $a.
	same($ui->get_focused_widget, $a, 'default order takes over once focus leaves override subtree');
};

# -----------------------------------------------------------------------------
# is_focused tracks transitions.
# -----------------------------------------------------------------------------

subtest 'is_focused tracks focus / blur transitions' => sub {
	my $a  = TestInput->new(id => 'a');
	my $b  = TestInput->new(id => 'b');
	my $ui = make_ui($a, $b);

	is($a->is_focused, 0, 'before: a not focused');
	$ui->set_focused_widget($a);
	is($a->is_focused, 1, 'after focus(a): a focused');
	$ui->set_focused_widget($b);
	is($a->is_focused, 0, 'after focus(b): a no longer focused');
	is($b->is_focused, 1, 'after focus(b): b focused');
};

done_testing;
