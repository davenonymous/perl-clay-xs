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
 *   - Every wrapper applies its wrapper guard (CLAY_PERL_WRAPPERS):
 *     wrapper_enter checks for a usable current context, so a missing,
 *     destroyed or foreign context croaks instead of crashing inside
 *     Clay, and refuses mutating calls from inside a callback.
 *
 *   - Open/close balance is tracked per context: closing or configuring
 *     with nothing open croaks, an element is configured at most once,
 *     right after it is opened, and Clay_EndLayout closes any element
 *     left open (so Clay's state stays consistent), then croaks. The
 *     frame state (clay_perl_layout_state) keeps the functions that walk
 *     Clay's layout tree away from a half-built one.
 *
 *   - Exceptions thrown by Perl callbacks while Clay runs are held
 *     (src/callbacks.c) and re-thrown by wrapper_leave once Clay has
 *     returned. The element-construction wrappers never re-throw held
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
 * Wrapper guards.
 *
 * Every Clay::XS function has one descriptor in CLAY_PERL_WRAPPERS below;
 * wrapper_enter and wrapper_leave apply it, and Clay::XS::_wrapper_guards
 * returns the whole table (t/19 and the POD are checked against it).
 *
 *   context  CURRENT:  croaks unless clay_perl_current_ctx (which mirrors
 *                      Clay's process-wide current context) is set, usable
 *                      and owned by this interpreter.
 *            OPTIONAL: the same checks when a current context is set;
 *                      without one the wrapper gets NULL.
 *            NONE:     the wrapper needs no context.
 *   mutates  The wrapper changes Clay's state or current context, so it
 *            croaks while a Clay callback runs (clay_perl_callback_depth >
 *            0): Clay is then in the middle of one of its own functions.
 *            The croak lands in the trampoline's eval and is re-thrown by
 *            the wrapper that called into Clay. Queries stay allowed.
 *   counts   Croaks unless Clay still has the element / measure-cache word
 *            counts Clay_Initialize sized the arena for (Clay keeps its
 *            persistent arrays at those sizes and indexes some of them
 *            without range checks).
 *   frame    IN_FRAME: between Clay_BeginLayout and Clay_EndLayout;
 *            OPEN_ELEMENT: with an element open;
 *            COMPLETE_LAYOUT: outside a frame, with the last frame
 *            completed: the wrapper walks Clay's layout tree, which an
 *            open or abandoned frame leaves half built.
 *   rethrow  AFTER:  wrapper_leave re-throws the context's held error once
 *                    the Clay call has returned (never while a callback
 *                    runs, see clay_perl_take_held_error).
 *            NEVER:  element construction keeps open/close balanced, and
 *                    context management and configuration hold no layout
 *                    state.
 *            CUSTOM: the wrapper takes the held error itself
 *                    (Clay_Initialize, Clay_BeginLayout).
 *
 * The guard also pins the context until the calling statement ends, so a
 * callback that drops the last reference to it cannot free it while Clay
 * is still using it.
 * ======================================================================== */

typedef enum { WRAP_CONTEXT_NONE, WRAP_CONTEXT_OPTIONAL, WRAP_CONTEXT_CURRENT } wrapper_context;
typedef enum {
    WRAP_FRAME_NONE, WRAP_FRAME_IN_FRAME, WRAP_FRAME_OPEN_ELEMENT, WRAP_FRAME_COMPLETE_LAYOUT
} wrapper_frame;
typedef enum { WRAP_RETHROW_NEVER, WRAP_RETHROW_AFTER, WRAP_RETHROW_CUSTOM } wrapper_rethrow;

typedef struct {
    const char     *name;
    wrapper_context context;
    bool            mutates;
    bool            counts;
    wrapper_frame   frame;
    wrapper_rethrow rethrow;
} clay_perl_wrapper;

/* name, context, mutates, counts, frame, rethrow. Clay_EndLayout checks
 * its frame itself, for its own message. */
#define CLAY_PERL_WRAPPERS(W) \
    W(Clay_MinMemorySize,                      NONE,     0, 0, NONE,         NEVER)  \
    W(Clay_Initialize,                         OPTIONAL, 1, 0, NONE,         CUSTOM) \
    W(Clay_SetCurrentContext,                  NONE,     1, 0, NONE,         NEVER)  \
    W(Clay_GetCurrentContext,                  OPTIONAL, 0, 0, NONE,         NEVER)  \
    W(Clay_SetLayoutDimensions,                CURRENT,  1, 1, NONE,         AFTER)  \
    W(Clay_GetLayoutDimensions,                CURRENT,  0, 1, NONE,         AFTER)  \
    W(Clay_BeginLayout,                        CURRENT,  1, 1, NONE,         CUSTOM) \
    W(Clay_EndLayout,                          CURRENT,  1, 1, NONE,         AFTER)  \
    W(Clay__OpenElement,                       CURRENT,  1, 1, IN_FRAME,     NEVER)  \
    W(Clay__OpenElementWithId,                 CURRENT,  1, 1, IN_FRAME,     NEVER)  \
    W(Clay__CloseElement,                      CURRENT,  1, 1, OPEN_ELEMENT, NEVER)  \
    W(Clay__ConfigureOpenElement,              CURRENT,  1, 1, OPEN_ELEMENT, NEVER)  \
    W(Clay__OpenTextElement,                   CURRENT,  1, 1, IN_FRAME,     NEVER)  \
    W(Clay__HashString,                        NONE,     0, 0, NONE,         NEVER)  \
    W(Clay__HashStringWithOffset,              NONE,     0, 0, NONE,         NEVER)  \
    W(Clay_GetElementId,                       NONE,     0, 0, NONE,         NEVER)  \
    W(Clay_GetElementIdWithIndex,              NONE,     0, 0, NONE,         NEVER)  \
    W(Clay_GetOpenElementId,                   CURRENT,  1, 1, IN_FRAME,     NEVER)  \
    W(Clay_GetElementData,                     CURRENT,  0, 1, NONE,         AFTER)  \
    W(Clay_SetMeasureTextFunction,             CURRENT,  1, 1, NONE,         AFTER)  \
    W(Clay_ResetMeasureTextCache,              CURRENT,  1, 1, NONE,         AFTER)  \
    W(Clay_SetPointerState,                    CURRENT,  1, 1, COMPLETE_LAYOUT, AFTER) \
    W(Clay_GetPointerState,                    CURRENT,  0, 1, NONE,         AFTER)  \
    W(Clay_Hovered,                            CURRENT,  1, 1, IN_FRAME,     NEVER)  \
    W(Clay_OnHover,                            CURRENT,  1, 1, OPEN_ELEMENT, NEVER)  \
    W(Clay_PointerOver,                        CURRENT,  0, 1, NONE,         AFTER)  \
    W(Clay_GetPointerOverIds,                  CURRENT,  0, 1, NONE,         AFTER)  \
    W(Clay_UpdateScrollContainers,             CURRENT,  1, 1, COMPLETE_LAYOUT, AFTER) \
    W(Clay_GetScrollOffset,                    CURRENT,  1, 1, IN_FRAME,     NEVER)  \
    W(Clay_GetScrollContainerData,             CURRENT,  0, 1, NONE,         AFTER)  \
    W(Clay_SetQueryScrollOffsetFunction,       CURRENT,  1, 1, NONE,         AFTER)  \
    W(Clay_SetExternalScrollHandlingEnabled,   CURRENT,  1, 1, NONE,         AFTER)  \
    W(set_scroll_position,                     CURRENT,  1, 1, NONE,         AFTER)  \
    W(check_struct,                            NONE,     0, 0, NONE,         NEVER)  \
    W(Clay_SetDebugModeEnabled,                CURRENT,  1, 1, NONE,         AFTER)  \
    W(Clay_IsDebugModeEnabled,                 CURRENT,  0, 1, NONE,         AFTER)  \
    W(Clay_SetCullingEnabled,                  CURRENT,  1, 1, NONE,         AFTER)  \
    W(Clay_GetMaxElementCount,                 CURRENT,  0, 0, NONE,         NEVER)  \
    W(Clay_SetMaxElementCount,                 OPTIONAL, 1, 0, NONE,         NEVER)  \
    W(Clay_GetMaxMeasureTextCacheWordCount,    CURRENT,  0, 0, NONE,         NEVER)  \
    W(Clay_SetMaxMeasureTextCacheWordCount,    OPTIONAL, 1, 0, NONE,         NEVER)  \
    W(Clay_EaseOut,                            NONE,     0, 0, NONE,         NEVER)  \
    W(Clay_SetTransitionHandlers,              CURRENT,  1, 1, NONE,         AFTER)  \
    W(sizing_fit,                              NONE,     0, 0, NONE,         NEVER)  \
    W(sizing_grow,                             NONE,     0, 0, NONE,         NEVER)  \
    W(sizing_fixed,                            NONE,     0, 0, NONE,         NEVER)  \
    W(sizing_percent,                          NONE,     0, 0, NONE,         NEVER)  \
    W(padding_all,                             NONE,     0, 0, NONE,         NEVER)  \
    W(border_all,                              NONE,     0, 0, NONE,         NEVER)  \
    W(border_outside,                          NONE,     0, 0, NONE,         NEVER)  \
    W(corner_radius_all,                       NONE,     0, 0, NONE,         NEVER)

#define CLAY_PERL_WRAPPER_DESCRIPTOR(name, context, mutates, counts, frame, rethrow) \
    static const clay_perl_wrapper GUARD_##name = {                                  \
        #name, WRAP_CONTEXT_##context, mutates, counts, WRAP_FRAME_##frame, WRAP_RETHROW_##rethrow \
    };
CLAY_PERL_WRAPPERS(CLAY_PERL_WRAPPER_DESCRIPTOR)

#define CLAY_PERL_WRAPPER_ENTRY(name, context, mutates, counts, frame, rethrow) &GUARD_##name,
static const clay_perl_wrapper *const all_wrappers[] = { CLAY_PERL_WRAPPERS(CLAY_PERL_WRAPPER_ENTRY) };

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

static void require_frame(pTHX_ const clay_perl_wrapper *w, clay_perl_context *ctx)
{
    switch (w->frame) {
    case WRAP_FRAME_NONE:
        return;
    case WRAP_FRAME_IN_FRAME:
        if (ctx->layout_state != CLAY_PERL_LAYOUT_DECLARING) {
            croak("%s: called outside Clay_BeginLayout/Clay_EndLayout", w->name);
        }
        return;
    case WRAP_FRAME_OPEN_ELEMENT:
        if (ctx->layout_state != CLAY_PERL_LAYOUT_DECLARING || ctx->open_depth == 0) {
            croak("%s: no element is open (unbalanced Clay__OpenElement/Clay__CloseElement)", w->name);
        }
        return;
    case WRAP_FRAME_COMPLETE_LAYOUT:
        if (ctx->layout_state == CLAY_PERL_LAYOUT_DECLARING) {
            croak("%s: cannot be called between Clay_BeginLayout and Clay_EndLayout", w->name);
        }
        if (ctx->layout_state == CLAY_PERL_LAYOUT_ABANDONED) {
            croak("%s: the last frame was never finished; complete a frame "
                  "(Clay_BeginLayout ... Clay_EndLayout) first", w->name);
        }
        return;
    }
}

/* Element declaration bookkeeping: an element may be configured only
 * right after it was opened, before any child, as the C CLAY() macro
 * does. */
static void element_opened(clay_perl_context *ctx)
{
    ctx->open_depth++;
    ctx->open_element_configurable = true;
}

static void element_closed(clay_perl_context *ctx)
{
    ctx->open_depth--;
    ctx->open_element_configurable = false;
}

/* Applies a descriptor before the wrapper's work; returns the context it
 * acquired (NULL for NONE, and for OPTIONAL without a current context). */
static clay_perl_context *wrapper_enter(pTHX_ const clay_perl_wrapper *w)
{
    if (w->mutates) forbid_in_callback(aTHX_ w->name);
    if (w->context == WRAP_CONTEXT_NONE) return NULL;

    clay_perl_context *ctx = clay_perl_current_ctx;
    if (!ctx && w->context == WRAP_CONTEXT_OPTIONAL) return NULL;
    if (!ctx || !ctx->clay_ctx) {
        croak("%s: no current Clay context; call Clay_Initialize first", w->name);
    }
    if (ctx->owner != CLAY_PERL_THIS_INTERPRETER) {
        croak("%s: the current Clay::XS context belongs to a different interpreter/thread "
              "(Clay has one process-wide current context)", w->name);
    }
    if (w->counts
        && (Clay_GetMaxElementCount() != ctx->max_element_count
            || Clay_GetMaxMeasureTextCacheWordCount() != ctx->max_measure_text_cache_word_count)) {
        croak("%s: element/word counts changed since Clay_Initialize; call Clay_Initialize again", w->name);
    }
    pin_context(aTHX_ ctx);
    require_frame(aTHX_ w, ctx);
    return ctx;
}

/* Applies a descriptor once the wrapper's Clay call has returned. */
static void wrapper_leave(pTHX_ const clay_perl_wrapper *w, clay_perl_context *ctx)
{
    if (w->rethrow != WRAP_RETHROW_AFTER) return;
    clay_perl_raise_held_error(aTHX_ ctx);
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
    /* (NV) SIZE_MAX rounds up to 2**64 on 64-bit perls, itself out of range. */
    if (!(bytes >= 0) || bytes != Perl_floor(bytes) || bytes >= (NV) SIZE_MAX) {
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

/* Croaks for elements left open at Clay_EndLayout, appending a held
 * callback error message when one is held as well. A held exception
 * object is re-thrown unchanged instead (the elements are closed either
 * way). */
static void croak_unbalanced(pTHX_ clay_perl_context *ctx, int32_t still_open)
{
    SV *held = clay_perl_take_held_error(aTHX_ ctx, NULL);
    if (held && SvROK(held)) croak_sv(held);

    SV *message = sv_2mortal(newSVpvf(
        "%d element%s still open at Clay_EndLayout "
        "(unbalanced Clay__OpenElement/Clay__CloseElement)",
        (int) still_open, still_open == 1 ? "" : "s"));
    if (held) {
        sv_catpvs(message, "; callback error: ");
        sv_catsv(message, held);
    }
    croak_sv(message);
}

/* ===========================================================================
 * Scroll position writes.
 *
 * A position written by set_scroll_position shows only in the next frame,
 * so Clay::UI::Revision adds this count to its revision: a renderer that
 * skips unchanged frames still draws it. Process-wide, like Clay's current
 * context, and shared by all interpreters: only its changes matter, and a
 * write from another thread at worst makes a renderer draw once more.
 * ======================================================================== */

static UV scroll_position_writes = 0;

MODULE = Clay::XS    PACKAGE = Clay::XS    PREFIX = xs_

PROTOTYPES: DISABLE

BOOT:
{
    /* Layout direction. */
    install_iv_const(aTHX_ "CLAY_LEFT_TO_RIGHT", CLAY_LEFT_TO_RIGHT);
    install_iv_const(aTHX_ "CLAY_TOP_TO_BOTTOM", CLAY_TOP_TO_BOTTOM);
    install_iv_const(aTHX_ "CLAY_LEFT_TO_RIGHT_WRAP", CLAY_LEFT_TO_RIGHT_WRAP);

    /* Line sizing of wrap containers. */
    install_iv_const(aTHX_ "CLAY_LINE_SIZING_GROW", CLAY_LINE_SIZING_GROW);
    install_iv_const(aTHX_ "CLAY_LINE_SIZING_FIT",  CLAY_LINE_SIZING_FIT);

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
        /* Pinned by the guard; it is restored if initialisation fails. */
        previous_ctx  = wrapper_enter(aTHX_ &GUARD_Clay_Initialize);
        previous_clay = Clay_GetCurrentContext();
        configured_counts(&element_count, &word_count);
        require_counts_fit(aTHX_ "Clay_Initialize", element_count, word_count);
        /* Clay_SetMaxElementCount without a context sets the word count to
         * 2 x elements, past the setter's minimum; Clay divides by
         * word_count / 32. */
        if (word_count < MIN_MEASURE_TEXT_CACHE_WORDS) {
            croak("Clay_Initialize: %d measure-cache words are below the minimum of %d "
                  "(without a context, Clay_SetMaxElementCount sets them to 2 x elements; "
                  "call Clay_SetMaxMeasureTextCacheWordCount afterwards)",
                  (int) word_count, MIN_MEASURE_TEXT_CACHE_WORDS);
        }
        if (word_count / MIN_MEASURE_TEXT_CACHE_WORDS > element_count) {
            croak("Clay_Initialize: %d measure-cache words need %d hash buckets but only %d elements "
                  "are configured; Clay would index its measure cache out of bounds",
                  (int) word_count, (int) (word_count / MIN_MEASURE_TEXT_CACHE_WORDS), (int) element_count);
        }

        capacity      = parse_capacity(aTHX_ capacity_sv);
        dim           = clay_dimensions_from_sv(aTHX_ dimensions_sv, "Clay_Initialize: dimensions");
        error_handler = clay_perl_require_code(aTHX_ error_handler_sv, "Clay_Initialize: error handler", true);

        ctx = clay_perl_context_new(aTHX_ capacity);
        if (!ctx) {
            croak("Clay_Initialize: cannot allocate %" UVuf " bytes", (UV) capacity);
        }
        clay_perl_callback_set(aTHX_ ctx, CLAY_PERL_DISPATCH_ERROR_HANDLER, error_handler, error_userdata_sv);

        handler.errorHandlerFunction = clay_perl_error_handler_trampoline;
        handler.userData             = ctx;
        ctx->clay_ctx = Clay_Initialize(ctx->clay_arena, dim, handler);

        failure = NULL;
        if (!ctx->clay_ctx) {
            failure = sv_2mortal(newSVpvs("Clay_Initialize: Clay could not create a context in the arena"));
        } else {
            ctx->max_element_count                 = Clay_GetMaxElementCount();
            ctx->max_measure_text_cache_word_count = Clay_GetMaxMeasureTextCacheWordCount();
            /* Clay keeps both function pointers process-wide and only the
             * userData per context: every context gets the trampolines, so
             * text measured without a Perl function is always reported. */
            Clay_SetMeasureTextFunction(clay_perl_measure_text_trampoline, ctx);
            Clay_SetQueryScrollOffsetFunction(clay_perl_query_scroll_offset_trampoline, ctx);
            clay_perl_current_ctx = ctx;
            failure = clay_perl_take_held_error(aTHX_ ctx, NULL);
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
        (void) wrapper_enter(aTHX_ &GUARD_Clay_SetCurrentContext);
        ctx = clay_perl_context_from_sv(aTHX_ ctx_sv);
        if (ctx->owner != CLAY_PERL_THIS_INTERPRETER) {
            croak("Clay_SetCurrentContext: Clay::XS context used from a different interpreter/thread");
        }
        Clay_SetCurrentContext(ctx->clay_ctx);
        clay_perl_current_ctx = ctx;

SV *
xs_Clay_GetCurrentContext()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx    = wrapper_enter(aTHX_ &GUARD_Clay_GetCurrentContext);
        RETVAL = ctx ? clay_perl_context_to_sv(aTHX_ ctx) : &PL_sv_undef;
    OUTPUT:
        RETVAL

void
xs_Clay_SetLayoutDimensions(dimensions_sv)
        SV *dimensions_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_Dimensions dim;
    CODE:
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_SetLayoutDimensions);
        dim = clay_dimensions_from_sv(aTHX_ dimensions_sv, "Clay_SetLayoutDimensions: dimensions");
        Clay_SetLayoutDimensions(dim);
        wrapper_leave(aTHX_ &GUARD_Clay_SetLayoutDimensions, ctx);

SV *
xs_Clay_GetLayoutDimensions()
    PREINIT:
        clay_perl_context *ctx;
        Clay_Dimensions dim;
    CODE:
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_GetLayoutDimensions);
        dim = Clay_GetLayoutDimensions();
        wrapper_leave(aTHX_ &GUARD_Clay_GetLayoutDimensions, ctx);
        RETVAL = clay_dimensions_to_sv(aTHX_ dim);
    OUTPUT:
        RETVAL

void
xs_Clay_BeginLayout()
    PREINIT:
        clay_perl_context *ctx;
        SV *leftover;
    CODE:
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_BeginLayout);
        leftover = clay_perl_take_held_error(aTHX_ ctx, " (from the previous unfinished frame)");
        if (leftover) {
            if (ctx->layout_state == CLAY_PERL_LAYOUT_DECLARING) {
                ctx->layout_state = CLAY_PERL_LAYOUT_ABANDONED;
            }
            ctx->open_depth                = 0;
            ctx->open_element_configurable = false;
            croak_sv(leftover);
        }
        clay_perl_context_begin_frame(aTHX_ ctx);
        Clay_BeginLayout();
        ctx->layout_state              = CLAY_PERL_LAYOUT_DECLARING;
        ctx->open_depth                = 0;
        ctx->open_element_configurable = false;

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
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_EndLayout);
        if (ctx->layout_state != CLAY_PERL_LAYOUT_DECLARING) {
            croak("Clay_EndLayout: called without a matching Clay_BeginLayout");
        }
        delta_time = (float) clay_perl_parse_float_or(aTHX_ delta_time_sv, "Clay_EndLayout: deltaTime", 0.0);
        still_open = ctx->open_depth;
        ctx->open_depth                = 0;
        ctx->open_element_configurable = false;
        for (int32_t i = 0; i < still_open; i++) {
            Clay__CloseElement();
        }

        outer_transition_ctx = clay_perl_active_transition_ctx;
        clay_perl_active_transition_ctx = ctx;
        cmds = Clay_EndLayout(delta_time);
        clay_perl_active_transition_ctx = outer_transition_ctx;
        ctx->layout_state = CLAY_PERL_LAYOUT_COMPLETE;
        ctx->completed_frames++;

        if (still_open > 0) {
            croak_unbalanced(aTHX_ ctx, still_open);
        }
        wrapper_leave(aTHX_ &GUARD_Clay_EndLayout, ctx);
        RETVAL = clay_render_command_array_to_sv(aTHX_ &cmds);
    OUTPUT:
        RETVAL

# =============================================================================
# Element open/close. These never re-throw held callback errors; see the
# file header.
# =============================================================================

void
xs_Clay__OpenElement()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = wrapper_enter(aTHX_ &GUARD_Clay__OpenElement);
        Clay__OpenElement();
        element_opened(ctx);

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
        ctx = wrapper_enter(aTHX_ &GUARD_Clay__OpenElementWithId);
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
        element_opened(ctx);

void
xs_Clay__CloseElement()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = wrapper_enter(aTHX_ &GUARD_Clay__CloseElement);
        Clay__CloseElement();
        element_closed(ctx);

void
xs_Clay__ConfigureOpenElement(decl_sv)
        SV *decl_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_ElementDeclaration decl;
    CODE:
        ctx = wrapper_enter(aTHX_ &GUARD_Clay__ConfigureOpenElement);
        /* Clay pushes the clip stack and floating roots per configuration
         * but pops them once per element. */
        if (!ctx->open_element_configurable) {
            croak("Clay__ConfigureOpenElement: the open element is already configured or has children; "
                  "configure an element once, right after opening it");
        }
        decl = clay_element_declaration_from_sv(aTHX_ decl_sv);
        Clay__ConfigureOpenElement(decl);
        ctx->open_element_configurable = false;

void
xs_Clay__OpenTextElement(text_sv, config_sv = &PL_sv_undef)
        SV *text_sv
        SV *config_sv
    PREINIT:
        clay_perl_context *ctx;
        Clay_String text;
        Clay_TextElementConfig config;
    CODE:
        ctx = wrapper_enter(aTHX_ &GUARD_Clay__OpenTextElement);
        config = clay_text_element_config_from_sv(aTHX_ config_sv);
        text = clay_perl_arena_copy_text(aTHX_ ctx, text_sv, "Clay__OpenTextElement");
        Clay__OpenTextElement(text, config);
        ctx->open_element_configurable = false;

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
        seed = (uint32_t) clay_perl_parse_uint_or(aTHX_ seed_sv, "Clay__HashString: seed", UINT32_MAX, 0);
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
        seed   = (uint32_t) clay_perl_parse_uint_or(aTHX_ seed_sv, "Clay__HashStringWithOffset: seed", UINT32_MAX, 0);
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
    CODE:
        (void) wrapper_enter(aTHX_ &GUARD_Clay_GetOpenElementId);
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
        ctx  = wrapper_enter(aTHX_ &GUARD_Clay_GetElementData);
        id   = clay_element_id_from_sv(aTHX_ id_sv, "Clay_GetElementData: element id");
        data = Clay_GetElementData(id);
        wrapper_leave(aTHX_ &GUARD_Clay_GetElementData, ctx);
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
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_SetMeasureTextFunction);
        cb  = clay_perl_require_code(aTHX_ cb_sv, "Clay_SetMeasureTextFunction: callback", true);
        clay_perl_callback_set(aTHX_ ctx, CLAY_PERL_DISPATCH_MEASURE_TEXT, cb, userdata_sv);
        Clay_SetMeasureTextFunction(clay_perl_measure_text_trampoline, ctx);
        wrapper_leave(aTHX_ &GUARD_Clay_SetMeasureTextFunction, ctx);

void
xs_Clay_ResetMeasureTextCache()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_ResetMeasureTextCache);
        Clay_ResetMeasureTextCache();
        wrapper_leave(aTHX_ &GUARD_Clay_ResetMeasureTextCache, ctx);

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
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_SetPointerState);
        pos = clay_vector2_from_sv(aTHX_ position_sv, "Clay_SetPointerState: position");
        Clay_SetPointerState(pos, pointerDown);
        wrapper_leave(aTHX_ &GUARD_Clay_SetPointerState, ctx);

SV *
xs_Clay_GetPointerState()
    PREINIT:
        clay_perl_context *ctx;
        Clay_PointerData pointer;
    CODE:
        ctx     = wrapper_enter(aTHX_ &GUARD_Clay_GetPointerState);
        pointer = Clay_GetPointerState();
        wrapper_leave(aTHX_ &GUARD_Clay_GetPointerState, ctx);
        RETVAL = clay_pointer_data_to_sv(aTHX_ pointer);
    OUTPUT:
        RETVAL

bool
xs_Clay_Hovered()
    CODE:
        (void) wrapper_enter(aTHX_ &GUARD_Clay_Hovered);
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
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_OnHover);
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
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_PointerOver);
        id  = clay_element_id_from_sv(aTHX_ id_sv, "Clay_PointerOver: element id");
        RETVAL = Clay_PointerOver(id);
        wrapper_leave(aTHX_ &GUARD_Clay_PointerOver, ctx);
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
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_GetPointerOverIds);
        ids = Clay_GetPointerOverIds();
        wrapper_leave(aTHX_ &GUARD_Clay_GetPointerOverIds, ctx);
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
        ctx        = wrapper_enter(aTHX_ &GUARD_Clay_UpdateScrollContainers);
        delta      = clay_vector2_from_sv(aTHX_ scroll_delta_sv, "Clay_UpdateScrollContainers: scrollDelta");
        delta_time = (float) clay_perl_parse_float(aTHX_ delta_time_sv, "Clay_UpdateScrollContainers: deltaTime");
        Clay_UpdateScrollContainers(enable_drag_scrolling, delta, delta_time);
        wrapper_leave(aTHX_ &GUARD_Clay_UpdateScrollContainers, ctx);

SV *
xs_Clay_GetScrollOffset()
    CODE:
        (void) wrapper_enter(aTHX_ &GUARD_Clay_GetScrollOffset);
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
        ctx  = wrapper_enter(aTHX_ &GUARD_Clay_GetScrollContainerData);
        id   = clay_element_id_from_sv(aTHX_ id_sv, "Clay_GetScrollContainerData: element id");
        data = Clay_GetScrollContainerData(id);
        wrapper_leave(aTHX_ &GUARD_Clay_GetScrollContainerData, ctx);
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
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_SetQueryScrollOffsetFunction);
        cb  = clay_perl_require_code(aTHX_ cb_sv, "Clay_SetQueryScrollOffsetFunction: callback", true);
        clay_perl_callback_set(aTHX_ ctx, CLAY_PERL_DISPATCH_QUERY_SCROLL_OFFSET, cb, userdata_sv);
        Clay_SetQueryScrollOffsetFunction(clay_perl_query_scroll_offset_trampoline, ctx);
        wrapper_leave(aTHX_ &GUARD_Clay_SetQueryScrollOffsetFunction, ctx);

void
xs_Clay_SetExternalScrollHandlingEnabled(enabled)
        bool enabled
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_SetExternalScrollHandlingEnabled);
        if (enabled && !ctx->callbacks[CLAY_PERL_DISPATCH_QUERY_SCROLL_OFFSET].code) {
            croak("Clay_SetExternalScrollHandlingEnabled: install a function with "
                  "Clay_SetQueryScrollOffsetFunction first");
        }
        /* Clay calls its global query function without a NULL check while
         * external handling is on; make sure it is ours. */
        Clay_SetQueryScrollOffsetFunction(clay_perl_query_scroll_offset_trampoline, ctx);
        Clay_SetExternalScrollHandlingEnabled(enabled);
        wrapper_leave(aTHX_ &GUARD_Clay_SetExternalScrollHandlingEnabled, ctx);

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
        ctx      = wrapper_enter(aTHX_ &GUARD_set_scroll_position);
        id       = clay_element_id_from_sv(aTHX_ id_sv, "set_scroll_position: element id");
        position = clay_vector2_from_sv(aTHX_ position_sv, "set_scroll_position: position");
        data     = Clay_GetScrollContainerData(id);
        if (!data.found || !data.scrollPosition) {
            croak("set_scroll_position: element %u is not a known scroll container "
                  "(declare it with clip enabled and complete a frame first)", (unsigned) id.id);
        }
        *data.scrollPosition = position;
        scroll_position_writes++;
        wrapper_leave(aTHX_ &GUARD_set_scroll_position, ctx);

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
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_SetDebugModeEnabled);
        Clay_SetDebugModeEnabled(enabled);
        wrapper_leave(aTHX_ &GUARD_Clay_SetDebugModeEnabled, ctx);

bool
xs_Clay_IsDebugModeEnabled()
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx    = wrapper_enter(aTHX_ &GUARD_Clay_IsDebugModeEnabled);
        RETVAL = Clay_IsDebugModeEnabled();
        wrapper_leave(aTHX_ &GUARD_Clay_IsDebugModeEnabled, ctx);
    OUTPUT:
        RETVAL

void
xs_Clay_SetCullingEnabled(enabled)
        bool enabled
    PREINIT:
        clay_perl_context *ctx;
    CODE:
        ctx = wrapper_enter(aTHX_ &GUARD_Clay_SetCullingEnabled);
        Clay_SetCullingEnabled(enabled);
        wrapper_leave(aTHX_ &GUARD_Clay_SetCullingEnabled, ctx);

IV
xs_Clay_GetMaxElementCount()
    CODE:
        (void) wrapper_enter(aTHX_ &GUARD_Clay_GetMaxElementCount);
        RETVAL = (IV) Clay_GetMaxElementCount();
    OUTPUT:
        RETVAL

void
xs_Clay_SetMaxElementCount(count_sv)
        SV *count_sv
    PREINIT:
        clay_perl_context *ctx;
        int32_t count;
    CODE:
        ctx   = wrapper_enter(aTHX_ &GUARD_Clay_SetMaxElementCount);
        count = parse_count(aTHX_ count_sv, "Clay_SetMaxElementCount", 1);
        if (!ctx) {
            /* Clay derives the default word count from the element count. */
            if (count > INT32_MAX / 2) {
                croak("Clay_SetMaxElementCount: %d elements would overflow Clay's default "
                      "measure-cache word count (2 x elements)", (int) count);
            }
            require_counts_fit(aTHX_ "Clay_SetMaxElementCount", count, count * 2);
        } else {
            require_counts_fit(aTHX_ "Clay_SetMaxElementCount", count, Clay_GetMaxMeasureTextCacheWordCount());
        }
        Clay_SetMaxElementCount(count);

IV
xs_Clay_GetMaxMeasureTextCacheWordCount()
    CODE:
        (void) wrapper_enter(aTHX_ &GUARD_Clay_GetMaxMeasureTextCacheWordCount);
        RETVAL = (IV) Clay_GetMaxMeasureTextCacheWordCount();
    OUTPUT:
        RETVAL

void
xs_Clay_SetMaxMeasureTextCacheWordCount(count_sv)
        SV *count_sv
    PREINIT:
        clay_perl_context *ctx;
        int32_t count;
        int32_t element_count;
        int32_t unused_word_count;
    CODE:
        ctx   = wrapper_enter(aTHX_ &GUARD_Clay_SetMaxMeasureTextCacheWordCount);
        count = parse_count(aTHX_ count_sv, "Clay_SetMaxMeasureTextCacheWordCount", MIN_MEASURE_TEXT_CACHE_WORDS);
        if (!ctx) {
            clay_perl_clay_default_counts(&element_count, &unused_word_count);
        } else {
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
        args.transitionState = (Clay_TransitionState) clay_perl_parse_uint_or(
            aTHX_ slot ? *slot : &PL_sv_undef, "Clay_EaseOut: transitionState", CLAY_TRANSITION_STATE_EXITING, 0);
        slot = hv_fetchs(hv, "elapsedTime", 0);
        args.elapsedTime = (float) clay_perl_parse_float_or(
            aTHX_ slot ? *slot : &PL_sv_undef, "Clay_EaseOut: elapsedTime", 0.0);
        slot = hv_fetchs(hv, "duration", 0);
        args.duration = (float) clay_perl_parse_float_or(
            aTHX_ slot ? *slot : &PL_sv_undef, "Clay_EaseOut: duration", 0.0);
        slot = hv_fetchs(hv, "properties", 0);
        args.properties = (Clay_TransitionProperty) clay_perl_parse_uint_or(
            aTHX_ slot ? *slot : &PL_sv_undef, "Clay_EaseOut: properties",
            CLAY_TRANSITION_PROPERTY_BOUNDING_BOX | CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR
            | CLAY_TRANSITION_PROPERTY_OVERLAY_COLOR | CLAY_TRANSITION_PROPERTY_CORNER_RADIUS
            | CLAY_TRANSITION_PROPERTY_BORDER, 0);

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
        ctx         = wrapper_enter(aTHX_ &GUARD_Clay_SetTransitionHandlers);
        handler     = clay_perl_require_code(aTHX_ handler_sv, "Clay_SetTransitionHandlers: handler", true);
        set_initial = clay_perl_require_code(aTHX_ set_initial_sv, "Clay_SetTransitionHandlers: setInitialState", true);
        set_final   = clay_perl_require_code(aTHX_ set_final_sv, "Clay_SetTransitionHandlers: setFinalState", true);
        clay_perl_callback_set(aTHX_ ctx, CLAY_PERL_DISPATCH_TRANSITION_HANDLER,     handler,     userdata_sv);
        clay_perl_callback_set(aTHX_ ctx, CLAY_PERL_DISPATCH_TRANSITION_SET_INITIAL, set_initial, userdata_sv);
        clay_perl_callback_set(aTHX_ ctx, CLAY_PERL_DISPATCH_TRANSITION_SET_FINAL,   set_final,   userdata_sv);
        wrapper_leave(aTHX_ &GUARD_Clay_SetTransitionHandlers, ctx);

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
        axis.size.minMax.min = (float) clay_perl_parse_float_or(aTHX_ min_sv, "sizing_fit: min", 0.0);
        axis.size.minMax.max = (float) clay_perl_parse_max_float_or(aTHX_ max_sv, "sizing_fit: max", 0.0);
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
        axis.size.minMax.min = (float) clay_perl_parse_float_or(aTHX_ min_sv, "sizing_grow: min", 0.0);
        axis.size.minMax.max = (float) clay_perl_parse_max_float_or(aTHX_ max_sv, "sizing_grow: max", 0.0);
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
# Internal: the wrapper guard table, for the tests. Returns
# { name => { context, mutates, counts, frame, rethrow } }.
# =============================================================================

SV *
xs__wrapper_guards()
    PREINIT:
        static const char *const contexts[] = { "none", "optional", "current" };
        static const char *const frames[]   = { "none", "in_frame", "open_element", "complete_layout" };
        static const char *const rethrows[] = { "never", "after", "custom" };
        HV *table;
        HV *guard;
        size_t i;
    CODE:
        table = newHV();
        for (i = 0; i < sizeof(all_wrappers) / sizeof(all_wrappers[0]); i++) {
            const clay_perl_wrapper *w = all_wrappers[i];
            guard = newHV();
            (void) hv_stores(guard, "context", newSVpv(contexts[w->context], 0));
            (void) hv_stores(guard, "mutates", newSVuv(w->mutates ? 1 : 0));
            (void) hv_stores(guard, "counts",  newSVuv(w->counts ? 1 : 0));
            (void) hv_stores(guard, "frame",   newSVpv(frames[w->frame], 0));
            (void) hv_stores(guard, "rethrow", newSVpv(rethrows[w->rethrow], 0));
            (void) hv_store(table, w->name, (I32) strlen(w->name), newRV_noinc((SV *) guard), 0);
        }
        RETVAL = newRV_noinc((SV *) table);
    OUTPUT:
        RETVAL

# =============================================================================
# Internal: how often set_scroll_position wrote a position, for
# Clay::UI::Revision.
# =============================================================================

UV
xs__scroll_position_writes()
    CODE:
        RETVAL = scroll_position_writes;
    OUTPUT:
        RETVAL

# =============================================================================
# Internal: how many string-arena chunks a context holds, for the tests of
# the arena's retention rule.
# =============================================================================

UV
xs__string_arena_chunk_count(ctx_sv)
        SV *ctx_sv
    PREINIT:
        clay_perl_context *ctx;
        const clay_perl_arena_chunk *chunk;
    CODE:
        ctx    = clay_perl_context_from_sv(aTHX_ ctx_sv);
        RETVAL = 0;
        for (chunk = ctx->strings.current; chunk; chunk = chunk->next) RETVAL++;
        for (chunk = ctx->strings.retained; chunk; chunk = chunk->next) RETVAL++;
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
        MAGIC *mg;
        SV *lost_error;
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
        /* An abandoned frame can leave a held error no wrapper re-threw.
         * It is warned about only after the context is freed: a dying
         * warn handler or a dying stringification must not leak it. */
        lost_error = ctx->held_error ? sv_2mortal(ctx->held_error) : NULL;
        ctx->held_error = NULL;
        mg->mg_ptr = NULL;
        clay_perl_context_free(aTHX_ ctx);
        if (lost_error) {
            warn("Clay::XS: context destroyed with a held callback error: %" SVf, SVfARG(lost_error));
        }
