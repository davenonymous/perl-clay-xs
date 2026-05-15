package Clay::Layout;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Exporter 5.57 'import';
use XSLoader;

our $VERSION = '0.001';

XSLoader::load(__PACKAGE__, $VERSION);

# -----------------------------------------------------------------------------
# Re-export every Clay_* / Clay__* / sizing_* / padding_* / border_* /
# corner_radius_* / Clay_Set* helper as its bare name, plus the constants
# the BOOT block installed.
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
);

our %EXPORT_TAGS = (
    all => [ @EXPORT_OK ],
);

1;

__END__

=pod

=head1 NAME

Clay::Layout - Perl XS bindings for the Clay (C Layout) UI library

=head1 SYNOPSIS

    use Clay::Layout qw(:all);

    my $ctx = Clay_Initialize(
        Clay_MinMemorySize(),
        { width => 800, height => 600 },
        sub ($err, $userdata) { warn "Clay error: $err->{errorText}" },
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
    Clay__CloseElement();

    my $commands = Clay_EndLayout();
    for my $cmd (@$commands) {
        # render $cmd according to $cmd->{commandType} ...
    }

=head1 DESCRIPTION

C<Clay::Layout> is a thin, name-preserving XS binding to Clay v0.14
L<https://github.com/nicbarker/clay>, a header-only C UI layout library.
Every public C<Clay_*> and internal C<Clay__*> function in F<clay.h> is
exposed under its exact C name; the macros (C<CLAY()>, C<CLAY_TEXT()>,
C<CLAY_ID()>, ...) are not bindable directly but the underlying open /
configure / close primitives they expand to are.

This module is the low-level surface. A higher-level idiomatic-Perl
wrapper that uses closures for nesting is planned in a separate
distribution.

=head1 MAPPING C MACROS TO PERL

The Clay C macros expand to combinations of internal functions. Here is
how to spell each one in Perl:

    CLAY_ID("foo")              ->  Clay_GetElementId("foo")
    CLAY_IDI("foo", 3)          ->  Clay_GetElementIdWithIndex("foo", 3)
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

=head1 LIMITATIONS

=over 4

=item *

Per-element transition handlers are not supported in this release. Clay's
transition callback signatures do not include the element id so a single
C trampoline cannot dispatch to different Perl coderefs per element. Use
C<Clay_SetTransitionHandlers> to install a single set of handlers that
fire for every transitioning element; dispatch based on the values inside
the callback arguments.

=item *

C<Clay::Layout> is single-interpreter and single-threaded, matching
Clay's own design. Multi-context use is supported via
C<Clay_SetCurrentContext>; multi-thread use is not.

=back

=head1 LICENSE

This binding is released under the same zlib/libpng license as Clay
itself. See F<src/clay/LICENSE.md> for the upstream notice.

=cut
