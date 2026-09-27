/*
 * callbacks.c - C trampolines that forward Clay's function-pointer
 * callbacks into Perl coderefs, and the deferred-error slot they report
 * failures through.
 *
 * Clay holds several function-pointer slots that user code provides:
 *
 *   - Clay_SetMeasureTextFunction       (one per context)
 *   - Clay_Initialize errorHandler      (one per context)
 *   - Clay_SetQueryScrollOffsetFunction (one per context)
 *   - Clay_OnHover                      (per element)
 *   - Clay_TransitionElementConfig.handler / enter.setInitialState /
 *     exit.setFinalState                (per element with transitions,
 *                                        but bridged through a single
 *                                        per-context handler set; see
 *                                        clay_perl.h for rationale)
 *
 * Each is bridged by a fixed C function defined here. Clay calls them in
 * the middle of its own C code, which must never be unwound by a Perl
 * exception. Every trampoline therefore makes exactly one Perl call: the
 * internal Clay::XS::_dispatch XSUB, under G_EVAL. The dispatcher calls
 * the user's coderef and parses its return value into a C result slot;
 * any exception - from the callback, from overloaded or tied return
 * values, from FATAL warnings, or from a malformed result - lands in that
 * G_EVAL. The trampoline then stashes it as the context's pending error
 * and returns a neutral value to Clay. The XS wrapper that called into
 * Clay re-throws the pending error once Clay has returned (see
 * clay_perl_raise_pending_error and the wrappers in lib/Clay/XS.xs).
 *
 * Threading the active context to the trampolines:
 *
 *   - For per-context callbacks (measure_text, error_handler,
 *     query_scroll_offset), Clay's userData slot carries the
 *     clay_perl_context*; a context that never installed a function has
 *     NULL userData, and the trampoline falls back to the current context.
 *
 *   - For hover, the element id is supplied as a function argument; the
 *     context is supplied as Clay's userData. The trampoline looks up the
 *     registered Perl coderef in ctx->hover_callbacks.
 *
 *   - For transitions, the callback signatures lack any way to pass our
 *     context pointer. The Clay_EndLayout wrapper sets the thread-local
 *     clay_perl_active_transition_ctx around the Clay_EndLayout call.
 *
 * Clay forgets an element's hover function whenever the element is
 * declared again (Clay__AddHashMapItem clears onHoverFunction), so hover
 * callbacks must be registered every frame. The registry sweep in
 * clay_perl_hover_registry_sweep only reclaims entries no frame can reach
 * any more.
 */

#include "clay_perl.h"

#include <stdio.h>
#include <string.h>

/* The context the binding treats as current; mirrors Clay's global. */
clay_perl_context *clay_perl_current_ctx = NULL;

/* ---------------------------------------------------------------------------
 * Thread-local active transition context.
 *
 * Set by the Clay_EndLayout wrapper around Clay_EndLayout. The transition
 * trampolines fall back to identity behaviour if it is NULL, which keeps
 * them safe to call even outside an EndLayout.
 * ------------------------------------------------------------------------ */

CLAY_PERL_THREAD_LOCAL clay_perl_context *clay_perl_active_transition_ctx = NULL;

CLAY_PERL_THREAD_LOCAL uint32_t clay_perl_callback_depth = 0;

CLAY_PERL_THREAD_LOCAL clay_perl_active_dispatch clay_perl_pending_dispatch = { 0, NULL };

/* ---------------------------------------------------------------------------
 * Deferred callback errors.
 * ------------------------------------------------------------------------ */

void clay_perl_stash_callback_error(pTHX_ clay_perl_context *ctx)
{
    if (ctx->pending_error) {
        ctx->suppressed_errors++;
    } else {
        ctx->pending_error = newSVsv(ERRSV);
    }
    sv_setpvs(ERRSV, "");
}

void clay_perl_stash_error_message(pTHX_ clay_perl_context *ctx, const char *message)
{
    if (ctx->pending_error) {
        ctx->suppressed_errors++;
        return;
    }
    ctx->pending_error = newSVpv(message, 0);
}

SV *clay_perl_take_pending_error(pTHX_ clay_perl_context *ctx, const char *note)
{
    SV *error = ctx->pending_error;
    if (!error) return NULL;

    uint32_t suppressed = ctx->suppressed_errors;
    ctx->pending_error     = NULL;
    ctx->suppressed_errors = 0;
    sv_2mortal(error);

    /* A failed or skipped measurement returned 0x0, which Clay cached per
     * text and config; drop the cache so the next frame measures again. */
    if (ctx->measure_cache_poisoned) {
        ctx->measure_cache_poisoned = false;
        Clay_ResetMeasureTextCache();
    }

    if (SvROK(error) || (suppressed == 0 && !note)) return error;

    STRLEN len;
    const char *pv = SvPV(error, len);
    bool newline = len > 0 && pv[len - 1] == '\n';
    SV *message = sv_2mortal(newSVpvn_flags(pv, newline ? len - 1 : len, SvUTF8(error)));
    if (suppressed > 0) {
        sv_catpvf(message, " (and %" UVuf " more callback error%s this frame)",
                  (UV) suppressed, suppressed == 1 ? "" : "s");
    }
    if (note) sv_catpv(message, note);
    if (newline) sv_catpvs(message, "\n");
    return message;
}

void clay_perl_raise_pending_error(pTHX_ clay_perl_context *ctx)
{
    SV *error = clay_perl_take_pending_error(aTHX_ ctx, NULL);
    if (error) croak_sv(error);
}

/* ---------------------------------------------------------------------------
 * Dispatch.
 *
 * call_dispatcher publishes (kind, result slot) in clay_perl_pending_dispatch,
 * pushes (callback, args...) and calls Clay::XS::_dispatch under G_EVAL,
 * counting itself in clay_perl_callback_depth. The previous pending
 * dispatch is restored afterwards, so nested dispatches (an error reported
 * while a callback runs) work. It must run between ENTER/SAVETMPS and
 * FREETMPS/LEAVE of the calling trampoline, with $@ localised there, so
 * the caller's $@ survives the callback. Returns true on failure (the
 * error is stashed on ctx).
 * ------------------------------------------------------------------------ */

static bool call_dispatcher(pTHX_ clay_perl_context *ctx, clay_perl_dispatch_kind kind,
                            clay_perl_dispatch_result *result, SV *callback,
                            SV **args, int argc)
{
    dSP;
    PUSHMARK(SP);
    EXTEND(SP, 1 + argc);
    /* A private reference keeps the callback alive even if it replaces
     * its own slot while running. */
    PUSHs(sv_2mortal(newSVsv(callback)));
    for (int i = 0; i < argc; i++) {
        PUSHs(args[i]);
    }
    PUTBACK;

    clay_perl_active_dispatch saved = clay_perl_pending_dispatch;
    clay_perl_pending_dispatch.kind   = kind;
    clay_perl_pending_dispatch.result = result;
    clay_perl_callback_depth++;
    call_sv((SV *) ctx->dispatch_cv, G_VOID | G_DISCARD | G_EVAL);
    clay_perl_callback_depth--;
    clay_perl_pending_dispatch = saved;

    /* Test for an exception without truth-testing it: an exception object
     * with an overloaded bool could itself die here, outside any eval. */
    SV *error = ERRSV;
    if (!SvROK(error) && !SvTRUE_nomg(error)) return false;
    clay_perl_stash_callback_error(aTHX_ ctx);
    return true;
}

static SV *userdata_arg(pTHX_ SV *userdata)
{
    return sv_2mortal(newSVsv(userdata ? userdata : &PL_sv_undef));
}

void clay_perl_dispatch_store_result(pTHX_ clay_perl_dispatch_kind kind,
                                     clay_perl_dispatch_result *result,
                                     SV *ret, SV *args_sv)
{
    switch (kind) {
    case CLAY_PERL_DISPATCH_MEASURE_TEXT:
        result->dimensions = clay_dimensions_from_sv(aTHX_ ret, "measure_text callback result");
        return;

    case CLAY_PERL_DISPATCH_QUERY_SCROLL_OFFSET:
        result->vector = clay_vector2_from_sv(aTHX_ ret, "query_scroll_offset callback result");
        return;

    case CLAY_PERL_DISPATCH_TRANSITION_HANDLER: {
        if (!args_sv || !SvROK(args_sv) || SvTYPE(SvRV(args_sv)) != SVt_PVHV) {
            croak("Clay::XS: transition handler replaced its argument hash");
        }
        SvGETMAGIC(ret);
        result->complete = SvOK(ret) ? cBOOL(SvTRUE_nomg(ret)) : true;
        SV **current = hv_fetchs((HV *) SvRV(args_sv), "current", 0);
        if (current && *current) {
            result->transition_data = clay_transition_data_from_sv(
                aTHX_ *current, result->transition_data, "transition handler args.current");
        }
        return;
    }

    case CLAY_PERL_DISPATCH_TRANSITION_SET_INITIAL:
        result->transition_data = clay_transition_data_from_sv(
            aTHX_ ret, result->transition_data, "transition setInitialState result");
        return;

    case CLAY_PERL_DISPATCH_TRANSITION_SET_FINAL:
        result->transition_data = clay_transition_data_from_sv(
            aTHX_ ret, result->transition_data, "transition setFinalState result");
        return;

    case CLAY_PERL_DISPATCH_ERROR_HANDLER:
    case CLAY_PERL_DISPATCH_HOVER:
        return;
    }
    croak("Clay::XS: internal error: unknown dispatch kind %d", (int) kind);
}

/* ---------------------------------------------------------------------------
 * Callback slots and the hover registry.
 * ------------------------------------------------------------------------ */

void clay_perl_replace_sv_slot(pTHX_ SV **slot, SV *new_value)
{
    SV *copy = (new_value && SvOK(new_value)) ? newSVsv(new_value) : NULL;
    SV *old  = *slot;
    *slot = copy;
    SvREFCNT_dec(old);
}

static void make_id_key(uint32_t id, char buf[16])
{
    snprintf(buf, 16, "%u", (unsigned) id);
}

void clay_perl_hover_register(pTHX_ clay_perl_context *ctx,
                              uint32_t element_id, SV *cb, SV *userdata)
{
    AV *entry = newAV();
    av_push(entry, newSVsv(cb));
    av_push(entry, newSVsv(userdata ? userdata : &PL_sv_undef));
    av_push(entry, newSVuv(ctx->frame_generation));

    char key[16];
    make_id_key(element_id, key);
    (void) hv_store(ctx->hover_callbacks, key, (I32) strlen(key), newRV_noinc((SV *) entry), 0);
}

void clay_perl_hover_registry_sweep(pTHX_ clay_perl_context *ctx,
                                    uint32_t keep_generations)
{
    if (ctx->frame_generation < keep_generations) return;
    uint32_t cutoff = ctx->frame_generation - keep_generations;

    /* Collect first, delete afterwards: deleting invalidates the iterator. */
    HV *hv = ctx->hover_callbacks;
    AV *stale = newAV();
    sv_2mortal((SV *) stale);
    HE *he;
    hv_iterinit(hv);
    while ((he = hv_iternext(hv)) != NULL) {
        AV *entry = (AV *) SvRV(HeVAL(he));
        SV **gen_slot = av_fetch(entry, 2, 0);
        if ((uint32_t) SvUV(*gen_slot) <= cutoff) {
            av_push(stale, newSVhek(HeKEY_hek(he)));
        }
    }

    SSize_t count = av_top_index(stale) + 1;
    for (SSize_t i = 0; i < count; i++) {
        SV **key = av_fetch(stale, i, 0);
        (void) hv_delete_ent(hv, *key, G_DISCARD, 0);
    }
}

/* ---------------------------------------------------------------------------
 * Trampoline: text measurement.
 *
 *     $cb->( $text, \%config, $userdata ) -> { width, height } or [ w, h ]
 *
 * Once an error is pending, measurement is skipped (0x0) until the error
 * is raised, so one broken measurer produces one exception per frame.
 * ------------------------------------------------------------------------ */

Clay_Dimensions clay_perl_measure_text_trampoline(Clay_StringSlice text,
                                                  Clay_TextElementConfig *config,
                                                  void *userData)
{
    dTHX;
    Clay_Dimensions zero = { 0, 0 };

    clay_perl_context *ctx = userData ? (clay_perl_context *) userData : clay_perl_current_ctx;
    if (!ctx) return zero;
    if (ctx->pending_error) {
        ctx->measure_cache_poisoned = true;
        return zero;
    }
    if (!ctx->measure_text_cb) {
        clay_perl_stash_error_message(aTHX_ ctx,
            "Clay::XS: text measured but no measure_text function is installed for this context");
        ctx->measure_cache_poisoned = true;
        return zero;
    }

    clay_perl_dispatch_result result;
    memset(&result, 0, sizeof(result));

    ENTER;
    SAVETMPS;
    save_scalar(PL_errgv);
    SV *args[3] = {
        sv_2mortal(clay_perl_utf8_sv(aTHX_ text.chars, text.length)),
        sv_2mortal(clay_text_element_config_to_sv(aTHX_ *config)),
        userdata_arg(aTHX_ ctx->measure_text_userdata),
    };
    bool failed = call_dispatcher(aTHX_ ctx, CLAY_PERL_DISPATCH_MEASURE_TEXT, &result,
                                  ctx->measure_text_cb, args, 3);
    FREETMPS;
    LEAVE;

    if (failed) {
        ctx->measure_cache_poisoned = true;
        return zero;
    }
    return result.dimensions;
}

/* ---------------------------------------------------------------------------
 * Trampoline: error handler.
 *
 *     $cb->( { errorType => $type, errorText => $string }, $userdata )
 *
 * With no Perl handler installed, Clay errors are ignored (as in C).
 * ------------------------------------------------------------------------ */

void clay_perl_error_handler_trampoline(Clay_ErrorData error)
{
    dTHX;
    clay_perl_context *ctx = (clay_perl_context *) error.userData;
    if (!ctx || !ctx->error_handler_cb) return;

    clay_perl_dispatch_result result;
    memset(&result, 0, sizeof(result));

    ENTER;
    SAVETMPS;
    save_scalar(PL_errgv);
    HV *err_hv = newHV();
    (void) hv_stores(err_hv, "errorType", newSViv((IV) error.errorType));
    (void) hv_stores(err_hv, "errorText",
                     clay_perl_utf8_sv(aTHX_ error.errorText.chars, error.errorText.length));
    SV *args[2] = {
        sv_2mortal(newRV_noinc((SV *) err_hv)),
        userdata_arg(aTHX_ ctx->error_handler_userdata),
    };
    (void) call_dispatcher(aTHX_ ctx, CLAY_PERL_DISPATCH_ERROR_HANDLER, &result,
                           ctx->error_handler_cb, args, 2);
    FREETMPS;
    LEAVE;
}

/* ---------------------------------------------------------------------------
 * Trampoline: query scroll offset.
 *
 *     $cb->( $element_id, $userdata ) -> { x, y } or [ x, y ]
 * ------------------------------------------------------------------------ */

Clay_Vector2 clay_perl_query_scroll_offset_trampoline(uint32_t element_id,
                                                      void *userData)
{
    dTHX;
    Clay_Vector2 zero = { 0, 0 };

    clay_perl_context *ctx = userData ? (clay_perl_context *) userData : clay_perl_current_ctx;
    if (!ctx) return zero;
    if (!ctx->query_scroll_offset_cb) {
        clay_perl_stash_error_message(aTHX_ ctx,
            "Clay::XS: external scroll handling is enabled but no query_scroll_offset function is installed for this context");
        return zero;
    }

    clay_perl_dispatch_result result;
    memset(&result, 0, sizeof(result));

    ENTER;
    SAVETMPS;
    save_scalar(PL_errgv);
    SV *args[2] = {
        sv_2mortal(newSVuv(element_id)),
        userdata_arg(aTHX_ ctx->query_scroll_offset_userdata),
    };
    bool failed = call_dispatcher(aTHX_ ctx, CLAY_PERL_DISPATCH_QUERY_SCROLL_OFFSET, &result,
                                  ctx->query_scroll_offset_cb, args, 2);
    FREETMPS;
    LEAVE;

    return failed ? zero : result.vector;
}

/* ---------------------------------------------------------------------------
 * Trampoline: per-element hover.
 *
 *     $cb->( \%element_id, \%pointer_data, $userdata )
 * ------------------------------------------------------------------------ */

void clay_perl_on_hover_trampoline(Clay_ElementId element_id,
                                   Clay_PointerData pointer,
                                   void *userData)
{
    dTHX;
    clay_perl_context *ctx = (clay_perl_context *) userData;
    if (!ctx) return;

    char key[16];
    make_id_key(element_id.id, key);
    SV **entry_slot = hv_fetch(ctx->hover_callbacks, key, (I32) strlen(key), 0);
    if (!entry_slot) return;

    AV *entry = (AV *) SvRV(*entry_slot);
    SV *callback = *av_fetch(entry, 0, 0);
    SV *userdata = *av_fetch(entry, 1, 0);

    clay_perl_dispatch_result result;
    memset(&result, 0, sizeof(result));

    ENTER;
    SAVETMPS;
    save_scalar(PL_errgv);
    SV *args[3] = {
        sv_2mortal(clay_element_id_to_sv(aTHX_ element_id)),
        sv_2mortal(clay_pointer_data_to_sv(aTHX_ pointer)),
        userdata_arg(aTHX_ userdata),
    };
    (void) call_dispatcher(aTHX_ ctx, CLAY_PERL_DISPATCH_HOVER, &result, callback, args, 3);
    FREETMPS;
    LEAVE;
}

/* ---------------------------------------------------------------------------
 * Transition trampolines.
 *
 * All three fish the active context out of the thread-local and call the
 * matching per-context Perl coderef if installed. Without a coderef (or
 * after a failure) they fall back to identity behaviour: the handler
 * reports completion, setInitialState returns the target and
 * setFinalState returns the initial state.
 *
 * args.current is a writeable pointer; the Perl handler updates the
 * `current` entry of the argument hash and the dispatcher copies it back.
 * ------------------------------------------------------------------------ */

bool clay_perl_transition_handler_trampoline(Clay_TransitionCallbackArguments args)
{
    dTHX;
    clay_perl_context *ctx = clay_perl_active_transition_ctx;
    if (!ctx || !ctx->transition_handler_cb) return true;

    clay_perl_dispatch_result result;
    memset(&result, 0, sizeof(result));
    result.complete        = true;
    result.transition_data = *args.current;

    ENTER;
    SAVETMPS;
    save_scalar(PL_errgv);
    HV *args_hv = newHV();
    (void) hv_stores(args_hv, "transitionState", newSViv((IV) args.transitionState));
    (void) hv_stores(args_hv, "initial",         clay_transition_data_to_sv(aTHX_ args.initial));
    (void) hv_stores(args_hv, "target",          clay_transition_data_to_sv(aTHX_ args.target));
    (void) hv_stores(args_hv, "current",         clay_transition_data_to_sv(aTHX_ *args.current));
    (void) hv_stores(args_hv, "elapsedTime",     newSVnv(args.elapsedTime));
    (void) hv_stores(args_hv, "duration",        newSVnv(args.duration));
    (void) hv_stores(args_hv, "properties",      newSVuv((UV) args.properties));
    SV *call_args[2] = {
        sv_2mortal(newRV_noinc((SV *) args_hv)),
        userdata_arg(aTHX_ ctx->transition_userdata),
    };
    bool failed = call_dispatcher(aTHX_ ctx, CLAY_PERL_DISPATCH_TRANSITION_HANDLER, &result,
                                  ctx->transition_handler_cb, call_args, 2);
    FREETMPS;
    LEAVE;

    if (failed) return true;
    *args.current = result.transition_data;
    return result.complete;
}

static Clay_TransitionData dispatch_transition_state(pTHX_ clay_perl_context *ctx,
                                                     clay_perl_dispatch_kind kind,
                                                     SV *callback,
                                                     Clay_TransitionData state,
                                                     Clay_TransitionProperty properties)
{
    clay_perl_dispatch_result result;
    memset(&result, 0, sizeof(result));
    result.transition_data = state;

    ENTER;
    SAVETMPS;
    save_scalar(PL_errgv);
    SV *args[3] = {
        sv_2mortal(clay_transition_data_to_sv(aTHX_ state)),
        sv_2mortal(newSVuv((UV) properties)),
        userdata_arg(aTHX_ ctx->transition_userdata),
    };
    bool failed = call_dispatcher(aTHX_ ctx, kind, &result, callback, args, 3);
    FREETMPS;
    LEAVE;

    return failed ? state : result.transition_data;
}

Clay_TransitionData clay_perl_transition_set_initial_trampoline(
    Clay_TransitionData target, Clay_TransitionProperty properties)
{
    dTHX;
    clay_perl_context *ctx = clay_perl_active_transition_ctx;
    if (!ctx || !ctx->transition_set_initial_cb) return target;
    return dispatch_transition_state(aTHX_ ctx, CLAY_PERL_DISPATCH_TRANSITION_SET_INITIAL,
                                     ctx->transition_set_initial_cb, target, properties);
}

Clay_TransitionData clay_perl_transition_set_final_trampoline(
    Clay_TransitionData initial, Clay_TransitionProperty properties)
{
    dTHX;
    clay_perl_context *ctx = clay_perl_active_transition_ctx;
    if (!ctx || !ctx->transition_set_final_cb) return initial;
    return dispatch_transition_state(aTHX_ ctx, CLAY_PERL_DISPATCH_TRANSITION_SET_FINAL,
                                     ctx->transition_set_final_cb, initial, properties);
}
