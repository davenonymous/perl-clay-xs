package Clay::XS;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Exporter 5.57 'import';
use XSLoader;

our $VERSION = '0.02';

XSLoader::load(__PACKAGE__, $VERSION);

# -----------------------------------------------------------------------------
# Re-export every Clay_* / Clay__* / sizing_* / padding_* / border_* /
# corner_radius_* / Clay_Set* / check_struct helper as its bare name,
# plus the constants the BOOT block installed.
#
# The export tag :all gives a caller a flat namespace identical to the
# C header. Most users will want this. Use individual imports if you
# need finer control.
# -----------------------------------------------------------------------------

our @EXPORT_OK = qw(
    Clay_MinMemorySize
    Clay_Initialize
    Clay_GetCurrentContext
    Clay_SetCurrentContext
    Clay_SetLayoutDimensions
    Clay_GetLayoutDimensions
    Clay_BeginLayout
    Clay_EndLayout

    Clay__OpenElement
    Clay__OpenElementWithId
    Clay__CloseElement
    Clay__ConfigureOpenElement
    Clay__OpenTextElement
    Clay__HashString
    Clay__HashStringWithOffset

    Clay_GetOpenElementId
    Clay_GetElementId
    Clay_GetElementIdWithIndex
    Clay_GetElementData

    Clay_SetMeasureTextFunction
    Clay_ResetMeasureTextCache

    Clay_SetPointerState
    Clay_GetPointerState
    Clay_Hovered
    Clay_OnHover
    Clay_PointerOver
    Clay_GetPointerOverIds

    Clay_UpdateScrollContainers
    Clay_GetScrollOffset
    Clay_GetScrollContainerData
    Clay_SetQueryScrollOffsetFunction
    Clay_SetExternalScrollHandlingEnabled

    Clay_SetDebugModeEnabled
    Clay_IsDebugModeEnabled
    Clay_SetCullingEnabled
    Clay_GetMaxElementCount
    Clay_SetMaxElementCount
    Clay_GetMaxMeasureTextCacheWordCount
    Clay_SetMaxMeasureTextCacheWordCount
    Clay_EaseOut
    Clay_SetTransitionHandlers

    sizing_fit sizing_grow sizing_fixed sizing_percent
    padding_all border_all border_outside corner_radius_all
    set_scroll_position
    check_struct

    CLAY_LEFT_TO_RIGHT CLAY_TOP_TO_BOTTOM
    CLAY_ALIGN_X_LEFT CLAY_ALIGN_X_RIGHT CLAY_ALIGN_X_CENTER
    CLAY_ALIGN_Y_TOP CLAY_ALIGN_Y_BOTTOM CLAY_ALIGN_Y_CENTER
    CLAY__SIZING_TYPE_FIT CLAY__SIZING_TYPE_GROW
    CLAY__SIZING_TYPE_PERCENT CLAY__SIZING_TYPE_FIXED
    CLAY_TEXT_WRAP_WORDS CLAY_TEXT_WRAP_NEWLINES CLAY_TEXT_WRAP_NONE
    CLAY_TEXT_ALIGN_LEFT CLAY_TEXT_ALIGN_CENTER CLAY_TEXT_ALIGN_RIGHT
    CLAY_ATTACH_POINT_LEFT_TOP CLAY_ATTACH_POINT_LEFT_CENTER
    CLAY_ATTACH_POINT_LEFT_BOTTOM CLAY_ATTACH_POINT_CENTER_TOP
    CLAY_ATTACH_POINT_CENTER_CENTER CLAY_ATTACH_POINT_CENTER_BOTTOM
    CLAY_ATTACH_POINT_RIGHT_TOP CLAY_ATTACH_POINT_RIGHT_CENTER
    CLAY_ATTACH_POINT_RIGHT_BOTTOM
    CLAY_POINTER_CAPTURE_MODE_CAPTURE CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH
    CLAY_ATTACH_TO_NONE CLAY_ATTACH_TO_PARENT
    CLAY_ATTACH_TO_ELEMENT_WITH_ID CLAY_ATTACH_TO_ROOT
    CLAY_CLIP_TO_NONE CLAY_CLIP_TO_ATTACHED_PARENT
    CLAY_RENDER_COMMAND_TYPE_NONE CLAY_RENDER_COMMAND_TYPE_RECTANGLE
    CLAY_RENDER_COMMAND_TYPE_BORDER CLAY_RENDER_COMMAND_TYPE_TEXT
    CLAY_RENDER_COMMAND_TYPE_IMAGE
    CLAY_RENDER_COMMAND_TYPE_SCISSOR_START CLAY_RENDER_COMMAND_TYPE_SCISSOR_END
    CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_START
    CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_END
    CLAY_RENDER_COMMAND_TYPE_CUSTOM
    CLAY_POINTER_DATA_PRESSED_THIS_FRAME CLAY_POINTER_DATA_PRESSED
    CLAY_POINTER_DATA_RELEASED_THIS_FRAME CLAY_POINTER_DATA_RELEASED
    CLAY_TRANSITION_STATE_IDLE CLAY_TRANSITION_STATE_ENTERING
    CLAY_TRANSITION_STATE_TRANSITIONING CLAY_TRANSITION_STATE_EXITING
    CLAY_TRANSITION_PROPERTY_NONE CLAY_TRANSITION_PROPERTY_X
    CLAY_TRANSITION_PROPERTY_Y CLAY_TRANSITION_PROPERTY_POSITION
    CLAY_TRANSITION_PROPERTY_WIDTH CLAY_TRANSITION_PROPERTY_HEIGHT
    CLAY_TRANSITION_PROPERTY_DIMENSIONS CLAY_TRANSITION_PROPERTY_BOUNDING_BOX
    CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR
    CLAY_TRANSITION_PROPERTY_OVERLAY_COLOR
    CLAY_TRANSITION_PROPERTY_CORNER_RADIUS
    CLAY_TRANSITION_PROPERTY_BORDER_COLOR
    CLAY_TRANSITION_PROPERTY_BORDER_WIDTH
    CLAY_TRANSITION_PROPERTY_BORDER
    CLAY_TRANSITION_ENTER_SKIP_ON_FIRST_PARENT_FRAME
    CLAY_TRANSITION_ENTER_TRIGGER_ON_FIRST_PARENT_FRAME
    CLAY_TRANSITION_EXIT_SKIP_WHEN_PARENT_EXITS
    CLAY_TRANSITION_EXIT_TRIGGER_WHEN_PARENT_EXITS
    CLAY_TRANSITION_DISABLE_INTERACTIONS_WHILE_TRANSITIONING_POSITION
    CLAY_TRANSITION_ALLOW_INTERACTIONS_WHILE_TRANSITIONING_POSITION
    CLAY_EXIT_TRANSITION_ORDERING_UNDERNEATH_SIBLINGS
    CLAY_EXIT_TRANSITION_ORDERING_NATURAL_ORDER
    CLAY_EXIT_TRANSITION_ORDERING_ABOVE_SIBLINGS
    CLAY_ERROR_TYPE_TEXT_MEASUREMENT_FUNCTION_NOT_PROVIDED
    CLAY_ERROR_TYPE_ARENA_CAPACITY_EXCEEDED
    CLAY_ERROR_TYPE_ELEMENTS_CAPACITY_EXCEEDED
    CLAY_ERROR_TYPE_TEXT_MEASUREMENT_CAPACITY_EXCEEDED
    CLAY_ERROR_TYPE_DUPLICATE_ID
    CLAY_ERROR_TYPE_FLOATING_CONTAINER_PARENT_NOT_FOUND
    CLAY_ERROR_TYPE_PERCENTAGE_OVER_1
    CLAY_ERROR_TYPE_INTERNAL_ERROR
    CLAY_ERROR_TYPE_UNBALANCED_OPEN_CLOSE
    CLAY_ERROR_TYPE_HASH_MAP_CAPACITY_EXCEEDED
    CLAY_ERROR_TYPE_SIZING_GROUP_CYCLE
);

our %EXPORT_TAGS = (
    all => [ @EXPORT_OK ],
);

# A context belongs to the interpreter that created it. Threads must not
# inherit a copy: its DESTROY would free the parent's context.
package Clay::XS::Context {
    sub CLONE_SKIP { 1 }
}

# What src/marshal.c croaks for a struct value it cannot use. Always true,
# so `$@ || ...` keeps it; stringifies like a plain croak message.
package Clay::XS::StructError {
    use overload '""' => \&as_string, bool => sub { 1 }, fallback => 1;

    sub path         ($self) { $self->{path} }
    sub expected     ($self) { $self->{expected} }
    sub got          ($self) { $self->{got} }
    sub hint         ($self) { $self->{hint} }
    sub unknown_keys ($self) { $self->{unknown_keys} }
    sub known_keys   ($self) { $self->{known_keys} }
    sub file         ($self) { $self->{file} }
    sub line         ($self) { $self->{line} }

    sub message ($self) {
        my $message = join('.', @{ $self->{path} }) . ": expected $self->{expected}, got $self->{got}";
        $message .= " ($self->{hint})" if defined $self->{hint};
        return $message;
    }

    sub as_string ($self, @) {
        return $self->message . " at $self->{file} line $self->{line}.\n";
    }
}

1;

__END__

=pod

=head1 NAME

Clay::XS - Perl XS bindings for the Clay (C Layout) UI library

=head1 SYNOPSIS

    use Clay::XS qw(:all);

    my $ctx = Clay_Initialize(
        Clay_MinMemorySize(),
        { width => 800, height => 600 },
        sub ($err, $userdata) { die "Clay error: $err->{errorText}\n" },
    );

    Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
        return { width => length($text) * $config->{fontSize}, height => $config->{fontSize} };
    });

    Clay_BeginLayout();

    Clay__OpenElementWithId(Clay_GetElementId("root"));
    Clay__ConfigureOpenElement({
        layout => {
            sizing  => { width => sizing_grow(), height => sizing_grow() },
            padding => padding_all(16),
        },
        backgroundColor => [240, 240, 240, 255],
    });
    Clay__OpenTextElement("Hello", { fontSize => 16, textColor => [0, 0, 0, 255] });
    Clay__CloseElement();

    my $commands = Clay_EndLayout();
    for my $cmd (@$commands) {
        # render $cmd according to $cmd->{commandType} ...
    }

=head1 DESCRIPTION

C<Clay::XS> is a thin, name-preserving XS binding to Clay v0.14
L<https://github.com/nicbarker/clay>, a header-only C UI layout library.
Every public C<Clay_*> function in F<clay.h> - plus
C<Clay_SetExternalScrollHandlingEnabled>, which upstream implements but
does not declare - and the internal C<Clay__*> functions the C macros
expand to are exposed under their exact C names. The one exception is
C<Clay_CreateArenaWithCapacityAndMemory>: C<Clay_Initialize> takes the
arena capacity in bytes and allocates and owns the arena itself. The macros (C<CLAY()>,
C<CLAY_TEXT()>, C<CLAY_ID()>, ...) are not bindable directly; see
L</MAPPING C MACROS TO PERL>.

Structs are plain Perl hashes whose keys are the exact C field names
(C<backgroundColor>, C<layoutDirection>, ...). The compact types
C<Clay_Color>, C<Clay_Vector2> and C<Clay_Dimensions> also accept
arrayrefs (C<[r, g, b, a]>, C<[x, y]>, C<[width, height]>). A missing or
undef field means the C zero value, exactly like a C designated
initialiser.

This module is the low-level surface. The higher-level, widget-based
layer is L<Clay::UI>, which ships in the same distribution.

=head1 MAPPING C MACROS TO PERL

The Clay C macros expand to combinations of internal functions. Here is
how to spell each one in Perl:

    CLAY_ID("foo")              ->  Clay_GetElementId("foo")
    CLAY_IDI("foo", 3)          ->  Clay_GetElementIdWithIndex("foo", 3)
    CLAY_ID_LOCAL("foo")        ->  Clay__HashString("foo", Clay_GetOpenElementId())
    CLAY_IDI_LOCAL("foo", 3)    ->  Clay__HashStringWithOffset("foo", 3, Clay_GetOpenElementId())
    CLAY_SIZING_FIT($min, $max) ->  sizing_fit($min, $max)
    CLAY_SIZING_GROW($min, $max)->  sizing_grow($min, $max)
    CLAY_SIZING_FIXED($size)    ->  sizing_fixed($size)
    CLAY_SIZING_PERCENT($pct)   ->  sizing_percent($pct)
    CLAY_PADDING_ALL($v)        ->  padding_all($v)
    CLAY_BORDER_ALL($v)         ->  border_all($v)
    CLAY_BORDER_OUTSIDE($v)     ->  border_outside($v)
    CLAY_CORNER_RADIUS($r)      ->  corner_radius_all($r)

    CLAY(id, { ... }) { ... }   ->
        Clay__OpenElementWithId($id);
        Clay__ConfigureOpenElement({ ... });
        # ... children declared here ...
        Clay__CloseElement();

    CLAY_AUTO_ID({ ... }) { ... } ->
        Clay__OpenElement();
        Clay__ConfigureOpenElement({ ... });
        # ... children ...
        Clay__CloseElement();

    CLAY_TEXT($text, { ... })   ->  Clay__OpenTextElement($text, { ... })

    Clay_GetScrollContainerData(id).scrollPosition->y = 40
                                ->  set_scroll_position($id, { x => 0, y => 40 })

In C, programmatic scrolling writes through the C<scrollPosition> pointer
returned by C<Clay_GetScrollContainerData>. C<set_scroll_position> does
that write; it croaks unless the id names a scroll container Clay knows
(one declared with C<clip> enabled in a completed frame).

The C<sizing_*> helpers accept C<max =E<gt> 0> (Clay's "no maximum") and
C<+Inf> as an unbounded maximum.

=head1 CONTEXTS

C<Clay_Initialize($capacity, $dimensions, $error_handler, $userdata)>
returns a C<Clay::XS::Context> object and makes it current. C<$capacity>
must be an integer of at least C<Clay_MinMemorySize()> bytes;
C<$error_handler> is undef or a CODE reference. Every other
Clay-touching function operates on the current context and croaks if
there is none. Switch contexts with C<Clay_SetCurrentContext($ctx)>;
C<Clay_GetCurrentContext()> returns the current context (another handle
to the same object) or undef.

The context is freed when the last reference to it goes away. Copies
made with L<Storable> and hand-blessed objects are not contexts and
croak when used.

Clay keeps one process-wide current context, so contexts belong to the
interpreter that created them: they are not copied into new threads,
and using an inherited current context from another thread croaks.

C<Clay_SetMaxElementCount> and C<Clay_SetMaxMeasureTextCacheWordCount>
take effect at the next C<Clay_Initialize>, which sizes the new context
for them (the word count must be at least 32). Calling a setter on a live
context is allowed, but every Clay-touching call on that context then
croaks until C<Clay_Initialize> has been called again - Clay's arrays
keep the sizes they were created with. Counts whose arena would exceed
4 GiB are rejected.

=head1 ELEMENTS AND FRAMES

A frame is C<Clay_BeginLayout()>, the element declarations, and
C<Clay_EndLayout($delta_time)>, which returns the render commands.
Element declarations are checked for balance:

=over 4

=item *

C<Clay__OpenElement>, C<Clay__OpenElementWithId> and
C<Clay__OpenTextElement> croak outside a frame.

=item *

C<Clay__CloseElement>, C<Clay__ConfigureOpenElement> and C<Clay_OnHover>
croak when no element is open.

=item *

C<Clay_EndLayout> croaks without a matching C<Clay_BeginLayout>. If
elements are still open (for example because an exception interrupted a
declaration), it closes them, lets Clay finish the frame, and croaks
C<N element(s) still open at Clay_EndLayout (unbalanced
Clay__OpenElement/Clay__CloseElement)>. The next frame works normally.

=back

Every struct field is parsed when it crosses into Clay: wrong reference
types (at any nesting level), non-numeric or non-finite numbers, and
integers outside the C field's range (for example negative padding or an
enum value Clay does not define) croak a L</STRUCT ERRORS> object naming
the struct and field, e.g. C<Clay_ElementDeclaration.layout.padding.left:
expected an integer in 0..65535, got '-8'>. Unknown keys are ignored, as
are extra array elements. C<floating =E<gt> { parentId =E<gt> ... }>
accepts a numeric id or an element-id hash from C<Clay_GetElementId>.

=head1 CHECKING STRUCTS

    check_struct('Clay_LayoutConfig', $layout);
    check_struct('Clay_Padding', $padding, 'layout.padding');

C<check_struct($type, $value, $root)> validates C<$value> as the struct
named by its exact C type (C<Clay_ElementDeclaration>,
C<Clay_LayoutConfig>, C<Clay_TextElementConfig>, C<Clay_Color>,
C<Clay_SizingAxis>, ...: every struct a function argument or a
declaration field takes) without a context or a frame. It returns
nothing and croaks a L</STRUCT ERRORS> object for the first problem; an
unknown type name croaks a plain string. The error path starts at
C<$root>, or at the type name when C<$root> is undef.

It applies the same rules as the parse that runs when the value crosses
into Clay, and is stricter in three ways: unknown keys croak (the error
lists the known ones), an arrayref must have exactly one element per
field (four for a colour), and a boolean field must not be a reference.
Shape errors of a few structs carry a hint, for example C<(padding_all(N)
builds one)>. An undef C<$value> is accepted: it means the zero struct.

=head1 STRUCT ERRORS

Struct values that cannot be used croak a C<Clay::XS::StructError>, both
when they cross into Clay and from L</CHECKING STRUCTS>. The object is true
in boolean context and stringifies like a plain croak message,
C<< <path>: expected <what>, got <value>[ (<hint>)] at <file> line <n>. >>
Its readers:

=over 4

=item C<path>

Arrayref of names from the root (the struct or function argument) to
the field, e.g. C<['Clay_ElementDeclaration', 'layout', 'padding', 'left']>.

=item C<expected>, C<got>

What the field takes (C<an integer in 0..65535>) and how the value was
seen (C<'-8'>, C<undef>, C<a HASH reference>).

=item C<hint>

A hint for building the value, or undef (only L</CHECKING STRUCTS> sets it).

=item C<unknown_keys>, C<known_keys>

For an unknown-key error: arrayrefs of the offending keys (sorted) and
of the keys the struct takes; undef otherwise.

=item C<message>

The message without the location.

=item C<file>, C<line>

Where the croak happened.

=back

Errors raised inside a callback (for example a bad transition handler
result) are re-thrown unchanged as described in L</ERRORS FROM
CALLBACKS>. Plain function arguments that are not structs (counts,
floats, callbacks) croak plain strings.

=head1 STRINGS

Strings are characters in and out. Text and element ids may contain any
Unicode characters; they reach Clay as UTF-8, and text in render
commands, the measure callback's text and element C<stringId>s come back
as Perl character strings. Clay splits words only on ASCII spaces and
newlines, so slices never cut a character.

Clay::XS copies text into per-context storage and interns element id
strings, so the caller never has to keep strings alive between calls.
Undef text and undef id strings croak, and so does every function that
takes an element id (C<Clay__OpenElementWithId>, C<Clay_GetElementData>,
C<Clay_PointerOver>, C<Clay_GetScrollContainerData>,
C<set_scroll_position>) when it gets anything but an element-id hash
reference, undef included.

=head1 CALLBACKS

All callbacks are CODE references, validated when installed; undef
clears a per-context callback. The callback and userdata values are
copied, so reassigning the caller's variables afterwards has no effect.

=over 4

=item Error handler (C<Clay_Initialize>)

    $handler->({ errorType => CLAY_ERROR_TYPE_..., errorText => $text }, $userdata)

Without a handler, Clay errors are ignored (as in C).

=item C<Clay_SetMeasureTextFunction($cb, $userdata)>

    $cb->($text, \%text_config, $userdata) -> { width => $w, height => $h } or [ $w, $h ]

C<%text_config> has the C<Clay_TextElementConfig> fields. Every context
that lays out text needs its own measure function: measuring text in a
context without one is reported as an error.

=item C<Clay_SetQueryScrollOffsetFunction($cb, $userdata)>

    $cb->($element_id, $userdata) -> { x => $x, y => $y } or [ $x, $y ]

Clay calls it for every scroll container while
C<Clay_SetExternalScrollHandlingEnabled(1)> is on; the returned offset
becomes the container's scroll position. Enabling external handling
without a query function croaks.

=item C<Clay_OnHover($cb, $userdata)>

    $cb->(\%element_id, { position => { x, y }, state => CLAY_POINTER_DATA_... }, $userdata)

Registers a hover callback for the currently open element. Clay forgets
an element's hover callback whenever the element is declared again, so
call C<Clay_OnHover> every frame. C<Clay_SetPointerState> runs the
callbacks registered while declaring the last completed frame, with the
pointer state from before the call.

=item C<Clay_SetTransitionHandlers($handler, $set_initial, $set_final, $userdata)>

    $handler->(\%args, $userdata) -> $complete
    $set_initial->(\%target_state, $properties, $userdata) -> \%initial_state
    $set_final->(\%initial_state, $properties, $userdata) -> \%final_state

One handler set per context serves every element with a C<transition>
config (Clay's transition callbacks carry no element id). C<%args> holds
C<transitionState>, C<initial>, C<target>, C<current>, C<elapsedTime>,
C<duration> and C<properties>; the handler updates C<< $args->{current} >>
(keys it leaves out keep their value) and returns true when the
transition is complete (undef also counts as complete). Transition data
hashes have C<boundingBox>, C<backgroundColor>, C<overlayColor>,
C<borderColor> and C<borderWidth>. An element's
C<< transition => { enter => { hasSetInitial => 1 } } >> routes its enter
transition through C<$set_initial>, and
C<< exit => { hasSetFinal => 1 } >> gives it an exit transition through
C<$set_final> (undef from either means "unchanged"). The C default for
C<< exit => { siblingOrdering } >> is
C<CLAY_EXIT_TRANSITION_ORDERING_UNDERNEATH_SIBLINGS>.

=back

C<Clay_EaseOut(\%args)> takes the same argument hash (C<current> defaults
to C<initial> when absent) and returns
C<< { complete => $bool, current => \%eased_state } >>, easing every
property selected in C<properties>, colours and border widths included.

=head2 What a callback may do

A callback runs while Clay is in the middle of one of its own functions,
so it must not change Clay's state. Inside a callback, these croak with
C<< <function>: cannot be called from inside a Clay callback >> (re-thrown
like any other callback error, see L</ERRORS FROM CALLBACKS>):
C<Clay_Initialize>, C<Clay_SetCurrentContext>, C<Clay_BeginLayout>,
C<Clay_EndLayout>, the element functions (C<Clay__OpenElement>,
C<Clay__OpenElementWithId>, C<Clay__ConfigureOpenElement>,
C<Clay__OpenTextElement>, C<Clay__CloseElement>, C<Clay_OnHover>), the
queries about the open element (C<Clay_GetOpenElementId>,
C<Clay_Hovered>, C<Clay_GetScrollOffset>), C<Clay_SetPointerState>,
C<Clay_UpdateScrollContainers>, C<set_scroll_position>, every setter
(C<Clay_SetLayoutDimensions>, C<Clay_SetMeasureTextFunction>,
C<Clay_ResetMeasureTextCache>, C<Clay_SetQueryScrollOffsetFunction>,
C<Clay_SetExternalScrollHandlingEnabled>, C<Clay_SetTransitionHandlers>,
C<Clay_SetDebugModeEnabled>, C<Clay_SetCullingEnabled>,
C<Clay_SetMaxElementCount>, C<Clay_SetMaxMeasureTextCacheWordCount>) and
an explicit C<DESTROY> of the context the callback runs in. This applies
to every context, not only the running one: Clay has a single current
context.

Read-only queries work: C<Clay_GetCurrentContext>,
C<Clay_GetLayoutDimensions>, C<Clay_GetElementData>,
C<Clay_GetPointerState>, C<Clay_PointerOver>, C<Clay_GetPointerOverIds>,
C<Clay_GetScrollContainerData>, C<Clay_IsDebugModeEnabled>, the count
getters, and the helpers that need no context (ids, hashing,
C<Clay_EaseOut>, C<sizing_*> ...).

Dropping the last reference to the running context inside a callback is
safe: every Clay::XS call keeps its context alive until the statement
that made the call has finished, and the context is freed then.

=head1 ERRORS FROM CALLBACKS

Clay calls the callbacks from inside its C code, which must never be
unwound by a Perl exception. An exception thrown by a callback (or a
malformed callback result, such as a measure function returning a plain
number) is therefore held until Clay returns, then re-thrown by the
Clay::XS function that invoked Clay:

=over 4

=item *

C<Clay_EndLayout> re-throws errors from the measure function, the error
handler, the query-scroll function and the transition handlers,
including those raised while elements were being declared.

=item *

C<Clay_SetPointerState> re-throws errors from hover callbacks.

=item *

The element-construction functions (C<Clay__OpenElement>,
C<Clay__OpenElementWithId>, C<Clay__ConfigureOpenElement>,
C<Clay__OpenTextElement>, C<Clay__CloseElement>, C<Clay_OnHover>) and the
in-element queries (C<Clay_GetOpenElementId>, C<Clay_Hovered>,
C<Clay_GetScrollOffset>) never re-throw held errors, so declarations stay
balanced; C<Clay_EndLayout> reports them. An error held when a frame is
abandoned is re-thrown by the next C<Clay_BeginLayout> with the suffix
C< (from the previous unfinished frame)>. Every other Clay::XS function
re-throws a held error as well.

=back

Only the first error is kept; later ones are counted and the message
gains C< (and N more callback errors this frame)>. Exception objects
(including a L</STRUCT ERRORS> object for a malformed callback result)
are re-thrown unchanged, without either suffix. After a measure
function fails, text is measured as 0x0 without calling Perl again until
the error has been re-thrown, and Clay's measurement cache is reset so
the next frame measures afresh. The render commands of a frame whose
C<Clay_EndLayout> croaked are discarded. Callbacks do not disturb the
caller's C<$@>.

=head1 RENDER COMMANDS

C<Clay_EndLayout> returns an arrayref of hashes, one per
C<Clay_RenderCommand>:

    {
        id          => $element_id,
        commandType => CLAY_RENDER_COMMAND_TYPE_...,
        zIndex      => $z,
        boundingBox => { x, y, width, height },
        userData    => $integer,           # 0 when none was set
        renderData  => { ... },            # depends on commandType
    }

C<renderData> mirrors the C union member for the command type:
C<RECTANGLE> has C<backgroundColor>, C<cornerRadius>; C<TEXT> has
C<stringContents>, C<textColor>, C<fontId>, C<fontSize>,
C<letterSpacing>, C<lineHeight>; C<IMAGE> and C<CUSTOM> have
C<backgroundColor>, C<cornerRadius> and C<imageData> / C<customData>;
C<BORDER> has C<color>, C<cornerRadius>, C<width>; C<SCISSOR_START> /
C<SCISSOR_END> have C<horizontal>, C<vertical>; C<OVERLAY_COLOR_START> /
C<OVERLAY_COLOR_END> have C<color>. C<userData>, C<imageData> and
C<customData> are the integers passed in the declaration (Clay treats
them as opaque pointers).

=head1 SIZING GROUPS

A patched Clay adds C<< sizingGroup => { width => $id, height => $id } >>
to the element declaration. Elements sharing a non-zero group id on an
axis are equalized to the group's largest size before grow distribution;
L<Clay::UI::Grid> builds on this. C<FIT> and C<GROW> elements take part
(C<FIXED> and C<PERCENT> sizes do not depend on content); each member
stays within its own C<max>. Groups may nest - a member can contain
members of other groups, as with a grid inside a grid cell - and
equalization repeats until the sizes settle, widening containers
(C<FIT> and C<GROW>) up the tree. Nesting that forms a cycle on one axis
(a member of group 1 contains a member of group 2 whose other member
contains a member of group 1) cannot settle; Clay then reports
C<CLAY_ERROR_TYPE_SIZING_GROUP_CYCLE> through the error handler.

=head1 LIMITATIONS

=over 4

=item *

Per-element transition handlers are not supported. Clay's transition
callback signatures do not include the element id, so a single C
trampoline cannot dispatch to different Perl coderefs per element. Use
C<Clay_SetTransitionHandlers> to install a single set of handlers that
fire for every transitioning element; dispatch based on the values inside
the callback arguments.

=item *

Contexts are per interpreter (see L</CONTEXTS>). Several contexts can be
used from one interpreter with C<Clay_SetCurrentContext>; using Clay from
several threads at once is not supported.

=back

=head1 LICENSE

This binding is released under the same zlib/libpng license as Clay
itself. See F<src/clay/LICENSE.md> for the upstream notice.

=cut
