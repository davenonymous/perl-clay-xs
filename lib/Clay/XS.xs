/*
 * XS.xs - The XS surface for Clay::XS.
 *
 * Every public and internal Clay v0.14 function is exposed under its
 * exact C name. The Perl-side module re-exports these and adds a handful
 * of convenience constructors for macros that don't translate
 * (CLAY_SIZING_FIT etc.).
 *
 * Each function is grouped by phase comment to match the implementation
 * plan. Boundary marshalling lives in src/marshal.c; trampolines for
 * function-pointer callbacks live in src/callbacks.c.
 *
 * Memory ownership notes are in src/clay_perl.h. The cliffs notes are:
 *
 *   - Clay_Initialize allocates the underlying Clay arena and stores it
 *     in a clay_perl_context that the Perl side holds via a blessed
 *     scalar ref. DESTROY frees everything.
 *
 *   - Strings passed to Clay (element ids, text contents) are copied
 *     into the per-frame string arena inside the Perl context. The
 *     arena is reset at every Clay_BeginLayout call so the Perl caller
 *     does not need to keep input strings alive across frames.
 *
 *   - Element open/configure/close must be balanced by the caller. We
 *     do not enforce balance ourselves; the underlying Clay__ functions
 *     croak via the error handler if they detect imbalance.
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "src/clay_perl.h"

#include <string.h>

/* ===========================================================================
 * BOOT helper: install integer constants under Clay::XS::.
 * ======================================================================== */

static void install_iv_const(pTHX_ const char *name, IV value)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "Clay::XS::%s", name);
    newCONSTSUB(gv_stashpv("Clay::XS", GV_ADD), name, newSViv(value));
    (void) buf;
}

/* ===========================================================================
 * Internal helper: get the active clay_perl_context (the one whose
 * Clay_Context * is currently set as Clay's global). Used by functions
 * that operate on the current context implicitly (BeginLayout, etc.).
 *
 * For Phase 1 we keep a single "last context whose Clay_Initialize ran"
 * pointer set at the C level. Multi-context users must call
 * Clay_SetCurrentContext explicitly via the wrapper before each Clay
 * function call. The wrapper updates this pointer.
 *
 * Storing it as a file-local variable rather than threading it through
 * each XS function keeps the C API mirroring exact: each Clay_*
 * function in C uses Clay_GetCurrentContext() internally.
 * ======================================================================== */

static clay_perl_context *clay_perl_current_ctx = NULL;

static clay_perl_context *get_current_ctx(pTHX)
{
    if (!clay_perl_current_ctx) {
        croak("Clay::XS: no current context; call Clay_Initialize first");
    }
    return clay_perl_current_ctx;
}

MODULE = Clay::XS    PACKAGE = Clay::XS    PREFIX = xs_

PROTOTYPES: DISABLE

BOOT:
{
    /* Layout direction. */
    install_iv_const(aTHX_ "CLAY_LEFT_TO_RIGHT", CLAY_LEFT_TO_RIGHT);
    install_iv_const(aTHX_ "CLAY_TOP_TO_BOTTOM", CLAY_TOP_TO_BOTTOM);

    /* Alignment. */
    install_iv_const(aTHX_ "CLAY_ALIGN_X_LEFT",   CLAY_ALIGN_X_LEFT);
    install_iv_const(aTHX_ "CLAY_ALIGN_X_RIGHT",  CLAY_ALIGN_X_RIGHT);
    install_iv_const(aTHX_ "CLAY_ALIGN_X_CENTER", CLAY_ALIGN_X_CENTER);
    install_iv_const(aTHX_ "CLAY_ALIGN_Y_TOP",    CLAY_ALIGN_Y_TOP);
    install_iv_const(aTHX_ "CLAY_ALIGN_Y_BOTTOM", CLAY_ALIGN_Y_BOTTOM);
    install_iv_const(aTHX_ "CLAY_ALIGN_Y_CENTER", CLAY_ALIGN_Y_CENTER);

    /* Sizing type. */
    install_iv_const(aTHX_ "CLAY__SIZING_TYPE_FIT",     CLAY__SIZING_TYPE_FIT);
    install_iv_const(aTHX_ "CLAY__SIZING_TYPE_GROW",    CLAY__SIZING_TYPE_GROW);
    install_iv_const(aTHX_ "CLAY__SIZING_TYPE_PERCENT", CLAY__SIZING_TYPE_PERCENT);
    install_iv_const(aTHX_ "CLAY__SIZING_TYPE_FIXED",   CLAY__SIZING_TYPE_FIXED);

    /* Text wrap. */
    install_iv_const(aTHX_ "CLAY_TEXT_WRAP_WORDS",    CLAY_TEXT_WRAP_WORDS);
    install_iv_const(aTHX_ "CLAY_TEXT_WRAP_NEWLINES", CLAY_TEXT_WRAP_NEWLINES);
    install_iv_const(aTHX_ "CLAY_TEXT_WRAP_NONE",     CLAY_TEXT_WRAP_NONE);
    install_iv_const(aTHX_ "CLAY_TEXT_ALIGN_LEFT",    CLAY_TEXT_ALIGN_LEFT);
    install_iv_const(aTHX_ "CLAY_TEXT_ALIGN_CENTER",  CLAY_TEXT_ALIGN_CENTER);
    install_iv_const(aTHX_ "CLAY_TEXT_ALIGN_RIGHT",   CLAY_TEXT_ALIGN_RIGHT);

    /* Floating attach points. */
    install_iv_const(aTHX_ "CLAY_ATTACH_POINT_LEFT_TOP",      CLAY_ATTACH_POINT_LEFT_TOP);
    install_iv_const(aTHX_ "CLAY_ATTACH_POINT_LEFT_CENTER",   CLAY_ATTACH_POINT_LEFT_CENTER);
    install_iv_const(aTHX_ "CLAY_ATTACH_POINT_LEFT_BOTTOM",   CLAY_ATTACH_POINT_LEFT_BOTTOM);
    install_iv_const(aTHX_ "CLAY_ATTACH_POINT_CENTER_TOP",    CLAY_ATTACH_POINT_CENTER_TOP);
    install_iv_const(aTHX_ "CLAY_ATTACH_POINT_CENTER_CENTER", CLAY_ATTACH_POINT_CENTER_CENTER);
    install_iv_const(aTHX_ "CLAY_ATTACH_POINT_CENTER_BOTTOM", CLAY_ATTACH_POINT_CENTER_BOTTOM);
    install_iv_const(aTHX_ "CLAY_ATTACH_POINT_RIGHT_TOP",     CLAY_ATTACH_POINT_RIGHT_TOP);
    install_iv_const(aTHX_ "CLAY_ATTACH_POINT_RIGHT_CENTER",  CLAY_ATTACH_POINT_RIGHT_CENTER);
    install_iv_const(aTHX_ "CLAY_ATTACH_POINT_RIGHT_BOTTOM",  CLAY_ATTACH_POINT_RIGHT_BOTTOM);

    install_iv_const(aTHX_ "CLAY_POINTER_CAPTURE_MODE_CAPTURE",     CLAY_POINTER_CAPTURE_MODE_CAPTURE);
    install_iv_const(aTHX_ "CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH", CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH);

    install_iv_const(aTHX_ "CLAY_ATTACH_TO_NONE",            CLAY_ATTACH_TO_NONE);
    install_iv_const(aTHX_ "CLAY_ATTACH_TO_PARENT",          CLAY_ATTACH_TO_PARENT);
    install_iv_const(aTHX_ "CLAY_ATTACH_TO_ELEMENT_WITH_ID", CLAY_ATTACH_TO_ELEMENT_WITH_ID);
    install_iv_const(aTHX_ "CLAY_ATTACH_TO_ROOT",            CLAY_ATTACH_TO_ROOT);

    install_iv_const(aTHX_ "CLAY_CLIP_TO_NONE",            CLAY_CLIP_TO_NONE);
    install_iv_const(aTHX_ "CLAY_CLIP_TO_ATTACHED_PARENT", CLAY_CLIP_TO_ATTACHED_PARENT);

    /* Render command types. */
    install_iv_const(aTHX_ "CLAY_RENDER_COMMAND_TYPE_NONE",                CLAY_RENDER_COMMAND_TYPE_NONE);
    install_iv_const(aTHX_ "CLAY_RENDER_COMMAND_TYPE_RECTANGLE",           CLAY_RENDER_COMMAND_TYPE_RECTANGLE);
    install_iv_const(aTHX_ "CLAY_RENDER_COMMAND_TYPE_BORDER",              CLAY_RENDER_COMMAND_TYPE_BORDER);
    install_iv_const(aTHX_ "CLAY_RENDER_COMMAND_TYPE_TEXT",                CLAY_RENDER_COMMAND_TYPE_TEXT);
    install_iv_const(aTHX_ "CLAY_RENDER_COMMAND_TYPE_IMAGE",               CLAY_RENDER_COMMAND_TYPE_IMAGE);
    install_iv_const(aTHX_ "CLAY_RENDER_COMMAND_TYPE_SCISSOR_START",       CLAY_RENDER_COMMAND_TYPE_SCISSOR_START);
    install_iv_const(aTHX_ "CLAY_RENDER_COMMAND_TYPE_SCISSOR_END",         CLAY_RENDER_COMMAND_TYPE_SCISSOR_END);
    install_iv_const(aTHX_ "CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_START", CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_START);
    install_iv_const(aTHX_ "CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_END",   CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_END);
    install_iv_const(aTHX_ "CLAY_RENDER_COMMAND_TYPE_CUSTOM",              CLAY_RENDER_COMMAND_TYPE_CUSTOM);

    /* Pointer state. */
    install_iv_const(aTHX_ "CLAY_POINTER_DATA_PRESSED_THIS_FRAME",  CLAY_POINTER_DATA_PRESSED_THIS_FRAME);
    install_iv_const(aTHX_ "CLAY_POINTER_DATA_PRESSED",             CLAY_POINTER_DATA_PRESSED);
    install_iv_const(aTHX_ "CLAY_POINTER_DATA_RELEASED_THIS_FRAME", CLAY_POINTER_DATA_RELEASED_THIS_FRAME);
    install_iv_const(aTHX_ "CLAY_POINTER_DATA_RELEASED",            CLAY_POINTER_DATA_RELEASED);

    /* Transitions. */
    install_iv_const(aTHX_ "CLAY_TRANSITION_STATE_IDLE",          CLAY_TRANSITION_STATE_IDLE);
    install_iv_const(aTHX_ "CLAY_TRANSITION_STATE_ENTERING",      CLAY_TRANSITION_STATE_ENTERING);
    install_iv_const(aTHX_ "CLAY_TRANSITION_STATE_TRANSITIONING", CLAY_TRANSITION_STATE_TRANSITIONING);
    install_iv_const(aTHX_ "CLAY_TRANSITION_STATE_EXITING",       CLAY_TRANSITION_STATE_EXITING);

    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_NONE",             CLAY_TRANSITION_PROPERTY_NONE);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_X",                CLAY_TRANSITION_PROPERTY_X);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_Y",                CLAY_TRANSITION_PROPERTY_Y);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_POSITION",         CLAY_TRANSITION_PROPERTY_POSITION);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_WIDTH",            CLAY_TRANSITION_PROPERTY_WIDTH);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_HEIGHT",           CLAY_TRANSITION_PROPERTY_HEIGHT);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_DIMENSIONS",       CLAY_TRANSITION_PROPERTY_DIMENSIONS);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_BOUNDING_BOX",     CLAY_TRANSITION_PROPERTY_BOUNDING_BOX);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR", CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_OVERLAY_COLOR",    CLAY_TRANSITION_PROPERTY_OVERLAY_COLOR);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_CORNER_RADIUS",    CLAY_TRANSITION_PROPERTY_CORNER_RADIUS);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_BORDER_COLOR",     CLAY_TRANSITION_PROPERTY_BORDER_COLOR);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_BORDER_WIDTH",     CLAY_TRANSITION_PROPERTY_BORDER_WIDTH);
    install_iv_const(aTHX_ "CLAY_TRANSITION_PROPERTY_BORDER",           CLAY_TRANSITION_PROPERTY_BORDER);

    install_iv_const(aTHX_ "CLAY_TRANSITION_ENTER_SKIP_ON_FIRST_PARENT_FRAME",    CLAY_TRANSITION_ENTER_SKIP_ON_FIRST_PARENT_FRAME);
    install_iv_const(aTHX_ "CLAY_TRANSITION_ENTER_TRIGGER_ON_FIRST_PARENT_FRAME", CLAY_TRANSITION_ENTER_TRIGGER_ON_FIRST_PARENT_FRAME);
    install_iv_const(aTHX_ "CLAY_TRANSITION_EXIT_SKIP_WHEN_PARENT_EXITS",         CLAY_TRANSITION_EXIT_SKIP_WHEN_PARENT_EXITS);
    install_iv_const(aTHX_ "CLAY_TRANSITION_EXIT_TRIGGER_WHEN_PARENT_EXITS",      CLAY_TRANSITION_EXIT_TRIGGER_WHEN_PARENT_EXITS);
    install_iv_const(aTHX_ "CLAY_TRANSITION_DISABLE_INTERACTIONS_WHILE_TRANSITIONING_POSITION", CLAY_TRANSITION_DISABLE_INTERACTIONS_WHILE_TRANSITIONING_POSITION);
    install_iv_const(aTHX_ "CLAY_TRANSITION_ALLOW_INTERACTIONS_WHILE_TRANSITIONING_POSITION",   CLAY_TRANSITION_ALLOW_INTERACTIONS_WHILE_TRANSITIONING_POSITION);
    install_iv_const(aTHX_ "CLAY_EXIT_TRANSITION_ORDERING_UNDERNEATH_SIBLINGS", CLAY_EXIT_TRANSITION_ORDERING_UNDERNEATH_SIBLINGS);
    install_iv_const(aTHX_ "CLAY_EXIT_TRANSITION_ORDERING_NATURAL_ORDER",       CLAY_EXIT_TRANSITION_ORDERING_NATURAL_ORDER);
    install_iv_const(aTHX_ "CLAY_EXIT_TRANSITION_ORDERING_ABOVE_SIBLINGS",      CLAY_EXIT_TRANSITION_ORDERING_ABOVE_SIBLINGS);

    /* Error types. */
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_TEXT_MEASUREMENT_FUNCTION_NOT_PROVIDED", CLAY_ERROR_TYPE_TEXT_MEASUREMENT_FUNCTION_NOT_PROVIDED);
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_ARENA_CAPACITY_EXCEEDED",                CLAY_ERROR_TYPE_ARENA_CAPACITY_EXCEEDED);
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_ELEMENTS_CAPACITY_EXCEEDED",             CLAY_ERROR_TYPE_ELEMENTS_CAPACITY_EXCEEDED);
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_TEXT_MEASUREMENT_CAPACITY_EXCEEDED",     CLAY_ERROR_TYPE_TEXT_MEASUREMENT_CAPACITY_EXCEEDED);
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_DUPLICATE_ID",                           CLAY_ERROR_TYPE_DUPLICATE_ID);
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_FLOATING_CONTAINER_PARENT_NOT_FOUND",    CLAY_ERROR_TYPE_FLOATING_CONTAINER_PARENT_NOT_FOUND);
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_PERCENTAGE_OVER_1",                      CLAY_ERROR_TYPE_PERCENTAGE_OVER_1);
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_INTERNAL_ERROR",                         CLAY_ERROR_TYPE_INTERNAL_ERROR);
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_UNBALANCED_OPEN_CLOSE",                  CLAY_ERROR_TYPE_UNBALANCED_OPEN_CLOSE);
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_HASH_MAP_CAPACITY_EXCEEDED",             CLAY_ERROR_TYPE_HASH_MAP_CAPACITY_EXCEEDED);
}

# =============================================================================
# Phase 4: Core lifecycle.
# =============================================================================

uint32_t
xs_Clay_MinMemorySize()
    CODE:
        RETVAL = Clay_MinMemorySize();
    OUTPUT:
        RETVAL

SV *
xs_Clay_Initialize(capacity, dimensions_sv, error_handler_sv = &PL_sv_undef, error_userdata_sv = &PL_sv_undef)
        UV capacity
        SV *dimensions_sv
        SV *error_handler_sv
        SV *error_userdata_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_Dimensions dim;
        Clay_ErrorHandler handler;
    CODE:
        if (capacity == 0) {
            croak("Clay_Initialize: capacity must be > 0 (typically Clay_MinMemorySize())");
        }
        ctx = clay_perl_context_new(aTHX_ (size_t) capacity);

        if (SvOK(error_handler_sv)) {
            ctx->error_handler_cb = SvREFCNT_inc(error_handler_sv);
            if (SvOK(error_userdata_sv)) {
                ctx->error_handler_userdata = SvREFCNT_inc(error_userdata_sv);
            }
        }

        dim = clay_dimensions_from_sv(aTHX_ dimensions_sv);
        handler.errorHandlerFunction = clay_perl_error_handler_trampoline;
        handler.userData             = ctx;

        ctx->clay_ctx = Clay_Initialize(ctx->clay_arena, dim, handler);
        clay_perl_current_ctx = ctx;
        RETVAL = clay_perl_context_to_sv(aTHX_ ctx);
    OUTPUT:
        RETVAL

void
xs_Clay_SetCurrentContext(ctx_sv)
        SV *ctx_sv
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = clay_perl_context_from_sv(aTHX_ ctx_sv);
        Clay_SetCurrentContext(ctx->clay_ctx);
        clay_perl_current_ctx = ctx;

SV *
xs_Clay_GetCurrentContext()
    PREINIT:
        Clay_Context *raw;
    CODE:
        raw = Clay_GetCurrentContext();
        if (!raw) {
            RETVAL = &PL_sv_undef;
        } else if (clay_perl_current_ctx && clay_perl_current_ctx->clay_ctx == raw) {
            RETVAL = clay_perl_context_to_sv(aTHX_ clay_perl_current_ctx);
        } else {
            /* Foreign context (created outside this binding) - return as
             * opaque IV; the caller will not be able to use it with our
             * other functions. */
            RETVAL = newSViv(PTR2IV(raw));
        }
    OUTPUT:
        RETVAL

void
xs_Clay_SetLayoutDimensions(dimensions_sv)
        SV *dimensions_sv
    PREINIT:
        Clay_Dimensions dim;
    CODE:
        dim = clay_dimensions_from_sv(aTHX_ dimensions_sv);
        Clay_SetLayoutDimensions(dim);

SV *
xs_Clay_GetLayoutDimensions()
    CODE:
        RETVAL = clay_dimensions_to_sv(aTHX_ Clay_GetLayoutDimensions());
    OUTPUT:
        RETVAL

void
xs_Clay_BeginLayout()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = get_current_ctx(aTHX);
        clay_perl_arena_reset(ctx);
        clay_perl_hover_registry_sweep(aTHX_ ctx, 2);
        Clay_BeginLayout();

SV *
xs_Clay_EndLayout(deltaTime = 0.0)
        double deltaTime
    PREINIT:
        clay_perl_context *ctx;
        Clay_RenderCommandArray cmds;
    CODE:
        ctx = get_current_ctx(aTHX);
        clay_perl_active_transition_ctx = ctx;
        cmds = Clay_EndLayout((float) deltaTime);
        clay_perl_active_transition_ctx = NULL;
        RETVAL = clay_render_command_array_to_sv(aTHX_ &cmds);
    OUTPUT:
        RETVAL

# =============================================================================
# Phase 5: Element open/close.
# =============================================================================

void
xs_Clay__OpenElement()
    CODE:
        Clay__OpenElement();

void
xs_Clay__OpenElementWithId(id_sv)
        SV *id_sv
    PREINIT:
        Clay_ElementId id;
    CODE:
        id = clay_element_id_from_sv(aTHX_ id_sv);
        Clay__OpenElementWithId(id);

void
xs_Clay__CloseElement()
    CODE:
        Clay__CloseElement();

void
xs_Clay__ConfigureOpenElement(decl_sv)
        SV *decl_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_ElementDeclaration decl;
    CODE:
        ctx = get_current_ctx(aTHX);
        decl = clay_element_declaration_from_sv(aTHX_ ctx, decl_sv);
        Clay__ConfigureOpenElement(decl);

void
xs_Clay__OpenTextElement(text_sv, config_sv)
        SV *text_sv
        SV *config_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_String text;
        Clay_TextElementConfig config;
    CODE:
        ctx = get_current_ctx(aTHX);
        text = clay_perl_arena_copy_pv(aTHX_ ctx, text_sv);
        config = clay_text_element_config_from_sv(aTHX_ config_sv);
        Clay__OpenTextElement(text, config);

SV *
xs_Clay__HashString(key_sv, seed = 0)
        SV *key_sv
        UV seed
    PREINIT:
        clay_perl_context *ctx;
        Clay_String key;
    CODE:
        ctx = get_current_ctx(aTHX);
        key = clay_perl_arena_copy_pv(aTHX_ ctx, key_sv);
        RETVAL = clay_element_id_to_sv(aTHX_ Clay__HashString(key, (uint32_t) seed));
    OUTPUT:
        RETVAL

SV *
xs_Clay__HashStringWithOffset(key_sv, offset, seed = 0)
        SV *key_sv
        UV offset
        UV seed
    PREINIT:
        clay_perl_context *ctx;
        Clay_String key;
    CODE:
        ctx = get_current_ctx(aTHX);
        key = clay_perl_arena_copy_pv(aTHX_ ctx, key_sv);
        RETVAL = clay_element_id_to_sv(aTHX_
            Clay__HashStringWithOffset(key, (uint32_t) offset, (uint32_t) seed));
    OUTPUT:
        RETVAL

UV
xs_Clay_GetOpenElementId()
    CODE:
        RETVAL = (UV) Clay_GetOpenElementId();
    OUTPUT:
        RETVAL

SV *
xs_Clay_GetElementId(id_string_sv)
        SV *id_string_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_String s;
    CODE:
        ctx = get_current_ctx(aTHX);
        s = clay_perl_arena_copy_pv(aTHX_ ctx, id_string_sv);
        RETVAL = clay_element_id_to_sv(aTHX_ Clay_GetElementId(s));
    OUTPUT:
        RETVAL

SV *
xs_Clay_GetElementIdWithIndex(id_string_sv, index)
        SV *id_string_sv
        UV index
    PREINIT:
        clay_perl_context *ctx;
        Clay_String s;
    CODE:
        ctx = get_current_ctx(aTHX);
        s = clay_perl_arena_copy_pv(aTHX_ ctx, id_string_sv);
        RETVAL = clay_element_id_to_sv(aTHX_
            Clay_GetElementIdWithIndex(s, (uint32_t) index));
    OUTPUT:
        RETVAL

SV *
xs_Clay_GetElementData(id_sv)
        SV *id_sv
    PREINIT:
        Clay_ElementId id;
    CODE:
        id = clay_element_id_from_sv(aTHX_ id_sv);
        RETVAL = clay_element_data_to_sv(aTHX_ Clay_GetElementData(id));
    OUTPUT:
        RETVAL

# =============================================================================
# Phase 6: Text measurement.
# =============================================================================

void
xs_Clay_SetMeasureTextFunction(cb_sv, userdata_sv = &PL_sv_undef)
        SV *cb_sv
        SV *userdata_sv
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = get_current_ctx(aTHX);

        if (ctx->measure_text_cb)        SvREFCNT_dec(ctx->measure_text_cb);
        if (ctx->measure_text_userdata)  SvREFCNT_dec(ctx->measure_text_userdata);
        ctx->measure_text_cb       = SvOK(cb_sv)       ? SvREFCNT_inc(cb_sv)       : NULL;
        ctx->measure_text_userdata = SvOK(userdata_sv) ? SvREFCNT_inc(userdata_sv) : NULL;

        Clay_SetMeasureTextFunction(clay_perl_measure_text_trampoline, ctx);

void
xs_Clay_ResetMeasureTextCache()
    CODE:
        Clay_ResetMeasureTextCache();

# =============================================================================
# Phase 7: Pointer & interaction.
# =============================================================================

void
xs_Clay_SetPointerState(position_sv, pointerDown)
        SV *position_sv
        bool pointerDown
    PREINIT:
        Clay_Vector2 pos;
    CODE:
        pos = clay_vector2_from_sv(aTHX_ position_sv);
        Clay_SetPointerState(pos, pointerDown);

SV *
xs_Clay_GetPointerState()
    CODE:
        RETVAL = clay_pointer_data_to_sv(aTHX_ Clay_GetPointerState());
    OUTPUT:
        RETVAL

bool
xs_Clay_Hovered()
    CODE:
        RETVAL = Clay_Hovered();
    OUTPUT:
        RETVAL

void
xs_Clay_OnHover(cb_sv, userdata_sv = &PL_sv_undef)
        SV *cb_sv
        SV *userdata_sv
    PREINIT:
        clay_perl_context *ctx;
        uint32_t open_id;
    CODE:
        ctx = get_current_ctx(aTHX);
        open_id = Clay_GetOpenElementId();
        if (open_id != 0) {
            clay_perl_hover_register(aTHX_ ctx, open_id, cb_sv, userdata_sv);
        }
        Clay_OnHover(clay_perl_on_hover_trampoline, ctx);

bool
xs_Clay_PointerOver(id_sv)
        SV *id_sv
    PREINIT:
        Clay_ElementId id;
    CODE:
        id = clay_element_id_from_sv(aTHX_ id_sv);
        RETVAL = Clay_PointerOver(id);
    OUTPUT:
        RETVAL

SV *
xs_Clay_GetPointerOverIds()
    PREINIT:
        Clay_ElementIdArray ids;
        AV *av;
        int32_t i;
    CODE:
        ids = Clay_GetPointerOverIds();
        av = newAV();
        if (ids.length > 0) {
            av_extend(av, ids.length - 1);
        }
        for (i = 0; i < ids.length; i++) {
            av_push(av, clay_element_id_to_sv(aTHX_ ids.internalArray[i]));
        }
        RETVAL = newRV_noinc((SV *) av);
    OUTPUT:
        RETVAL

# =============================================================================
# Phase 8: Scroll support.
# =============================================================================

void
xs_Clay_UpdateScrollContainers(enable_drag_scrolling, scroll_delta_sv, delta_time)
        bool enable_drag_scrolling
        SV *scroll_delta_sv
        double delta_time
    PREINIT:
        Clay_Vector2 delta;
    CODE:
        delta = clay_vector2_from_sv(aTHX_ scroll_delta_sv);
        Clay_UpdateScrollContainers(enable_drag_scrolling, delta, (float) delta_time);

SV *
xs_Clay_GetScrollOffset()
    CODE:
        RETVAL = clay_vector2_to_sv(aTHX_ Clay_GetScrollOffset());
    OUTPUT:
        RETVAL

SV *
xs_Clay_GetScrollContainerData(id_sv)
        SV *id_sv
    PREINIT:
        Clay_ElementId id;
    CODE:
        id = clay_element_id_from_sv(aTHX_ id_sv);
        RETVAL = clay_scroll_container_data_to_sv(aTHX_ Clay_GetScrollContainerData(id));
    OUTPUT:
        RETVAL

void
xs_Clay_SetQueryScrollOffsetFunction(cb_sv, userdata_sv = &PL_sv_undef)
        SV *cb_sv
        SV *userdata_sv
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = get_current_ctx(aTHX);
        if (ctx->query_scroll_offset_cb)       SvREFCNT_dec(ctx->query_scroll_offset_cb);
        if (ctx->query_scroll_offset_userdata) SvREFCNT_dec(ctx->query_scroll_offset_userdata);
        ctx->query_scroll_offset_cb       = SvOK(cb_sv)       ? SvREFCNT_inc(cb_sv)       : NULL;
        ctx->query_scroll_offset_userdata = SvOK(userdata_sv) ? SvREFCNT_inc(userdata_sv) : NULL;
        Clay_SetQueryScrollOffsetFunction(clay_perl_query_scroll_offset_trampoline, ctx);

# =============================================================================
# Phase 9: Debug, culling, capacity, ease helper.
# =============================================================================

void
xs_Clay_SetDebugModeEnabled(enabled)
        bool enabled
    CODE:
        Clay_SetDebugModeEnabled(enabled);

bool
xs_Clay_IsDebugModeEnabled()
    CODE:
        RETVAL = Clay_IsDebugModeEnabled();
    OUTPUT:
        RETVAL

void
xs_Clay_SetCullingEnabled(enabled)
        bool enabled
    CODE:
        Clay_SetCullingEnabled(enabled);

IV
xs_Clay_GetMaxElementCount()
    CODE:
        RETVAL = (IV) Clay_GetMaxElementCount();
    OUTPUT:
        RETVAL

void
xs_Clay_SetMaxElementCount(count)
        IV count
    CODE:
        Clay_SetMaxElementCount((int32_t) count);

IV
xs_Clay_GetMaxMeasureTextCacheWordCount()
    CODE:
        RETVAL = (IV) Clay_GetMaxMeasureTextCacheWordCount();
    OUTPUT:
        RETVAL

void
xs_Clay_SetMaxMeasureTextCacheWordCount(count)
        IV count
    CODE:
        Clay_SetMaxMeasureTextCacheWordCount((int32_t) count);

SV *
xs_Clay_EaseOut(args_sv)
        SV *args_sv
    PREINIT:
        Clay_TransitionCallbackArguments args;
        Clay_TransitionData current_state;
        HV *hv;
        HV *result_hv;
        SV **slot;
        bool complete;
    CODE:
        if (!SvROK(args_sv) || SvTYPE(SvRV(args_sv)) != SVt_PVHV) {
            croak("Clay_EaseOut: expected hash reference");
        }
        hv = (HV *) SvRV(args_sv);

        memset(&args,           0, sizeof(args));
        memset(&current_state,  0, sizeof(current_state));

        slot = hv_fetchs(hv, "transitionState", 0);
        args.transitionState = (slot && *slot && SvOK(*slot))
            ? (Clay_TransitionState) SvIV(*slot) : CLAY_TRANSITION_STATE_IDLE;

        slot = hv_fetchs(hv, "elapsedTime", 0);
        args.elapsedTime = (slot && *slot && SvOK(*slot))
            ? (float) SvNV(*slot) : 0;

        slot = hv_fetchs(hv, "duration", 0);
        args.duration = (slot && *slot && SvOK(*slot))
            ? (float) SvNV(*slot) : 0;

        slot = hv_fetchs(hv, "properties", 0);
        args.properties = (slot && *slot && SvOK(*slot))
            ? (Clay_TransitionProperty) SvUV(*slot)
            : (Clay_TransitionProperty) 0;

        /* Build initial, target, and current TransitionData from input hash.
         * Clay_EaseOut writes the lerped result through args.current. */
        slot = hv_fetchs(hv, "initial", 0);
        if (slot && *slot) {
            HV *th = (SvROK(*slot) && SvTYPE(SvRV(*slot)) == SVt_PVHV)
                     ? (HV *) SvRV(*slot) : NULL;
            if (th) {
                SV **bb_slot = hv_fetchs(th, "boundingBox", 0);
                if (bb_slot && *bb_slot)
                    args.initial.boundingBox = clay_bounding_box_from_sv(aTHX_ *bb_slot);
            }
        }
        slot = hv_fetchs(hv, "target", 0);
        if (slot && *slot) {
            HV *th = (SvROK(*slot) && SvTYPE(SvRV(*slot)) == SVt_PVHV)
                     ? (HV *) SvRV(*slot) : NULL;
            if (th) {
                SV **bb_slot = hv_fetchs(th, "boundingBox", 0);
                if (bb_slot && *bb_slot)
                    args.target.boundingBox = clay_bounding_box_from_sv(aTHX_ *bb_slot);
            }
        }
        slot = hv_fetchs(hv, "current", 0);
        if (slot && *slot) {
            HV *th = (SvROK(*slot) && SvTYPE(SvRV(*slot)) == SVt_PVHV)
                     ? (HV *) SvRV(*slot) : NULL;
            if (th) {
                SV **bb_slot = hv_fetchs(th, "boundingBox", 0);
                if (bb_slot && *bb_slot)
                    current_state.boundingBox = clay_bounding_box_from_sv(aTHX_ *bb_slot);
            }
        } else {
            current_state = args.initial;
        }
        args.current = &current_state;

        complete = Clay_EaseOut(args);

        result_hv = newHV();
        hv_stores(result_hv, "complete", complete ? newSVuv(1) : newSVuv(0));
        {
            HV *cur_hv = newHV();
            hv_stores(cur_hv, "boundingBox",
                      clay_bounding_box_to_sv(aTHX_ current_state.boundingBox));
            hv_stores(cur_hv, "backgroundColor",
                      clay_color_to_sv(aTHX_ current_state.backgroundColor));
            hv_stores(cur_hv, "overlayColor",
                      clay_color_to_sv(aTHX_ current_state.overlayColor));
            hv_stores(cur_hv, "borderColor",
                      clay_color_to_sv(aTHX_ current_state.borderColor));
            hv_stores(cur_hv, "borderWidth",
                      clay_border_width_to_sv(aTHX_ current_state.borderWidth));
            hv_stores(result_hv, "current", newRV_noinc((SV *) cur_hv));
        }
        RETVAL = newRV_noinc((SV *) result_hv);
    OUTPUT:
        RETVAL

# =============================================================================
# Phase 10 helpers: install per-context transition callbacks.
# =============================================================================

void
xs_Clay_SetTransitionHandlers(handler_sv = &PL_sv_undef, set_initial_sv = &PL_sv_undef, set_final_sv = &PL_sv_undef, userdata_sv = &PL_sv_undef)
        SV *handler_sv
        SV *set_initial_sv
        SV *set_final_sv
        SV *userdata_sv
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = get_current_ctx(aTHX);
        clay_perl_set_transition_handler(aTHX_ ctx, handler_sv, set_initial_sv, set_final_sv, userdata_sv);

# =============================================================================
# Phase 2.4: sizing helpers (replacements for CLAY_SIZING_* macros).
# =============================================================================

SV *
xs_sizing_fit(min = 0.0, max = 0.0)
        double min
        double max
    PREINIT:
        Clay_SizingAxis axis;
    CODE:
        memset(&axis, 0, sizeof(axis));
        axis.type = CLAY__SIZING_TYPE_FIT;
        axis.size.minMax.min = (float) min;
        axis.size.minMax.max = (float) max;
        RETVAL = clay_sizing_axis_to_sv(aTHX_ axis);
    OUTPUT:
        RETVAL

SV *
xs_sizing_grow(min = 0.0, max = 0.0)
        double min
        double max
    PREINIT:
        Clay_SizingAxis axis;
    CODE:
        memset(&axis, 0, sizeof(axis));
        axis.type = CLAY__SIZING_TYPE_GROW;
        axis.size.minMax.min = (float) min;
        axis.size.minMax.max = (float) max;
        RETVAL = clay_sizing_axis_to_sv(aTHX_ axis);
    OUTPUT:
        RETVAL

SV *
xs_sizing_fixed(size)
        double size
    PREINIT:
        Clay_SizingAxis axis;
    CODE:
        memset(&axis, 0, sizeof(axis));
        axis.type = CLAY__SIZING_TYPE_FIXED;
        axis.size.minMax.min = (float) size;
        axis.size.minMax.max = (float) size;
        RETVAL = clay_sizing_axis_to_sv(aTHX_ axis);
    OUTPUT:
        RETVAL

SV *
xs_sizing_percent(percent)
        double percent
    PREINIT:
        Clay_SizingAxis axis;
    CODE:
        memset(&axis, 0, sizeof(axis));
        axis.type = CLAY__SIZING_TYPE_PERCENT;
        axis.size.percent = (float) percent;
        RETVAL = clay_sizing_axis_to_sv(aTHX_ axis);
    OUTPUT:
        RETVAL

SV *
xs_padding_all(value)
        UV value
    PREINIT:
        Clay_Padding p;
    CODE:
        p.left = p.right = p.top = p.bottom = (uint16_t) value;
        RETVAL = clay_padding_to_sv(aTHX_ p);
    OUTPUT:
        RETVAL

SV *
xs_border_all(width)
        UV width
    PREINIT:
        Clay_BorderWidth w;
    CODE:
        w.left = w.right = w.top = w.bottom = w.betweenChildren = (uint16_t) width;
        RETVAL = clay_border_width_to_sv(aTHX_ w);
    OUTPUT:
        RETVAL

SV *
xs_border_outside(width)
        UV width
    PREINIT:
        Clay_BorderWidth w;
    CODE:
        w.left = w.right = w.top = w.bottom = (uint16_t) width;
        w.betweenChildren = 0;
        RETVAL = clay_border_width_to_sv(aTHX_ w);
    OUTPUT:
        RETVAL

SV *
xs_corner_radius_all(radius)
        double radius
    PREINIT:
        Clay_CornerRadius r;
    CODE:
        r.topLeft = r.topRight = r.bottomLeft = r.bottomRight = (float) radius;
        RETVAL = clay_corner_radius_to_sv(aTHX_ r);
    OUTPUT:
        RETVAL

# =============================================================================
# Lifecycle: explicit free hook for the context.
# =============================================================================

MODULE = Clay::XS    PACKAGE = Clay::XS::Context    PREFIX = xs_ctx_

void
xs_ctx_DESTROY(self_sv)
        SV *self_sv
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = clay_perl_context_from_sv(aTHX_ self_sv);
        /* If Clay still thinks this context is current, clear its global
         * pointer first. Otherwise the next Clay_Initialize will read
         * freed memory when it inspects "oldContext" for default
         * propagation. See src/clay/clay.h:4192. */
        if (Clay_GetCurrentContext() == ctx->clay_ctx) {
            Clay_SetCurrentContext(NULL);
        }
        if (clay_perl_current_ctx == ctx) {
            clay_perl_current_ctx = NULL;
        }
        clay_perl_context_free(aTHX_ ctx);
