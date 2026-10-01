/*
 * XS.xs - The XS surface for Clay::XS.
 *
 * Every public Clay v0.14 function (except
 * Clay_CreateArenaWithCapacityAndMemory: Clay_Initialize allocates and owns
 * the arena) and the internal Clay__ functions the C macros expand to are
 * exposed under their exact C names. The
 * Perl-side module re-exports these and adds a handful of snake_case
 * helpers for macros that don't translate (CLAY_SIZING_FIT etc.) and for
 * C idioms that need a pointer (set_scroll_position).
 *
 * Boundary marshalling lives in src/marshal.c; trampolines for
 * function-pointer callbacks live in src/callbacks.c; the context, its
 * string arena and the id intern table live in src/clay_perl_context.c.
 *
 * Memory ownership notes are in src/clay_perl.h. The cliffs notes are:
 *
 *   - Clay_Initialize allocates the underlying Clay arena and stores it
 *     in a clay_perl_context that the Perl side holds via a blessed
 *     reference. DESTROY frees everything.
 *
 *   - Text passed to Clay is copied into the context's string arena;
 *     element id strings are interned. The caller never needs to keep
 *     input strings alive.
 *
 *   - Every wrapper that touches Clay state first checks for a usable
 *     current context (require_context), so a missing, destroyed or
 *     foreign context croaks instead of crashing inside Clay.
 *
 *   - Open/close balance is tracked per context: closing or configuring
 *     with nothing open croaks, and Clay_EndLayout closes any element
 *     left open (so Clay's state stays consistent), then croaks.
 *
 *   - Exceptions thrown by Perl callbacks while Clay runs are deferred
 *     (src/callbacks.c) and re-thrown by the wrapper once Clay has
 *     returned. The element-construction wrappers never re-throw deferred
 *     errors (Clay_EndLayout does), so callers can keep open/close
 *     balanced.
 */

#include "src/clay_perl.h"

#include <string.h>

/* ===========================================================================
 * BOOT helper: install integer constants under Clay::XS::.
 * ======================================================================== */

static void install_iv_const(pTHX_ const char *name, IV value)
{
    newCONSTSUB(gv_stashpvs("Clay::XS", GV_ADD), name, newSViv(value));
}

/* ===========================================================================
 * Context guards.
 *
 * clay_perl_current_ctx mirrors Clay's process-wide current context. The
 * guard croaks unless it is set, belongs to this interpreter and - with
 * GUARD_COUNTS - still has the element / measure-cache word counts
 * Clay_Initialize sized its arena for (Clay keeps its persistent arrays at
 * those sizes and indexes some of them without range checks).
 *
 * While a Clay callback runs (clay_perl_callback_depth > 0) Clay is in the
 * middle of one of its own functions: GUARD_MUTATES wrappers - everything
 * that changes Clay's state or current context - croak then. The croak
 * lands in the trampoline's eval and is re-thrown by the wrapper that
 * called into Clay. Queries that only read finished state stay allowed.
 *
 * The guard also pins the context until the calling statement ends, so a
 * callback that drops the last reference to it cannot free it while Clay
 * is still using it.
 * ======================================================================== */

#define GUARD_COUNTS  0x1
#define GUARD_MUTATES 0x2

static void forbid_in_callback(pTHX_ const char *func)
{
    if (clay_perl_callback_depth > 0) {
        croak("%s: cannot be called from inside a Clay callback", func);
    }
}

static void pin_context(pTHX_ clay_perl_context *ctx)
{
    if (ctx && ctx->referent) {
        sv_2mortal(SvREFCNT_inc_simple_NN(ctx->referent));
    }
}

static clay_perl_context *require_context(pTHX_ const char *func, int guards)
{
    if (guards & GUARD_MUTATES) forbid_in_callback(aTHX_ func);
    clay_perl_context *ctx = clay_perl_current_ctx;
    if (!ctx || !ctx->clay_ctx) {
        croak("%s: no current Clay context; call Clay_Initialize first", func);
    }
    if (ctx->owner != CLAY_PERL_THIS_INTERPRETER) {
        croak("%s: Clay::XS context used from a different interpreter/thread", func);
    }
    if ((guards & GUARD_COUNTS)
        && (Clay_GetMaxElementCount() != ctx->max_element_count
            || Clay_GetMaxMeasureTextCacheWordCount() != ctx->max_measure_text_cache_word_count)) {
        croak("%s: element/word counts changed since Clay_Initialize; call Clay_Initialize again", func);
    }
    pin_context(aTHX_ ctx);
    return ctx;
}

/* Wrappers that change Clay's state. */
#define REQUIRE_CONTEXT(func) require_context(aTHX_ (func), GUARD_COUNTS | GUARD_MUTATES)

/* Read-only queries, allowed inside callbacks. */
#define REQUIRE_CONTEXT_QUERY(func) require_context(aTHX_ (func), GUARD_COUNTS)

static void require_frame(pTHX_ clay_perl_context *ctx, const char *func)
{
    if (!ctx->in_frame) {
        croak("%s: called outside Clay_BeginLayout/Clay_EndLayout", func);
    }
}

static void require_open_element(pTHX_ clay_perl_context *ctx, const char *func)
{
    if (ctx->open_depth == 0) {
        croak("%s: no element is open (unbalanced Clay__OpenElement/Clay__CloseElement)", func);
    }
}

/* ===========================================================================
 * Capacity validation shared by Clay_Initialize and the count setters.
 * ======================================================================== */

#define MIN_MEASURE_TEXT_CACHE_WORDS 32

/* Clay's arena size arithmetic is 32-bit and wraps silently; counts whose
 * arena would not fit 4 GiB corrupt memory instead of failing. */
static void require_counts_fit(pTHX_ const char *func, int32_t element_count, int32_t word_count)
{
    uint64_t needed = clay_perl_clay_arena_bytes_upper_bound(element_count, word_count);
    if (needed > (uint64_t) UINT32_MAX) {
        croak("%s: %d elements and %d measure-cache words need about %.0f bytes of arena; "
              "Clay's arena arithmetic is limited to 4 GiB",
              func, (int) element_count, (int) word_count, (double) needed);
    }
}

/* The counts Clay_MinMemorySize and the next Clay_Initialize use: those of
 * Clay's current context, or Clay's defaults when there is none. */
static void configured_counts(int32_t *element_count, int32_t *word_count)
{
    if (Clay_GetCurrentContext()) {
        *element_count = Clay_GetMaxElementCount();
        *word_count    = Clay_GetMaxMeasureTextCacheWordCount();
    } else {
        clay_perl_clay_default_counts(element_count, word_count);
    }
}

static int32_t parse_count(pTHX_ SV *sv, const char *func, int32_t minimum)
{
    return (int32_t) clay_perl_parse_integer(aTHX_ sv, func, (NV) minimum, (NV) INT32_MAX);
}

/* The capacity argument of Clay_Initialize: a non-negative integer of at
 * least Clay_MinMemorySize() bytes. */
static size_t parse_capacity(pTHX_ SV *sv)
{
    SvGETMAGIC(sv);
    NV bytes = (SvOK(sv) && (!SvROK(sv) || SvAMAGIC(sv)) && looks_like_number(sv))
             ? SvNV_nomg(sv) : -1;
    if (!(bytes >= 0) || bytes != Perl_floor(bytes) || bytes > (NV) SIZE_MAX) {
        croak("Clay_Initialize: capacity must be a non-negative integer number of bytes, got '%" SVf "'",
              SVfARG(sv));
    }
    uint32_t minimum = Clay_MinMemorySize();
    if (bytes < (NV) minimum) {
        croak("Clay_Initialize: capacity %.0f is below Clay_MinMemorySize() = %u bytes",
              (double) bytes, (unsigned) minimum);
    }
    return (size_t) bytes;
}

/* ===========================================================================
 * Element ids.
 * ======================================================================== */

/* The UTF-8 bytes of an id string; croaks for undef. */
static const char *id_string_bytes(pTHX_ SV *sv, const char *func, STRLEN *len)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) croak("%s: element id string must be defined", func);
    return SvPVutf8_nomg(sv, *len);
}

/* A Clay_String over the SV's own buffer, for hashing only: Clay's hash
 * functions do not keep it, and the returned stringId is copied out at
 * once by clay_element_id_to_sv. */
static Clay_String borrowed_id_string(pTHX_ SV *sv, const char *func)
{
    STRLEN len;
    const char *bytes = id_string_bytes(aTHX_ sv, func, &len);
    if (len > (STRLEN) INT32_MAX) {
        croak("%s: element id length %" UVuf " exceeds INT32_MAX", func, (UV) len);
    }
    Clay_String s = { false, (int32_t) len, bytes };
    return s;
}

/* ===========================================================================
 * Clay_EndLayout helpers.
 * ======================================================================== */

/* Croaks for elements left open at Clay_EndLayout, appending a deferred
 * callback error when one is pending as well. */
static void croak_unbalanced(pTHX_ clay_perl_context *ctx, int32_t still_open)
{
    SV *message = sv_2mortal(newSVpvf(
        "%d element%s still open at Clay_EndLayout "
        "(unbalanced Clay__OpenElement/Clay__CloseElement)",
        (int) still_open, still_open == 1 ? "" : "s"));
    SV *pending = clay_perl_take_pending_error(aTHX_ ctx, NULL);
    if (pending) {
        sv_catpvs(message, "; callback error: ");
        sv_catsv(message, pending);
    }
    croak_sv(message);
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
    install_iv_const(aTHX_ "CLAY_ERROR_TYPE_SIZING_GROUP_CYCLE",                     CLAY_ERROR_TYPE_SIZING_GROUP_CYCLE);
}

# =============================================================================
# Core lifecycle.
# =============================================================================

uint32_t
xs_Clay_MinMemorySize()
    PREINIT:
        int32_t element_count;
        int32_t word_count;
    CODE:
        configured_counts(&element_count, &word_count);
        require_counts_fit(aTHX_ "Clay_MinMemorySize", element_count, word_count);
        RETVAL = Clay_MinMemorySize();
    OUTPUT:
        RETVAL

SV *
xs_Clay_Initialize(capacity_sv, dimensions_sv, error_handler_sv = &PL_sv_undef, error_userdata_sv = &PL_sv_undef)
        SV *capacity_sv
        SV *dimensions_sv
        SV *error_handler_sv
        SV *error_userdata_sv
    PREINIT:
        clay_perl_context *ctx;
        clay_perl_context *previous_ctx;
        Clay_Context *previous_clay;
        Clay_Dimensions dim;
        Clay_ErrorHandler handler;
        SV *error_handler;
        size_t capacity;
        int32_t element_count;
        int32_t word_count;
        SV *failure;
    CODE:
        forbid_in_callback(aTHX_ "Clay_Initialize");
        previous_ctx = clay_perl_current_ctx;
        if (previous_ctx && previous_ctx->owner != CLAY_PERL_THIS_INTERPRETER) {
            croak("Clay_Initialize: Clay::XS context used from a different interpreter/thread");
        }
        /* It is restored if initialisation fails. */
        pin_context(aTHX_ previous_ctx);
        previous_clay = Clay_GetCurrentContext();
        configured_counts(&element_count, &word_count);
        require_counts_fit(aTHX_ "Clay_Initialize", element_count, word_count);
        if (word_count / MIN_MEASURE_TEXT_CACHE_WORDS > element_count) {
            croak("Clay_Initialize: %d measure-cache words need %d hash buckets but only %d elements "
                  "are configured; Clay would index its measure cache out of bounds",
                  (int) word_count, (int) (word_count / MIN_MEASURE_TEXT_CACHE_WORDS), (int) element_count);
        }

        capacity      = parse_capacity(aTHX_ capacity_sv);
        dim           = clay_dimensions_from_sv(aTHX_ dimensions_sv, "Clay_Initialize: dimensions");
        error_handler = clay_perl_require_code(aTHX_ error_handler_sv, "Clay_Initialize: error handler", true);
        if (!get_cv("Clay::XS::_dispatch", 0)) {
            croak("Clay_Initialize: internal error: Clay::XS::_dispatch is not defined");
        }

        ctx = clay_perl_context_new(aTHX_ capacity);
        if (!ctx) {
            croak("Clay_Initialize: cannot allocate %" UVuf " bytes", (UV) capacity);
        }
        clay_perl_replace_sv_slot(aTHX_ &ctx->error_handler_cb, error_handler);
        clay_perl_replace_sv_slot(aTHX_ &ctx->error_handler_userdata, error_userdata_sv);

        handler.errorHandlerFunction = clay_perl_error_handler_trampoline;
        handler.userData             = ctx;
        ctx->clay_ctx = Clay_Initialize(ctx->clay_arena, dim, handler);

        failure = NULL;
        if (!ctx->clay_ctx) {
            failure = sv_2mortal(newSVpvs("Clay_Initialize: Clay could not create a context in the arena"));
        } else {
            ctx->max_element_count                 = Clay_GetMaxElementCount();
            ctx->max_measure_text_cache_word_count = Clay_GetMaxMeasureTextCacheWordCount();
            clay_perl_current_ctx = ctx;
            failure = clay_perl_take_pending_error(aTHX_ ctx, NULL);
        }
        if (failure) {
            Clay_SetCurrentContext(previous_clay);
            clay_perl_current_ctx = previous_ctx;
            clay_perl_context_free(aTHX_ ctx);
            croak_sv(failure);
        }
        RETVAL = clay_perl_context_bless(aTHX_ ctx);
    OUTPUT:
        RETVAL

void
xs_Clay_SetCurrentContext(ctx_sv)
        SV *ctx_sv
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        forbid_in_callback(aTHX_ "Clay_SetCurrentContext");
        ctx = clay_perl_context_from_sv(aTHX_ ctx_sv);
        if (ctx->owner != CLAY_PERL_THIS_INTERPRETER) {
            croak("Clay_SetCurrentContext: Clay::XS context used from a different interpreter/thread");
        }
        Clay_SetCurrentContext(ctx->clay_ctx);
        clay_perl_current_ctx = ctx;

SV *
xs_Clay_GetCurrentContext()
    CODE:
        if (!clay_perl_current_ctx) {
            RETVAL = &PL_sv_undef;
        } else {
            RETVAL = clay_perl_context_to_sv(aTHX_ require_context(aTHX_ "Clay_GetCurrentContext", 0));
        }
    OUTPUT:
        RETVAL

void
xs_Clay_SetLayoutDimensions(dimensions_sv)
        SV *dimensions_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_Dimensions dim;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_SetLayoutDimensions");
        dim = clay_dimensions_from_sv(aTHX_ dimensions_sv, "Clay_SetLayoutDimensions: dimensions");
        Clay_SetLayoutDimensions(dim);
        clay_perl_raise_pending_error(aTHX_ ctx);

SV *
xs_Clay_GetLayoutDimensions()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT_QUERY("Clay_GetLayoutDimensions");
        clay_perl_raise_pending_error(aTHX_ ctx);
        RETVAL = clay_dimensions_to_sv(aTHX_ Clay_GetLayoutDimensions());
    OUTPUT:
        RETVAL

void
xs_Clay_BeginLayout()
    PREINIT:
        clay_perl_context *ctx;
        SV *leftover;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_BeginLayout");
        leftover = clay_perl_take_pending_error(aTHX_ ctx, " (from the previous unfinished frame)");
        if (leftover) {
            ctx->in_frame   = false;
            ctx->open_depth = 0;
            croak_sv(leftover);
        }
        clay_perl_context_begin_frame(aTHX_ ctx);
        Clay_BeginLayout();
        ctx->in_frame   = true;
        ctx->open_depth = 0;

SV *
xs_Clay_EndLayout(delta_time_sv = &PL_sv_undef)
        SV *delta_time_sv
    PREINIT:
        clay_perl_context *ctx;
        clay_perl_context *outer_transition_ctx;
        Clay_RenderCommandArray cmds;
        float delta_time;
        int32_t still_open;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_EndLayout");
        if (!ctx->in_frame) {
            croak("Clay_EndLayout: called without a matching Clay_BeginLayout");
        }
        delta_time = SvOK(delta_time_sv)
                   ? (float) clay_perl_parse_float(aTHX_ delta_time_sv, "Clay_EndLayout: deltaTime")
                   : 0.0f;
        still_open = ctx->open_depth;
        ctx->in_frame   = false;
        ctx->open_depth = 0;
        for (int32_t i = 0; i < still_open; i++) {
            Clay__CloseElement();
        }

        outer_transition_ctx = clay_perl_active_transition_ctx;
        clay_perl_active_transition_ctx = ctx;
        cmds = Clay_EndLayout(delta_time);
        clay_perl_active_transition_ctx = outer_transition_ctx;

        if (still_open > 0) {
            croak_unbalanced(aTHX_ ctx, still_open);
        }
        clay_perl_raise_pending_error(aTHX_ ctx);
        RETVAL = clay_render_command_array_to_sv(aTHX_ &cmds);
    OUTPUT:
        RETVAL

# =============================================================================
# Element open/close. These never re-throw deferred callback errors; see the
# file header.
# =============================================================================

void
xs_Clay__OpenElement()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay__OpenElement");
        require_frame(aTHX_ ctx, "Clay__OpenElement");
        Clay__OpenElement();
        ctx->open_depth++;

void
xs_Clay__OpenElementWithId(id_sv)
        SV *id_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_ElementId id;
        SV **string_slot;
        STRLEN len;
        const char *bytes;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay__OpenElementWithId");
        require_frame(aTHX_ ctx, "Clay__OpenElementWithId");
        id = clay_element_id_from_sv(aTHX_ id_sv, "Clay__OpenElementWithId: element id");
        string_slot = hv_fetchs((HV *) SvRV(id_sv), "stringId", 0);
        if (string_slot && *string_slot) {
            SvGETMAGIC(*string_slot);
            if (SvOK(*string_slot)) {
                bytes = SvPVutf8_nomg(*string_slot, len);
                id.stringId = clay_perl_intern_id(aTHX_ ctx, bytes, len);
            }
        }
        Clay__OpenElementWithId(id);
        ctx->open_depth++;

void
xs_Clay__CloseElement()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay__CloseElement");
        require_open_element(aTHX_ ctx, "Clay__CloseElement");
        Clay__CloseElement();
        ctx->open_depth--;

void
xs_Clay__ConfigureOpenElement(decl_sv)
        SV *decl_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_ElementDeclaration decl;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay__ConfigureOpenElement");
        require_open_element(aTHX_ ctx, "Clay__ConfigureOpenElement");
        decl = clay_element_declaration_from_sv(aTHX_ decl_sv);
        Clay__ConfigureOpenElement(decl);

void
xs_Clay__OpenTextElement(text_sv, config_sv = &PL_sv_undef)
        SV *text_sv
        SV *config_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_String text;
        Clay_TextElementConfig config;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay__OpenTextElement");
        require_frame(aTHX_ ctx, "Clay__OpenTextElement");
        config = clay_text_element_config_from_sv(aTHX_ config_sv);
        text = clay_perl_arena_copy_text(aTHX_ ctx, text_sv, "Clay__OpenTextElement");
        Clay__OpenTextElement(text, config);

# =============================================================================
# Element ids. Hashing needs no context.
# =============================================================================

SV *
xs_Clay__HashString(key_sv, seed_sv = &PL_sv_undef)
        SV *key_sv
        SV *seed_sv
    PREINIT:
        Clay_String key;
        uint32_t seed;
    CODE:
        key  = borrowed_id_string(aTHX_ key_sv, "Clay__HashString");
        seed = SvOK(seed_sv) ? (uint32_t) clay_perl_parse_uint(aTHX_ seed_sv, "Clay__HashString: seed", UINT32_MAX) : 0;
        RETVAL = clay_element_id_to_sv(aTHX_ Clay__HashString(key, seed));
    OUTPUT:
        RETVAL

SV *
xs_Clay__HashStringWithOffset(key_sv, offset_sv, seed_sv = &PL_sv_undef)
        SV *key_sv
        SV *offset_sv
        SV *seed_sv
    PREINIT:
        Clay_String key;
        uint32_t offset;
        uint32_t seed;
    CODE:
        key    = borrowed_id_string(aTHX_ key_sv, "Clay__HashStringWithOffset");
        offset = (uint32_t) clay_perl_parse_uint(aTHX_ offset_sv, "Clay__HashStringWithOffset: offset", UINT32_MAX);
        seed   = SvOK(seed_sv) ? (uint32_t) clay_perl_parse_uint(aTHX_ seed_sv, "Clay__HashStringWithOffset: seed", UINT32_MAX) : 0;
        RETVAL = clay_element_id_to_sv(aTHX_ Clay__HashStringWithOffset(key, offset, seed));
    OUTPUT:
        RETVAL

SV *
xs_Clay_GetElementId(id_string_sv)
        SV *id_string_sv
    CODE:
        RETVAL = clay_element_id_to_sv(aTHX_
            Clay_GetElementId(borrowed_id_string(aTHX_ id_string_sv, "Clay_GetElementId")));
    OUTPUT:
        RETVAL

SV *
xs_Clay_GetElementIdWithIndex(id_string_sv, index_sv)
        SV *id_string_sv
        SV *index_sv
    PREINIT:
        Clay_String s;
        uint32_t index;
    CODE:
        s     = borrowed_id_string(aTHX_ id_string_sv, "Clay_GetElementIdWithIndex");
        index = (uint32_t) clay_perl_parse_uint(aTHX_ index_sv, "Clay_GetElementIdWithIndex: index", UINT32_MAX);
        RETVAL = clay_element_id_to_sv(aTHX_ Clay_GetElementIdWithIndex(s, index));
    OUTPUT:
        RETVAL

UV
xs_Clay_GetOpenElementId()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_GetOpenElementId");
        require_frame(aTHX_ ctx, "Clay_GetOpenElementId");
        RETVAL = (UV) Clay_GetOpenElementId();
    OUTPUT:
        RETVAL

SV *
xs_Clay_GetElementData(id_sv)
        SV *id_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_ElementId id;
        Clay_ElementData data;
    CODE:
        ctx  = REQUIRE_CONTEXT_QUERY("Clay_GetElementData");
        id   = clay_element_id_from_sv(aTHX_ id_sv, "Clay_GetElementData: element id");
        data = Clay_GetElementData(id);
        clay_perl_raise_pending_error(aTHX_ ctx);
        RETVAL = clay_element_data_to_sv(aTHX_ data);
    OUTPUT:
        RETVAL

# =============================================================================
# Text measurement.
# =============================================================================

void
xs_Clay_SetMeasureTextFunction(cb_sv, userdata_sv = &PL_sv_undef)
        SV *cb_sv
        SV *userdata_sv
    PREINIT:
        clay_perl_context *ctx;
        SV *cb;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_SetMeasureTextFunction");
        cb  = clay_perl_require_code(aTHX_ cb_sv, "Clay_SetMeasureTextFunction: callback", true);
        clay_perl_replace_sv_slot(aTHX_ &ctx->measure_text_cb, cb);
        clay_perl_replace_sv_slot(aTHX_ &ctx->measure_text_userdata, userdata_sv);
        Clay_SetMeasureTextFunction(clay_perl_measure_text_trampoline, ctx);
        clay_perl_raise_pending_error(aTHX_ ctx);

void
xs_Clay_ResetMeasureTextCache()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_ResetMeasureTextCache");
        Clay_ResetMeasureTextCache();
        clay_perl_raise_pending_error(aTHX_ ctx);

# =============================================================================
# Pointer & interaction.
# =============================================================================

void
xs_Clay_SetPointerState(position_sv, pointerDown)
        SV *position_sv
        bool pointerDown
    PREINIT:
        clay_perl_context *ctx;
        Clay_Vector2 pos;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_SetPointerState");
        pos = clay_vector2_from_sv(aTHX_ position_sv, "Clay_SetPointerState: position");
        Clay_SetPointerState(pos, pointerDown);
        clay_perl_raise_pending_error(aTHX_ ctx);

SV *
xs_Clay_GetPointerState()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT_QUERY("Clay_GetPointerState");
        clay_perl_raise_pending_error(aTHX_ ctx);
        RETVAL = clay_pointer_data_to_sv(aTHX_ Clay_GetPointerState());
    OUTPUT:
        RETVAL

bool
xs_Clay_Hovered()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_Hovered");
        require_frame(aTHX_ ctx, "Clay_Hovered");
        RETVAL = Clay_Hovered();
    OUTPUT:
        RETVAL

void
xs_Clay_OnHover(cb_sv, userdata_sv = &PL_sv_undef)
        SV *cb_sv
        SV *userdata_sv
    PREINIT:
        clay_perl_context *ctx;
        SV *cb;
        uint32_t open_id;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_OnHover");
        require_open_element(aTHX_ ctx, "Clay_OnHover");
        cb = clay_perl_require_code(aTHX_ cb_sv, "Clay_OnHover: callback", false);
        open_id = Clay_GetOpenElementId();
        if (open_id == 0) {
            croak("Clay_OnHover: the open element has no id");
        }
        clay_perl_hover_register(aTHX_ ctx, open_id, cb, userdata_sv);
        Clay_OnHover(clay_perl_on_hover_trampoline, ctx);

bool
xs_Clay_PointerOver(id_sv)
        SV *id_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_ElementId id;
    CODE:
        ctx = REQUIRE_CONTEXT_QUERY("Clay_PointerOver");
        id  = clay_element_id_from_sv(aTHX_ id_sv, "Clay_PointerOver: element id");
        RETVAL = Clay_PointerOver(id);
        clay_perl_raise_pending_error(aTHX_ ctx);
    OUTPUT:
        RETVAL

SV *
xs_Clay_GetPointerOverIds()
    PREINIT:
        clay_perl_context *ctx;
        Clay_ElementIdArray ids;
        AV *av;
        int32_t i;
    CODE:
        ctx = REQUIRE_CONTEXT_QUERY("Clay_GetPointerOverIds");
        clay_perl_raise_pending_error(aTHX_ ctx);
        ids = Clay_GetPointerOverIds();
        av  = newAV();
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
# Scroll support.
# =============================================================================

void
xs_Clay_UpdateScrollContainers(enable_drag_scrolling, scroll_delta_sv, delta_time_sv)
        bool enable_drag_scrolling
        SV *scroll_delta_sv
        SV *delta_time_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_Vector2 delta;
        float delta_time;
    CODE:
        ctx        = REQUIRE_CONTEXT("Clay_UpdateScrollContainers");
        delta      = clay_vector2_from_sv(aTHX_ scroll_delta_sv, "Clay_UpdateScrollContainers: scrollDelta");
        delta_time = (float) clay_perl_parse_float(aTHX_ delta_time_sv, "Clay_UpdateScrollContainers: deltaTime");
        Clay_UpdateScrollContainers(enable_drag_scrolling, delta, delta_time);
        clay_perl_raise_pending_error(aTHX_ ctx);

SV *
xs_Clay_GetScrollOffset()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_GetScrollOffset");
        require_frame(aTHX_ ctx, "Clay_GetScrollOffset");
        RETVAL = clay_vector2_to_sv(aTHX_ Clay_GetScrollOffset());
    OUTPUT:
        RETVAL

SV *
xs_Clay_GetScrollContainerData(id_sv)
        SV *id_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_ElementId id;
        Clay_ScrollContainerData data;
    CODE:
        ctx  = REQUIRE_CONTEXT_QUERY("Clay_GetScrollContainerData");
        id   = clay_element_id_from_sv(aTHX_ id_sv, "Clay_GetScrollContainerData: element id");
        data = Clay_GetScrollContainerData(id);
        clay_perl_raise_pending_error(aTHX_ ctx);
        RETVAL = clay_scroll_container_data_to_sv(aTHX_ data);
    OUTPUT:
        RETVAL

void
xs_Clay_SetQueryScrollOffsetFunction(cb_sv, userdata_sv = &PL_sv_undef)
        SV *cb_sv
        SV *userdata_sv
    PREINIT:
        clay_perl_context *ctx;
        SV *cb;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_SetQueryScrollOffsetFunction");
        cb  = clay_perl_require_code(aTHX_ cb_sv, "Clay_SetQueryScrollOffsetFunction: callback", true);
        clay_perl_replace_sv_slot(aTHX_ &ctx->query_scroll_offset_cb, cb);
        clay_perl_replace_sv_slot(aTHX_ &ctx->query_scroll_offset_userdata, userdata_sv);
        Clay_SetQueryScrollOffsetFunction(clay_perl_query_scroll_offset_trampoline, ctx);
        clay_perl_raise_pending_error(aTHX_ ctx);

void
xs_Clay_SetExternalScrollHandlingEnabled(enabled)
        bool enabled
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_SetExternalScrollHandlingEnabled");
        if (enabled && !ctx->query_scroll_offset_cb) {
            croak("Clay_SetExternalScrollHandlingEnabled: install a function with "
                  "Clay_SetQueryScrollOffsetFunction first");
        }
        /* Clay calls its global query function without a NULL check while
         * external handling is on; make sure it is ours. */
        Clay_SetQueryScrollOffsetFunction(clay_perl_query_scroll_offset_trampoline, ctx);
        Clay_SetExternalScrollHandlingEnabled(enabled);
        clay_perl_raise_pending_error(aTHX_ ctx);

void
xs_set_scroll_position(id_sv, position_sv)
        SV *id_sv
        SV *position_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_ElementId id;
        Clay_Vector2 position;
        Clay_ScrollContainerData data;
    CODE:
        ctx      = REQUIRE_CONTEXT("set_scroll_position");
        id       = clay_element_id_from_sv(aTHX_ id_sv, "set_scroll_position: element id");
        position = clay_vector2_from_sv(aTHX_ position_sv, "set_scroll_position: position");
        data     = Clay_GetScrollContainerData(id);
        if (!data.found || !data.scrollPosition) {
            croak("set_scroll_position: element %u is not a known scroll container "
                  "(declare it with clip enabled and complete a frame first)", (unsigned) id.id);
        }
        *data.scrollPosition = position;
        clay_perl_raise_pending_error(aTHX_ ctx);

# Check mode: needs no context and never calls into Clay.
void
xs_check_struct(type, value, root_sv = &PL_sv_undef)
        const char *type
        SV *value
        SV *root_sv
    CODE:
        SvGETMAGIC(root_sv);
        clay_perl_check_struct(aTHX_ type, value, SvOK(root_sv) ? SvPV_nomg_nolen(root_sv) : NULL);

# =============================================================================
# Debug, culling, capacity, ease helper.
# =============================================================================

void
xs_Clay_SetDebugModeEnabled(enabled)
        bool enabled
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_SetDebugModeEnabled");
        Clay_SetDebugModeEnabled(enabled);
        clay_perl_raise_pending_error(aTHX_ ctx);

bool
xs_Clay_IsDebugModeEnabled()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT_QUERY("Clay_IsDebugModeEnabled");
        clay_perl_raise_pending_error(aTHX_ ctx);
        RETVAL = Clay_IsDebugModeEnabled();
    OUTPUT:
        RETVAL

void
xs_Clay_SetCullingEnabled(enabled)
        bool enabled
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = REQUIRE_CONTEXT("Clay_SetCullingEnabled");
        Clay_SetCullingEnabled(enabled);
        clay_perl_raise_pending_error(aTHX_ ctx);

IV
xs_Clay_GetMaxElementCount()
    CODE:
        (void) require_context(aTHX_ "Clay_GetMaxElementCount", 0);
        RETVAL = (IV) Clay_GetMaxElementCount();
    OUTPUT:
        RETVAL

void
xs_Clay_SetMaxElementCount(count_sv)
        SV *count_sv
    PREINIT:
        int32_t count;
    CODE:
        forbid_in_callback(aTHX_ "Clay_SetMaxElementCount");
        count = parse_count(aTHX_ count_sv, "Clay_SetMaxElementCount", 1);
        if (!clay_perl_current_ctx) {
            /* Clay derives the default word count from the element count. */
            if (count > INT32_MAX / 2) {
                croak("Clay_SetMaxElementCount: %d elements would overflow Clay's default "
                      "measure-cache word count (2 x elements)", (int) count);
            }
            require_counts_fit(aTHX_ "Clay_SetMaxElementCount", count, count * 2);
        } else {
            (void) require_context(aTHX_ "Clay_SetMaxElementCount", GUARD_MUTATES);
            require_counts_fit(aTHX_ "Clay_SetMaxElementCount", count, Clay_GetMaxMeasureTextCacheWordCount());
        }
        Clay_SetMaxElementCount(count);

IV
xs_Clay_GetMaxMeasureTextCacheWordCount()
    CODE:
        (void) require_context(aTHX_ "Clay_GetMaxMeasureTextCacheWordCount", 0);
        RETVAL = (IV) Clay_GetMaxMeasureTextCacheWordCount();
    OUTPUT:
        RETVAL

void
xs_Clay_SetMaxMeasureTextCacheWordCount(count_sv)
        SV *count_sv
    PREINIT:
        int32_t count;
        int32_t element_count;
        int32_t unused_word_count;
    CODE:
        forbid_in_callback(aTHX_ "Clay_SetMaxMeasureTextCacheWordCount");
        count = parse_count(aTHX_ count_sv, "Clay_SetMaxMeasureTextCacheWordCount", MIN_MEASURE_TEXT_CACHE_WORDS);
        if (!clay_perl_current_ctx) {
            clay_perl_clay_default_counts(&element_count, &unused_word_count);
        } else {
            (void) require_context(aTHX_ "Clay_SetMaxMeasureTextCacheWordCount", GUARD_MUTATES);
            element_count = Clay_GetMaxElementCount();
        }
        require_counts_fit(aTHX_ "Clay_SetMaxMeasureTextCacheWordCount", element_count, count);
        Clay_SetMaxMeasureTextCacheWordCount(count);

SV *
xs_Clay_EaseOut(args_sv)
        SV *args_sv
    PREINIT:
        Clay_TransitionCallbackArguments args;
        Clay_TransitionData zero;
        Clay_TransitionData current_state;
        HV *hv;
        HV *result_hv;
        SV **slot;
        bool complete;
    CODE:
        SvGETMAGIC(args_sv);
        if (!SvROK(args_sv) || SvTYPE(SvRV(args_sv)) != SVt_PVHV) {
            croak("Clay_EaseOut: expected hash reference");
        }
        hv = (HV *) SvRV(args_sv);
        memset(&args, 0, sizeof(args));
        memset(&zero, 0, sizeof(zero));

        slot = hv_fetchs(hv, "transitionState", 0);
        if (slot && SvOK(*slot)) {
            args.transitionState = (Clay_TransitionState) clay_perl_parse_uint(
                aTHX_ *slot, "Clay_EaseOut: transitionState", CLAY_TRANSITION_STATE_EXITING);
        }
        slot = hv_fetchs(hv, "elapsedTime", 0);
        if (slot && SvOK(*slot)) {
            args.elapsedTime = (float) clay_perl_parse_float(aTHX_ *slot, "Clay_EaseOut: elapsedTime");
        }
        slot = hv_fetchs(hv, "duration", 0);
        if (slot && SvOK(*slot)) {
            args.duration = (float) clay_perl_parse_float(aTHX_ *slot, "Clay_EaseOut: duration");
        }
        slot = hv_fetchs(hv, "properties", 0);
        if (slot && SvOK(*slot)) {
            args.properties = (Clay_TransitionProperty) clay_perl_parse_uint(
                aTHX_ *slot, "Clay_EaseOut: properties",
                CLAY_TRANSITION_PROPERTY_BOUNDING_BOX | CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR
                | CLAY_TRANSITION_PROPERTY_OVERLAY_COLOR | CLAY_TRANSITION_PROPERTY_CORNER_RADIUS
                | CLAY_TRANSITION_PROPERTY_BORDER);
        }

        slot = hv_fetchs(hv, "initial", 0);
        args.initial = clay_transition_data_from_sv(aTHX_ slot ? *slot : NULL, zero, "Clay_EaseOut: initial");
        slot = hv_fetchs(hv, "target", 0);
        args.target  = clay_transition_data_from_sv(aTHX_ slot ? *slot : NULL, zero, "Clay_EaseOut: target");
        slot = hv_fetchs(hv, "current", 0);
        current_state = slot
                      ? clay_transition_data_from_sv(aTHX_ *slot, zero, "Clay_EaseOut: current")
                      : args.initial;
        args.current = &current_state;

        complete = Clay_EaseOut(args);

        result_hv = newHV();
        (void) hv_stores(result_hv, "complete", newSVuv(complete ? 1 : 0));
        (void) hv_stores(result_hv, "current", clay_transition_data_to_sv(aTHX_ current_state));
        RETVAL = newRV_noinc((SV *) result_hv);
    OUTPUT:
        RETVAL

# =============================================================================
# Per-context transition callbacks.
# =============================================================================

void
xs_Clay_SetTransitionHandlers(handler_sv = &PL_sv_undef, set_initial_sv = &PL_sv_undef, set_final_sv = &PL_sv_undef, userdata_sv = &PL_sv_undef)
        SV *handler_sv
        SV *set_initial_sv
        SV *set_final_sv
        SV *userdata_sv
    PREINIT:
        clay_perl_context *ctx;
        SV *handler;
        SV *set_initial;
        SV *set_final;
    CODE:
        ctx         = REQUIRE_CONTEXT("Clay_SetTransitionHandlers");
        handler     = clay_perl_require_code(aTHX_ handler_sv, "Clay_SetTransitionHandlers: handler", true);
        set_initial = clay_perl_require_code(aTHX_ set_initial_sv, "Clay_SetTransitionHandlers: setInitialState", true);
        set_final   = clay_perl_require_code(aTHX_ set_final_sv, "Clay_SetTransitionHandlers: setFinalState", true);
        clay_perl_replace_sv_slot(aTHX_ &ctx->transition_handler_cb,     handler);
        clay_perl_replace_sv_slot(aTHX_ &ctx->transition_set_initial_cb, set_initial);
        clay_perl_replace_sv_slot(aTHX_ &ctx->transition_set_final_cb,   set_final);
        clay_perl_replace_sv_slot(aTHX_ &ctx->transition_userdata,       userdata_sv);
        clay_perl_raise_pending_error(aTHX_ ctx);

# =============================================================================
# Sizing, padding, border and corner helpers (replacements for the
# CLAY_SIZING_* / CLAY_PADDING_ALL / CLAY_BORDER_* / CLAY_CORNER_RADIUS
# macros). Pure; no context needed.
# =============================================================================

SV *
xs_sizing_fit(min_sv = &PL_sv_undef, max_sv = &PL_sv_undef)
        SV *min_sv
        SV *max_sv
    PREINIT:
        Clay_SizingAxis axis;
    CODE:
        memset(&axis, 0, sizeof(axis));
        axis.type = CLAY__SIZING_TYPE_FIT;
        axis.size.minMax.min = SvOK(min_sv) ? (float) clay_perl_parse_float(aTHX_ min_sv, "sizing_fit: min") : 0.0f;
        axis.size.minMax.max = SvOK(max_sv) ? (float) clay_perl_parse_max_float(aTHX_ max_sv, "sizing_fit: max") : 0.0f;
        RETVAL = clay_sizing_axis_to_sv(aTHX_ axis);
    OUTPUT:
        RETVAL

SV *
xs_sizing_grow(min_sv = &PL_sv_undef, max_sv = &PL_sv_undef)
        SV *min_sv
        SV *max_sv
    PREINIT:
        Clay_SizingAxis axis;
    CODE:
        memset(&axis, 0, sizeof(axis));
        axis.type = CLAY__SIZING_TYPE_GROW;
        axis.size.minMax.min = SvOK(min_sv) ? (float) clay_perl_parse_float(aTHX_ min_sv, "sizing_grow: min") : 0.0f;
        axis.size.minMax.max = SvOK(max_sv) ? (float) clay_perl_parse_max_float(aTHX_ max_sv, "sizing_grow: max") : 0.0f;
        RETVAL = clay_sizing_axis_to_sv(aTHX_ axis);
    OUTPUT:
        RETVAL

SV *
xs_sizing_fixed(size_sv)
        SV *size_sv
    PREINIT:
        Clay_SizingAxis axis;
        float size;
    CODE:
        size = (float) clay_perl_parse_float(aTHX_ size_sv, "sizing_fixed: size");
        memset(&axis, 0, sizeof(axis));
        axis.type = CLAY__SIZING_TYPE_FIXED;
        axis.size.minMax.min = size;
        axis.size.minMax.max = size;
        RETVAL = clay_sizing_axis_to_sv(aTHX_ axis);
    OUTPUT:
        RETVAL

SV *
xs_sizing_percent(percent_sv)
        SV *percent_sv
    PREINIT:
        Clay_SizingAxis axis;
    CODE:
        memset(&axis, 0, sizeof(axis));
        axis.type = CLAY__SIZING_TYPE_PERCENT;
        axis.size.percent = (float) clay_perl_parse_float(aTHX_ percent_sv, "sizing_percent: percent");
        RETVAL = clay_sizing_axis_to_sv(aTHX_ axis);
    OUTPUT:
        RETVAL

SV *
xs_padding_all(value_sv)
        SV *value_sv
    PREINIT:
        Clay_Padding p;
    CODE:
        p.left = p.right = p.top = p.bottom =
            (uint16_t) clay_perl_parse_uint(aTHX_ value_sv, "padding_all: value", UINT16_MAX);
        RETVAL = clay_padding_to_sv(aTHX_ p);
    OUTPUT:
        RETVAL

SV *
xs_border_all(width_sv)
        SV *width_sv
    PREINIT:
        Clay_BorderWidth w;
    CODE:
        w.left = w.right = w.top = w.bottom = w.betweenChildren =
            (uint16_t) clay_perl_parse_uint(aTHX_ width_sv, "border_all: width", UINT16_MAX);
        RETVAL = clay_border_width_to_sv(aTHX_ w);
    OUTPUT:
        RETVAL

SV *
xs_border_outside(width_sv)
        SV *width_sv
    PREINIT:
        Clay_BorderWidth w;
    CODE:
        w.left = w.right = w.top = w.bottom =
            (uint16_t) clay_perl_parse_uint(aTHX_ width_sv, "border_outside: width", UINT16_MAX);
        w.betweenChildren = 0;
        RETVAL = clay_border_width_to_sv(aTHX_ w);
    OUTPUT:
        RETVAL

SV *
xs_corner_radius_all(radius_sv)
        SV *radius_sv
    PREINIT:
        Clay_CornerRadius r;
    CODE:
        r.topLeft = r.topRight = r.bottomLeft = r.bottomRight =
            (float) clay_perl_parse_float(aTHX_ radius_sv, "corner_radius_all: radius");
        RETVAL = clay_corner_radius_to_sv(aTHX_ r);
    OUTPUT:
        RETVAL

# =============================================================================
# Internal: the single Perl entry point of every callback trampoline (see
# src/callbacks.c). Called as _dispatch($callback, @args) by a trampoline
# that has published its dispatch kind and C result slot in
# clay_perl_pending_dispatch; takes them (so no other call can), calls
# $callback->(@args) and parses its return value into the slot. Any
# exception propagates to the trampoline's G_EVAL. Called any other way,
# it croaks.
# =============================================================================

void
xs__dispatch(...)
    PREINIT:
        clay_perl_active_dispatch dispatch;
        SV *callback;
        SV *args_sv;
        SV *ret;
        I32 i;
        int count;
    PPCODE:
        dispatch = clay_perl_pending_dispatch;
        if (!dispatch.result || items < 1) {
            croak("Clay::XS::_dispatch is internal to the Clay::XS callback trampolines");
        }
        clay_perl_pending_dispatch.result = NULL;
        callback = ST(0);
        args_sv  = items > 1 ? ST(1) : NULL;

        PUSHMARK(SP);
        for (i = 1; i < items; i++) {
            XPUSHs(ST(i));
        }
        PUTBACK;
        count = call_sv(callback, G_SCALAR);
        SPAGAIN;
        ret = count > 0 ? POPs : &PL_sv_undef;
        PUTBACK;

        clay_perl_dispatch_store_result(aTHX_ dispatch.kind, dispatch.result, ret, args_sv);
        XSRETURN_EMPTY;

# =============================================================================
# Lifecycle: explicit free hook for the context.
# =============================================================================

MODULE = Clay::XS    PACKAGE = Clay::XS::Context    PREFIX = xs_ctx_

void
xs_ctx_DESTROY(self_sv)
        SV *self_sv
    PREINIT:
        clay_perl_context *ctx;
        MAGIC *mg;
    CODE:
        ctx = clay_perl_context_peek(aTHX_ self_sv, &mg);
        if (!ctx) {
            XSRETURN_EMPTY;
        }
        /* Only an explicit call can get here for the context a callback
         * is running in: the XS wrappers pin it. */
        if (clay_perl_callback_depth > 0 && ctx == clay_perl_current_ctx) {
            croak("Clay::XS::Context::DESTROY: cannot be called from inside a Clay callback "
                  "for the context the callback runs in");
        }
        /* Clay_Initialize reads the current context ("oldContext") for its
         * default counts; it must never see freed memory. */
        if (Clay_GetCurrentContext() == ctx->clay_ctx) {
            Clay_SetCurrentContext(NULL);
        }
        if (clay_perl_current_ctx == ctx) {
            clay_perl_current_ctx = NULL;
        }
        clay_perl_context_free(aTHX_ ctx);
        mg->mg_ptr = NULL;
