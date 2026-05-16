use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;

use Clay::UI::Box;
use Clay::UI::Text;
use Clay::UI::Events qw(
	EVENT_HANDLED EVENT_CONTINUE
	BUBBLE_ALWAYS BUBBLE_IF_CONTINUE BUBBLE_NEVER
);
use Clay::UI::Events::Event;
use Clay::UI::Events::OnHoverStart;
use Clay::UI::Events::OnHoverStopped;
use Clay::UI::Events::OnPress;
use Clay::UI::Events::OnRelease;
use Clay::UI::Events::OnScroll;

# -----------------------------------------------------------------------------
# Constants are singleton objects and compare with ==.
# -----------------------------------------------------------------------------

subtest 'constants are singletons' => sub {
	ok( EVENT_HANDLED == EVENT_HANDLED,         'EVENT_HANDLED is a singleton' );
	ok( EVENT_CONTINUE == EVENT_CONTINUE,       'EVENT_CONTINUE is a singleton' );
	ok( EVENT_HANDLED != EVENT_CONTINUE,        'HANDLED and CONTINUE distinguishable' );
	ok( BUBBLE_ALWAYS != BUBBLE_NEVER,          'bubble singletons distinguishable' );
};

# -----------------------------------------------------------------------------
# Subclass event_name defaulting.
# -----------------------------------------------------------------------------

subtest 'event_name default propagates to name' => sub {
	is( Clay::UI::Events::OnHoverStart  ->new->name, 'OnHoverStart',  'OnHoverStart defaults name' );
	is( Clay::UI::Events::OnHoverStopped->new->name, 'OnHoverStopped','OnHoverStopped defaults name' );
	is( Clay::UI::Events::OnPress       ->new->name, 'OnPress',       'OnPress defaults name' );
	is( Clay::UI::Events::OnRelease     ->new->name, 'OnRelease',     'OnRelease defaults name' );
	is( Clay::UI::Events::OnScroll      ->new->name, 'OnScroll',      'OnScroll defaults name' );

	is(
		Clay::UI::Events::OnPress->new(name => 'Custom')->name,
		'Custom',
		'caller-provided name overrides default',
	);
};

# -----------------------------------------------------------------------------
# Basic handler registration + target / current_target.
# -----------------------------------------------------------------------------

subtest 'handler fires with target == current_target on the firer' => sub {
	my $box = Clay::UI::Box->new( id => 'b' );
	my @calls;
	$box->on('OnPress', sub ($e) {
		push @calls, { target => $e->target, current => $e->current_target };
	});

	$box->fire_event(Clay::UI::Events::OnPress->new(x => 5, y => 7));

	is( scalar(@calls), 1, 'handler invoked once' );
	is( $calls[0]{target},  $box, 'target is firer' );
	is( $calls[0]{current}, $box, 'current_target == target on no-bubble path' );
};

# -----------------------------------------------------------------------------
# Bubble: ALWAYS walks every ancestor regardless of return.
# -----------------------------------------------------------------------------

subtest 'BUBBLE_ALWAYS visits every ancestor' => sub {
	my $leaf  = Clay::UI::Box->new( id => 'leaf' );
	my $mid   = Clay::UI::Box->new( id => 'mid',  children => [ $leaf ] );
	my $root  = Clay::UI::Box->new( id => 'root', children => [ $mid  ] );

	my @hit_ids;
	$_->on('Ping', sub ($e) { push @hit_ids, $e->current_target->id; return EVENT_HANDLED })
		for $leaf, $mid, $root;

	$leaf->fire_event(
		Clay::UI::Events::Event->new(name => 'Ping', bubble_mode => BUBBLE_ALWAYS),
	);

	is( \@hit_ids, [ 'leaf', 'mid', 'root' ], 'all three handlers fired in bubble order' );
};

# -----------------------------------------------------------------------------
# Bubble: IF_CONTINUE stops on undef / EVENT_HANDLED.
# -----------------------------------------------------------------------------

subtest 'all handlers on the firing node fire even when one returns HANDLED' => sub {
	# Per-node, not per-handler: a sibling returning EVENT_HANDLED must
	# not skip later handlers at the SAME node. The stop decision applies
	# at the node boundary, after the handler list is exhausted.
	my $leaf = Clay::UI::Box->new( id => 'leaf' );
	my $root = Clay::UI::Box->new( id => 'root', children => [ $leaf ] );

	my @order;
	$leaf->on('Ping', sub ($e) { push @order, 'leaf-1'; return EVENT_CONTINUE });
	$leaf->on('Ping', sub ($e) { push @order, 'leaf-2'; return EVENT_HANDLED });
	$leaf->on('Ping', sub ($e) { push @order, 'leaf-3'; return EVENT_CONTINUE });
	$root->on('Ping', sub ($e) { push @order, 'root'   });

	$leaf->fire_event(
		Clay::UI::Events::Event->new(name => 'Ping', bubble_mode => BUBBLE_IF_CONTINUE),
	);

	is(
		\@order,
		[ 'leaf-1', 'leaf-2', 'leaf-3' ],
		'all three leaf handlers ran in order; bubble stopped before root',
	);
};

subtest 'BUBBLE_IF_CONTINUE stops on EVENT_HANDLED' => sub {
	my $leaf  = Clay::UI::Box->new( id => 'leaf' );
	my $mid   = Clay::UI::Box->new( id => 'mid',  children => [ $leaf ] );
	my $root  = Clay::UI::Box->new( id => 'root', children => [ $mid  ] );

	my @hit_ids;
	$leaf->on('Ping', sub ($e) { push @hit_ids, 'leaf'; return EVENT_CONTINUE });
	$mid ->on('Ping', sub ($e) { push @hit_ids, 'mid';  return EVENT_HANDLED });
	$root->on('Ping', sub ($e) { push @hit_ids, 'root'; return EVENT_CONTINUE });

	$leaf->fire_event(
		Clay::UI::Events::Event->new(name => 'Ping', bubble_mode => BUBBLE_IF_CONTINUE),
	);

	is( \@hit_ids, [ 'leaf', 'mid' ], 'bubble stops once mid returns EVENT_HANDLED' );
};

subtest 'BUBBLE_IF_CONTINUE: undef return halts as EVENT_HANDLED' => sub {
	my $leaf = Clay::UI::Box->new( id => 'leaf' );
	my $root = Clay::UI::Box->new( id => 'root', children => [ $leaf ] );

	my @hits;
	$leaf->on('Ping', sub ($e) { push @hits, 'leaf'; return });  # undef
	$root->on('Ping', sub ($e) { push @hits, 'root' });

	$leaf->fire_event(Clay::UI::Events::Event->new(name => 'Ping'));  # default IF_CONTINUE

	is( \@hits, [ 'leaf' ], 'undef return halts bubbling' );
};

# -----------------------------------------------------------------------------
# Bubble: NEVER never reaches ancestors.
# -----------------------------------------------------------------------------

subtest 'BUBBLE_NEVER stays on firer' => sub {
	my $leaf = Clay::UI::Box->new( id => 'leaf' );
	my $root = Clay::UI::Box->new( id => 'root', children => [ $leaf ] );

	my @hits;
	$leaf->on('Ping', sub ($e) { push @hits, 'leaf'; return EVENT_CONTINUE });
	$root->on('Ping', sub ($e) { push @hits, 'root' });

	$leaf->fire_event(
		Clay::UI::Events::Event->new(name => 'Ping', bubble_mode => BUBBLE_NEVER),
	);

	is( \@hits, [ 'leaf' ], 'ancestor handler never fired' );
};

# -----------------------------------------------------------------------------
# current_target tracks bubble cursor; target stays the firer.
# -----------------------------------------------------------------------------

subtest 'current_target updates per hop; target is immutable' => sub {
	my $leaf = Clay::UI::Box->new( id => 'leaf' );
	my $root = Clay::UI::Box->new( id => 'root', children => [ $leaf ] );

	my @observations;
	$leaf->on('Ping', sub ($e) {
		push @observations, [ $e->target->id, $e->current_target->id ];
		return EVENT_CONTINUE;
	});
	$root->on('Ping', sub ($e) {
		push @observations, [ $e->target->id, $e->current_target->id ];
		return EVENT_CONTINUE;
	});

	$leaf->fire_event(
		Clay::UI::Events::Event->new(name => 'Ping', bubble_mode => BUBBLE_ALWAYS),
	);

	is( \@observations, [ [ 'leaf', 'leaf' ], [ 'leaf', 'root' ] ],
	    'target stays at firer; current_target follows bubble cursor' );
};

# -----------------------------------------------------------------------------
# Re-firing the same event object is forbidden.
# -----------------------------------------------------------------------------

subtest 'event objects are single-use' => sub {
	my $box = Clay::UI::Box->new;
	my $event = Clay::UI::Events::OnPress->new;

	$box->fire_event($event);

	like(
		dies { $box->fire_event($event) },
		qr/already dispatched/,
		're-firing the same event dies',
	);
};

# -----------------------------------------------------------------------------
# Multiple handlers on the same name fire in registration order.
# -----------------------------------------------------------------------------

subtest 'multiple handlers fire in registration order' => sub {
	my $box = Clay::UI::Box->new;
	my @order;
	$box->on('Ping', sub { push @order, 'first' });
	$box->on('Ping', sub { push @order, 'second' });
	$box->on('Ping', sub { push @order, 'third' });

	$box->fire_event(Clay::UI::Events::Event->new(name => 'Ping'));

	is( \@order, [ 'first', 'second', 'third' ], 'registration order preserved' );
};

# -----------------------------------------------------------------------------
# Validation: bad inputs fail loud.
# -----------------------------------------------------------------------------

subtest 'on() rejects bad inputs' => sub {
	my $box = Clay::UI::Box->new;
	like( dies { $box->on('', sub { }) },        qr/non-empty string/, 'empty event name' );
	like( dies { $box->on('X', 'nope') },        qr/coderef/,          'non-coderef handler' );
};

subtest 'fire_event() rejects non-event arg' => sub {
	my $box = Clay::UI::Box->new;
	like( dies { $box->fire_event("not an event") }, qr/Clay::UI::Events::Event/,
	      'fire_event rejects non-event' );
};

# -----------------------------------------------------------------------------
# TextNode widgets also get on()/fire_event() through the same role.
# -----------------------------------------------------------------------------

subtest 'Listener/Emitter split: Text listens, Box emits' => sub {
	# Listener half is composed into every widget (Text included);
	# Emitter half is composed only into widgets that originate events
	# (Box, Button). A Box firing an event bubbling up the tree reaches
	# Text listeners on its ancestors - but a Text leaf cannot fire one.
	my $inner = Clay::UI::Box->new(id => 'inner');
	my $outer = Clay::UI::Box->new(id => 'outer', children => [ $inner ]);
	my $text  = Clay::UI::Text->new(text => 'hi');

	ok( $inner->can('fire_event'), 'Box exposes fire_event' );
	ok(!$text->can('fire_event'),  'Text does NOT expose fire_event' );
	ok( $text->can('on'),          'Text exposes on() (Listener half)' );

	my @hits;
	$outer->on('Ping', sub ($e) { push @hits, 'outer' });
	$inner->fire_event(
		Clay::UI::Events::Event->new(name => 'Ping', bubble_mode => BUBBLE_ALWAYS),
	);
	is( \@hits, [ 'outer' ], 'event from inner Box reached listener on outer Box' );
};

done_testing;
