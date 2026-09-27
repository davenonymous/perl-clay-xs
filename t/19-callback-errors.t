use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Test2::V0;
use Scalar::Util ();

use Clay::XS qw(:all);

# -----------------------------------------------------------------------------
# Callbacks are stored by value and validated at install time. An exception
# thrown by a callback while Clay runs is re-thrown by the Clay::XS call
# that invoked Clay, once Clay has returned.
# -----------------------------------------------------------------------------

sub fresh_context (%args) {
	my $ctx = Clay_Initialize(Clay_MinMemorySize(), { width => 300, height => 100 },
		$args{error_handler}, $args{error_userdata});
	Clay_SetMeasureTextFunction($args{measure} // sub ($text, $config, $userdata) {
		return { width => length($text), height => 10 };
	});
	return $ctx;
}

sub box ($name, %decl) {
	Clay__OpenElementWithId(Clay_GetElementId($name));
	Clay__ConfigureOpenElement({
		layout => { sizing => { width => sizing_fixed(100), height => sizing_fixed(100) } },
		%decl,
	});
}

subtest 'hover callbacks are stored by value' => sub {
	my $ctx = fresh_context();
	my @fired;
	my $build = sub {
		my $handler;
		Clay_BeginLayout();
		for my $name (qw(first second third)) {
			box($name);
			$handler = sub { push @fired, $name };
			Clay_OnHover($handler);
			Clay__CloseElement();
		}
		Clay_EndLayout();
	};
	$build->();
	Clay_SetPointerState([10, 10], 0);
	is( \@fired, ['first'], 'a reused variable still dispatches to the handler of each element' );
};

subtest 'reassigning the caller variables after install has no effect' => sub {
	my $seen;
	my $payload = 'original';
	my $measure = sub ($text, $config, $userdata) { $seen = $userdata; return { width => 1, height => 1 } };
	my $ctx = fresh_context(measure => $measure);
	Clay_SetMeasureTextFunction($measure, $payload);
	$payload = 'mutated-after-install';
	$measure = undef;
	Clay_BeginLayout();
	Clay__OpenTextElement('a', {});
	Clay_EndLayout();
	is( $seen, 'original', 'callback and userdata are private copies' );
};

subtest 'callbacks must be CODE references' => sub {
	my $ctx = fresh_context();
	like( dies { Clay_SetMeasureTextFunction('x') }, qr/expected a CODE reference or undef, got 'x'/,
		'measure function' );
	like( dies { Clay_SetTransitionHandlers(undef, 'x') }, qr/setInitialState: expected a CODE reference/,
		'transition handler' );
	like( dies { Clay_SetQueryScrollOffsetFunction([]) }, qr/expected a CODE reference or undef, got a ARRAY/,
		'query scroll offset function' );
	Clay_BeginLayout();
	box('hoverable');
	like( dies { Clay_OnHover('x') }, qr/Clay_OnHover: callback: expected a CODE reference, got 'x'/,
		'hover callback' );
	like( dies { Clay_OnHover(undef) }, qr/expected a CODE reference, got undef/, 'undef hover callback' );
	Clay__CloseElement();
	Clay_EndLayout();
};

subtest 'a dying error handler propagates out of Clay_EndLayout' => sub {
	my @args;
	my $ctx = fresh_context(
		error_handler  => sub ($error, $userdata) { push @args, [ $error, $userdata ]; die "Clay error: $error->{errorText}\n" },
		error_userdata => 'handler-payload',
	);
	Clay_BeginLayout();
	for (1 .. 2) { box('dup'); Clay__CloseElement() }
	like( dies { Clay_EndLayout() }, qr/^Clay error: An element with this ID was already previously declared/,
		'the handler exception is re-thrown' );
	is( $args[0][0]{errorType}, CLAY_ERROR_TYPE_DUPLICATE_ID, 'handler receives errorType' );
	is( $args[0][1], 'handler-payload', 'handler receives its userdata' );

	Clay_BeginLayout();
	box('single');
	Clay__CloseElement();
	ok( lives { Clay_EndLayout() }, 'the next frame is clean' );
};

subtest 'a bad transition handler result croaks from Clay_EndLayout' => sub {
	my $ctx = fresh_context();
	Clay_SetTransitionHandlers(sub ($args, $userdata) {
		$args->{current} = { boundingBox => [1, 2, 3, 4] };
		return 0;
	});
	my $frame = sub ($colour) {
		Clay_BeginLayout();
		box('fading', backgroundColor => $colour,
			transition => { duration => 1, properties => CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR });
		Clay__CloseElement();
		return Clay_EndLayout(0.1);
	};
	$frame->([255, 0, 0, 255]);
	like( dies { $frame->([0, 0, 255, 255]) },
		qr/transition handler args\.current\.boundingBox: expected a hash reference, got a ARRAY reference/,
		'the malformed result is reported' );
	Clay_SetTransitionHandlers();
};

subtest 'a dying hover callback propagates out of Clay_SetPointerState' => sub {
	my $ctx = fresh_context();
	Clay_BeginLayout();
	box('trap');
	Clay_OnHover(sub { die "hover exploded\n" });
	Clay__CloseElement();
	Clay_EndLayout();
	like( dies { Clay_SetPointerState([10, 10], 0) }, qr/^hover exploded$/, 'hover exception re-thrown' );
};

subtest 'a failing measurer is called once per frame' => sub {
	my $calls = 0;
	my $ctx = fresh_context(measure => sub { $calls++; die "no font\n" });
	Clay_BeginLayout();
	Clay__OpenTextElement("many words in this text $_", {}) for 1 .. 20;
	like( dies { Clay_EndLayout() }, qr/^no font$/, 'one exception for the frame' );
	is( $calls, 1, 'the measurer ran once' );
};

subtest 'later callback errors of the same call are counted' => sub {
	my $ctx = fresh_context();
	Clay_BeginLayout();
	box('outer');
	Clay_OnHover(sub { die "outer hover\n" });
	box('inner');
	Clay_OnHover(sub { die "inner hover\n" });
	Clay__CloseElement();
	Clay__CloseElement();
	Clay_EndLayout();
	like( dies { Clay_SetPointerState([10, 10], 0) },
		qr/^outer hover \(and 1 more callback error this frame\)$/, 'first error re-thrown, second counted' );
};

subtest 'a context without a measure function reports measured text' => sub {
	my $a = fresh_context();
	my $b = Clay_Initialize(Clay_MinMemorySize(), { width => 100, height => 100 });
	Clay_BeginLayout();
	Clay__OpenTextElement('hello', {});
	like( dies { Clay_EndLayout() },
		qr/text measured but no measure_text function is installed for this context/,
		'second context without a measurer croaks' );
};

subtest 'an error left by an abandoned frame is raised by the next Clay_BeginLayout' => sub {
	my $ctx = fresh_context(measure => sub { die "measure failed\n" });
	Clay_BeginLayout();
	Clay__OpenTextElement('abandoned', {});
	like( dies { Clay_BeginLayout() }, qr/^measure failed \(from the previous unfinished frame\)$/,
		'the leftover error names its origin' );
	Clay_SetMeasureTextFunction(sub { return { width => 1, height => 1 } });
	Clay_BeginLayout();
	Clay__OpenTextElement('fine', {});
	ok( lives { Clay_EndLayout() }, 'the following frame works' );
};

# -----------------------------------------------------------------------------
# A callback runs in the middle of a Clay function: it cannot free the
# context Clay is using, and calls that change Clay's state croak (the croak
# is re-thrown by the call that invoked Clay).
# -----------------------------------------------------------------------------

sub text_frame ($text = 'hello') {
	Clay_BeginLayout();
	Clay__OpenTextElement($text, {});
	return Clay_EndLayout();
}

subtest 'a callback dropping the last reference does not free the running context' => sub {
	my $ctx = fresh_context();
	Clay_BeginLayout();
	box('drop');
	Clay_OnHover(sub { undef $ctx });
	Clay__CloseElement();
	Clay_EndLayout();
	ok( lives { Clay_SetPointerState([10, 10], 0) }, 'Clay_SetPointerState completes' );
	is( $ctx, undef, 'the callback dropped the reference' );
	like( dies { Clay_BeginLayout() }, qr/no current Clay context/, 'the context is freed afterwards' );

	my $measured;
	$measured = fresh_context(measure => sub ($text, $config, $userdata) {
		undef $measured;
		return { width => 1, height => 1 };
	});
	Clay_BeginLayout();
	ok( lives { Clay__OpenTextElement('hello', {}) }, 'the call that ran the dropping measurer completes' );
	like( dies { Clay_EndLayout() }, qr/no current Clay context/, 'and that context is freed afterwards' );
};

subtest 'a callback cannot destroy the running context explicitly' => sub {
	my $ctx;
	$ctx = fresh_context(measure => sub ($text, $config, $userdata) {
		$ctx->DESTROY;
		return { width => 1, height => 1 };
	});
	like( dies { text_frame() }, qr/DESTROY: cannot be called from inside a Clay callback/,
		'explicit DESTROY croaks' );
	ok( Clay_GetCurrentContext(), 'the context is still alive' );
};

subtest 'calls that change Clay state croak inside callbacks' => sub {
	my %calls = (
		Clay_BeginLayout       => sub { Clay_BeginLayout() },
		Clay_EndLayout         => sub { Clay_EndLayout() },
		Clay_Initialize        => sub { my $other = Clay_Initialize(Clay_MinMemorySize(), [10, 10]) },
		Clay_SetCurrentContext => sub { Clay_SetCurrentContext(Clay_GetCurrentContext()) },
		Clay__OpenElement      => sub { Clay__OpenElement() },
		Clay_SetPointerState   => sub { Clay_SetPointerState([0, 0], 0) },
		Clay_ResetMeasureTextCache => sub { Clay_ResetMeasureTextCache() },
	);
	for my $name (sort keys %calls) {
		my $ctx = fresh_context(measure => sub ($text, $config, $userdata) {
			$calls{$name}->();
			return { width => 1, height => 1 };
		});
		like( dies { text_frame() }, qr/^\Q$name\E: cannot be called from inside a Clay callback/,
			"$name from a measure callback" );
		Clay_SetMeasureTextFunction(sub { return { width => 1, height => 1 } });
		ok( lives { text_frame() }, "the next frame after $name works" );
	}

	my $ctx = fresh_context();
	Clay_SetTransitionHandlers(sub ($args, $userdata) { Clay_BeginLayout(); return 1 });
	my $frame = sub ($colour) {
		Clay_BeginLayout();
		box('fading', backgroundColor => $colour,
			transition => { duration => 1, properties => CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR });
		Clay__CloseElement();
		return Clay_EndLayout(0.016);
	};
	$frame->([255, 0, 0, 255]);
	like( dies { $frame->([0, 0, 255, 255]) }, qr/^Clay_BeginLayout: cannot be called from inside a Clay callback/,
		'Clay_BeginLayout from a transition handler' );
	Clay_SetTransitionHandlers(sub ($args, $userdata) { my $other = Clay_Initialize(Clay_MinMemorySize(), [10, 10]); return 1 });
	like( dies { $frame->([0, 255, 0, 255]) }, qr/^Clay_Initialize: cannot be called from inside a Clay callback/,
		'Clay_Initialize from a transition handler' );
	Clay_SetTransitionHandlers();
	ok( lives { $frame->([0, 255, 0, 255]) }, 'the next frame works' );
};

subtest 'read-only queries work inside callbacks' => sub {
	my @seen;
	my $ctx = fresh_context(measure => sub ($text, $config, $userdata) {
		push @seen, Clay_GetLayoutDimensions()->{width}, scalar @{ Clay_GetPointerOverIds() };
		return { width => 1, height => 1 };
	});
	ok( lives { text_frame() }, 'the frame completes' );
	is( [ @seen[0, 1] ], [ 300, 0 ], 'the queries returned the context state' );
};

subtest 'an exception object with a dying bool overload is re-thrown as is' => sub {
	package My::Exception { use overload 'bool' => sub { die "bool called\n" }, fallback => 1 }
	my $exception = bless {}, 'My::Exception';
	my $ctx = fresh_context(measure => sub { die $exception });
	# Test2's dies() truth-tests the exception, so use a plain eval.
	my $ok    = eval { text_frame(); 1 };
	my $error = $@;
	ok( !defined $ok, 'the frame dies' );
	is( Scalar::Util::refaddr($error), Scalar::Util::refaddr($exception), 'with the same object' );
};

subtest 'Clay::XS::_dispatch cannot be called directly' => sub {
	like( dies { Clay::XS::_dispatch(1, 0, sub { [1, 2] }) }, qr/_dispatch is internal/, 'outside a callback' );
	my $inner;
	my $ctx = fresh_context(measure => sub ($text, $config, $userdata) {
		$inner = dies { Clay::XS::_dispatch(sub { [1, 2] }) };
		return { width => 1, height => 1 };
	});
	text_frame();
	like( $inner, qr/_dispatch is internal/, 'inside a callback' );
};

subtest 'the caller $@ survives callbacks' => sub {
	my $ctx = fresh_context();
	eval { die "outer error\n" };
	Clay_BeginLayout();
	Clay__OpenTextElement('measured', {});
	Clay_EndLayout();
	is( $@, "outer error\n", '$@ is unchanged' );
};

done_testing;
