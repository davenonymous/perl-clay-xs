/*
 * callbacks.c - C trampolines that forward Clay's function-pointer
 * callbacks into Perl coderefs.
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
 * Each is bridged by a fixed C function defined here. The C function
 * reaches into a clay_perl_context to find the Perl coderef and invokes
 * it through Perl's stack-based call API. Because Clay calls these in
 * normal C control flow (not pp_*), we manage our own ENTER/SAVETMPS
 * scopes.
 *
 * Threading the active context to the trampolines:
 *
 *   - For per-context callbacks (measure_text, error_handler,
 *     query_scroll_offset), Clay's userData slot carries a clay_perl_context*
 *     directly. The Perl-side stash is found via that pointer.
 *
 *   - For hover, the element id is supplied as a function argument; the
 *     context is supplied as Clay's userData. The trampoline looks up the
 *     registered Perl coderef in ctx->hover_callbacks.
 *
 *   - For transitions, the callback signatures lack any way to pass our
 *     context pointer. We solve this with a single thread-local
 *     "active_transition_ctx" set by the EndLayout wrapper just before
 *     Clay processes transitions. This is safe because Clay does not
 *     re-enter itself and Perl is single-threaded per interpreter.
 *
 * Generation-based cleanup of the hover registry happens in
 * clay_perl_hover_registry_sweep, called from clay_perl_arena_reset.
 * Entries whose generation is older than the configured "keep" window
 * are dropped. The window defaults to 2 frames so a hover handler set in
 * frame N is still usable in frame N+1 even if the user forgot to
 * re-register.
 */

#include "clay_perl.h"

#include <stdio.h>
#include <string.h>

/* ---------------------------------------------------------------------------
 * Surface a Perl exception that fired inside a Clay callback.
 *
 * Clay's callback signatures have no exception channel, so we cannot
 * propagate the error up to the calling Clay_* function. The next best
 * thing is to emit a warning so that the user at least sees the error
 * message; silent swallowing would violate "Fail Fast, Fail Loud".
 *
 * We use Perl's warn() machinery so the message respects the
 * application's $SIG{__WARN__} hook.
 * ------------------------------------------------------------------------ */

static void surface_trampoline_error(pTHX_ const char *where)
{
    if (!SvTRUE(ERRSV)) return;
    STRLEN len;
    const char *msg = SvPV(ERRSV, len);
    Perl_warn(aTHX_ "Clay::Layout: %s callback threw: %.*s",
              where, (int) len, msg);
    sv_setpvs(ERRSV, "");
}

/* ---------------------------------------------------------------------------
 * Thread-local active transition context.
 *
 * Set by the Clay_EndLayout wrapper before calling Clay_EndLayout. Reset
 * to NULL immediately after. The transition trampolines fall back to
 * doing nothing if this is NULL, which keeps them safe to call even
 * outside an EndLayout.
 * ------------------------------------------------------------------------ */

#if defined(__GNUC__) || defined(__clang__)
__thread clay_perl_context *clay_perl_active_transition_ctx = NULL;
#elif defined(_MSC_VER)
__declspec(thread) clay_perl_context *clay_perl_active_transition_ctx = NULL;
#else
clay_perl_context *clay_perl_active_transition_ctx = NULL;
#endif

/* ---------------------------------------------------------------------------
 * Helpers for storing/loading [coderef, userdata, generation] arrayrefs
 * keyed by element id (decimal string).
 * ------------------------------------------------------------------------ */

static void make_id_key(uint32_t id, char buf[16])
{
    snprintf(buf, 16, "%u", (unsigned) id);
}

static SV *new_hover_entry(pTHX_ SV *coderef, SV *userdata, uint32_t generation)
{
    AV *av = newAV();
    av_push(av, SvREFCNT_inc(coderef));
    av_push(av, userdata ? SvREFCNT_inc(userdata) : newSV(0));
    av_push(av, newSVuv(generation));
    return newRV_noinc((SV *) av);
}

void clay_perl_hover_register(pTHX_ clay_perl_context *ctx,
                              uint32_t element_id, SV *cb, SV *userdata)
{
    if (!ctx || !ctx->hover_callbacks) return;
    char key[16];
    make_id_key(element_id, key);
    SV *entry = new_hover_entry(aTHX_ cb, userdata, ctx->hover_generation);
    hv_store(ctx->hover_callbacks, key, (I32) strlen(key), entry, 0);
}

void clay_perl_hover_registry_sweep(pTHX_ clay_perl_context *ctx,
                                    uint32_t keep_generations)
{
    if (!ctx || !ctx->hover_callbacks) return;

    /* Avoid underflow when hover_generation is small early in the context's
     * life. The check below uses ctx->hover_generation - keep_generations as
     * the cutoff; if that would wrap, skip the sweep. */
    if (ctx->hover_generation < keep_generations) return;
    uint32_t cutoff = ctx->hover_generation - keep_generations;

    HV *hv = ctx->hover_callbacks;
    /* Collect keys-to-delete first to avoid mutating during iteration. */
    AV *to_delete = newAV();
    hv_iterinit(hv);
    HE *he;
    while ((he = hv_iternext(hv)) != NULL) {
        SV *val = HeVAL(he);
        if (!val || !SvROK(val) || SvTYPE(SvRV(val)) != SVt_PVAV) continue;
        AV *av = (AV *) SvRV(val);
        SV **gen_slot = av_fetch(av, av_len(av), 0);
        if (!gen_slot || !*gen_slot) continue;
        uint32_t gen = (uint32_t) SvUV(*gen_slot);
        if (gen < cutoff) {
            I32 keylen;
            const char *key = hv_iterkey(he, &keylen);
            av_push(to_delete, newSVpvn(key, keylen));
        }
    }

    SSize_t n = av_top_index(to_delete) + 1;
    for (SSize_t i = 0; i < n; i++) {
        SV **slot = av_fetch(to_delete, i, 0);
        if (!slot || !*slot) continue;
        STRLEN keylen;
        const char *key = SvPV(*slot, keylen);
        hv_delete(hv, key, (I32) keylen, G_DISCARD);
    }
    SvREFCNT_dec((SV *) to_delete);
}

/* ---------------------------------------------------------------------------
 * Transition handler installation.
 * ------------------------------------------------------------------------ */

static void replace_sv_slot(SV **slot, SV *new_value)
{
    if (*slot) {
        SvREFCNT_dec(*slot);
    }
    *slot = (new_value && SvOK(new_value)) ? SvREFCNT_inc(new_value) : NULL;
}

void clay_perl_set_transition_handler(pTHX_ clay_perl_context *ctx,
                                      SV *handler, SV *set_initial,
                                      SV *set_final, SV *userdata)
{
    if (!ctx) return;
    replace_sv_slot(&ctx->transition_handler_cb,     handler);
    replace_sv_slot(&ctx->transition_set_initial_cb, set_initial);
    replace_sv_slot(&ctx->transition_set_final_cb,   set_final);
    replace_sv_slot(&ctx->transition_userdata,       userdata);
}

/* ---------------------------------------------------------------------------
 * Trampoline: text measurement.
 *
 * Clay invokes us with (StringSlice text, TextElementConfig *config, void *userData).
 * The Perl callback is called as:
 *
 *     $cb->( $text_string, \%config_hash, $userdata_sv ) -> { width, height }
 * ------------------------------------------------------------------------ */

Clay_Dimensions clay_perl_measure_text_trampoline(Clay_StringSlice text,
                                                  Clay_TextElementConfig *config,
                                                  void *userData)
{
    dTHX;
    Clay_Dimensions zero = { 0, 0 };

    clay_perl_context *ctx = (clay_perl_context *) userData;
    if (!ctx || !ctx->measure_text_cb) return zero;

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    XPUSHs(sv_2mortal(clay_string_slice_to_sv(aTHX_ text)));
    XPUSHs(sv_2mortal(clay_text_element_config_to_sv(aTHX_ *config)));
    XPUSHs(sv_2mortal(newSVsv(ctx->measure_text_userdata
                              ? ctx->measure_text_userdata
                              : &PL_sv_undef)));
    PUTBACK;

    int count = call_sv(ctx->measure_text_cb, G_SCALAR | G_EVAL);

    SPAGAIN;

    Clay_Dimensions result = zero;
    if (SvTRUE(ERRSV)) {
        if (count >= 1) (void) POPs;
        surface_trampoline_error(aTHX_ "measure_text");
    } else if (count >= 1) {
        SV *ret = POPs;
        if (SvOK(ret)) {
            result = clay_dimensions_from_sv(aTHX_ ret);
        }
    }

    PUTBACK;
    FREETMPS;
    LEAVE;
    return result;
}

/* ---------------------------------------------------------------------------
 * Trampoline: error handler.
 *
 *     $cb->( { errorType => $type, errorText => $string }, $userdata )
 * ------------------------------------------------------------------------ */

void clay_perl_error_handler_trampoline(Clay_ErrorData error)
{
    dTHX;
    clay_perl_context *ctx = (clay_perl_context *) error.userData;
    if (!ctx || !ctx->error_handler_cb) return;

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    HV *err_hv = newHV();
    hv_store(err_hv, "errorType", 9, newSViv((IV) error.errorType), 0);
    if (error.errorText.chars && error.errorText.length > 0) {
        hv_store(err_hv, "errorText", 9,
                 newSVpvn(error.errorText.chars, error.errorText.length), 0);
    } else {
        hv_store(err_hv, "errorText", 9, newSVpvs(""), 0);
    }

    XPUSHs(sv_2mortal(newRV_noinc((SV *) err_hv)));
    XPUSHs(sv_2mortal(newSVsv(ctx->error_handler_userdata
                              ? ctx->error_handler_userdata
                              : &PL_sv_undef)));
    PUTBACK;

    call_sv(ctx->error_handler_cb, G_VOID | G_DISCARD | G_EVAL);
    surface_trampoline_error(aTHX_ "error_handler");

    FREETMPS;
    LEAVE;
}

/* ---------------------------------------------------------------------------
 * Trampoline: query scroll offset.
 *
 *     $cb->( $element_id, $userdata ) -> [ x, y ] or { x => , y => }
 * ------------------------------------------------------------------------ */

Clay_Vector2 clay_perl_query_scroll_offset_trampoline(uint32_t element_id,
                                                      void *userData)
{
    dTHX;
    Clay_Vector2 zero = { 0, 0 };

    clay_perl_context *ctx = (clay_perl_context *) userData;
    if (!ctx || !ctx->query_scroll_offset_cb) return zero;

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    XPUSHs(sv_2mortal(newSVuv(element_id)));
    XPUSHs(sv_2mortal(newSVsv(ctx->query_scroll_offset_userdata
                              ? ctx->query_scroll_offset_userdata
                              : &PL_sv_undef)));
    PUTBACK;

    int count = call_sv(ctx->query_scroll_offset_cb, G_SCALAR | G_EVAL);
    SPAGAIN;

    Clay_Vector2 result = zero;
    if (SvTRUE(ERRSV)) {
        if (count >= 1) (void) POPs;
        surface_trampoline_error(aTHX_ "query_scroll_offset");
    } else if (count >= 1) {
        SV *ret = POPs;
        if (SvOK(ret)) {
            result = clay_vector2_from_sv(aTHX_ ret);
        }
    }

    PUTBACK;
    FREETMPS;
    LEAVE;
    return result;
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
    if (!ctx || !ctx->hover_callbacks) return;

    char key[16];
    make_id_key(element_id.id, key);
    SV **entry_slot = hv_fetch(ctx->hover_callbacks, key, (I32) strlen(key), 0);
    if (!entry_slot || !*entry_slot) return;
    if (!SvROK(*entry_slot) || SvTYPE(SvRV(*entry_slot)) != SVt_PVAV) return;

    AV *entry = (AV *) SvRV(*entry_slot);
    SV **cb_slot       = av_fetch(entry, 0, 0);
    SV **userdata_slot = av_fetch(entry, 1, 0);
    if (!cb_slot || !*cb_slot) return;

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    XPUSHs(sv_2mortal(clay_element_id_to_sv(aTHX_ element_id)));
    XPUSHs(sv_2mortal(clay_pointer_data_to_sv(aTHX_ pointer)));
    XPUSHs(sv_2mortal(newSVsv(userdata_slot && *userdata_slot
                              ? *userdata_slot : &PL_sv_undef)));
    PUTBACK;

    call_sv(*cb_slot, G_VOID | G_DISCARD | G_EVAL);
    surface_trampoline_error(aTHX_ "on_hover");

    FREETMPS;
    LEAVE;
}

/* ---------------------------------------------------------------------------
 * Transition trampolines.
 *
 * All three callbacks share the same dispatch pattern: they fish the
 * active context out of the thread-local, then call the matching
 * per-context Perl coderef if installed. If no coderef is installed or
 * the context is missing, they fall back to safe identity behaviour.
 *
 * args.current is a writeable pointer; the Perl handler is expected to
 * mutate it via the returned hashref. We copy the returned hash back
 * into *args.current after the call.
 * ------------------------------------------------------------------------ */

static SV *transition_data_to_sv(pTHX_ Clay_TransitionData data)
{
    HV *hv = newHV();
    hv_store(hv, "boundingBox",     11, clay_bounding_box_to_sv(aTHX_ data.boundingBox), 0);
    hv_store(hv, "backgroundColor", 15, clay_color_to_sv(aTHX_ data.backgroundColor), 0);
    hv_store(hv, "overlayColor",    12, clay_color_to_sv(aTHX_ data.overlayColor), 0);
    hv_store(hv, "borderColor",     11, clay_color_to_sv(aTHX_ data.borderColor), 0);
    hv_store(hv, "borderWidth",     11, clay_border_width_to_sv(aTHX_ data.borderWidth), 0);
    return newRV_noinc((SV *) hv);
}

static Clay_TransitionData transition_data_from_sv(pTHX_ SV *sv)
{
    Clay_TransitionData d;
    memset(&d, 0, sizeof(d));
    if (!sv || !SvOK(sv) || !SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) return d;
    HV *hv = (HV *) SvRV(sv);

    SV **slot;
    if ((slot = hv_fetchs(hv, "boundingBox", 0)))
        d.boundingBox = clay_bounding_box_from_sv(aTHX_ *slot);
    if ((slot = hv_fetchs(hv, "backgroundColor", 0)))
        d.backgroundColor = clay_color_from_sv(aTHX_ *slot);
    if ((slot = hv_fetchs(hv, "overlayColor", 0)))
        d.overlayColor = clay_color_from_sv(aTHX_ *slot);
    if ((slot = hv_fetchs(hv, "borderColor", 0)))
        d.borderColor = clay_color_from_sv(aTHX_ *slot);
    if ((slot = hv_fetchs(hv, "borderWidth", 0)))
        d.borderWidth = clay_border_width_from_sv(aTHX_ *slot);
    return d;
}

bool clay_perl_transition_handler_trampoline(Clay_TransitionCallbackArguments args)
{
    dTHX;
    clay_perl_context *ctx = clay_perl_active_transition_ctx;
    if (!ctx || !ctx->transition_handler_cb) {
        /* No Perl handler - report completion immediately so Clay doesn't
         * spin waiting for us. */
        return true;
    }

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    HV *args_hv = newHV();
    hv_store(args_hv, "transitionState", 15, newSViv((IV) args.transitionState), 0);
    hv_store(args_hv, "initial",          7, transition_data_to_sv(aTHX_ args.initial), 0);
    hv_store(args_hv, "target",           6, transition_data_to_sv(aTHX_ args.target), 0);
    hv_store(args_hv, "current",          7, transition_data_to_sv(aTHX_ *args.current), 0);
    hv_store(args_hv, "elapsedTime",     11, newSVnv(args.elapsedTime), 0);
    hv_store(args_hv, "duration",         8, newSVnv(args.duration), 0);
    hv_store(args_hv, "properties",      10, newSVuv((UV) args.properties), 0);

    XPUSHs(sv_2mortal(newRV_noinc((SV *) args_hv)));
    XPUSHs(sv_2mortal(newSVsv(ctx->transition_userdata
                              ? ctx->transition_userdata : &PL_sv_undef)));
    PUTBACK;

    int count = call_sv(ctx->transition_handler_cb, G_SCALAR | G_EVAL);
    SPAGAIN;

    bool complete = true;
    if (SvTRUE(ERRSV)) {
        if (count >= 1) (void) POPs;
        surface_trampoline_error(aTHX_ "transition_handler");
        complete = true;
    } else if (count >= 1) {
        SV *ret = POPs;
        complete = SvOK(ret) ? (SvTRUE(ret) ? true : false) : true;
    }

    /* If the Perl handler mutated args_hv->{current}, write the new state
     * back through args.current. We look up the key fresh in case the
     * handler replaced the entire hash. */
    SV **current_slot = hv_fetchs(args_hv, "current", 0);
    if (current_slot && *current_slot && args.current) {
        *args.current = transition_data_from_sv(aTHX_ *current_slot);
    }

    PUTBACK;
    FREETMPS;
    LEAVE;
    return complete;
}

Clay_TransitionData clay_perl_transition_set_initial_trampoline(
    Clay_TransitionData target, Clay_TransitionProperty properties)
{
    dTHX;
    clay_perl_context *ctx = clay_perl_active_transition_ctx;
    if (!ctx || !ctx->transition_set_initial_cb) return target;

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    XPUSHs(sv_2mortal(transition_data_to_sv(aTHX_ target)));
    XPUSHs(sv_2mortal(newSVuv((UV) properties)));
    XPUSHs(sv_2mortal(newSVsv(ctx->transition_userdata
                              ? ctx->transition_userdata : &PL_sv_undef)));
    PUTBACK;

    int count = call_sv(ctx->transition_set_initial_cb, G_SCALAR | G_EVAL);
    SPAGAIN;

    Clay_TransitionData result = target;
    if (SvTRUE(ERRSV)) {
        if (count >= 1) (void) POPs;
        surface_trampoline_error(aTHX_ "transition_set_initial");
    } else if (count >= 1) {
        SV *ret = POPs;
        if (SvOK(ret)) {
            result = transition_data_from_sv(aTHX_ ret);
        }
    }

    PUTBACK;
    FREETMPS;
    LEAVE;
    return result;
}

Clay_TransitionData clay_perl_transition_set_final_trampoline(
    Clay_TransitionData initial, Clay_TransitionProperty properties)
{
    dTHX;
    clay_perl_context *ctx = clay_perl_active_transition_ctx;
    if (!ctx || !ctx->transition_set_final_cb) return initial;

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    XPUSHs(sv_2mortal(transition_data_to_sv(aTHX_ initial)));
    XPUSHs(sv_2mortal(newSVuv((UV) properties)));
    XPUSHs(sv_2mortal(newSVsv(ctx->transition_userdata
                              ? ctx->transition_userdata : &PL_sv_undef)));
    PUTBACK;

    int count = call_sv(ctx->transition_set_final_cb, G_SCALAR | G_EVAL);
    SPAGAIN;

    Clay_TransitionData result = initial;
    if (SvTRUE(ERRSV)) {
        if (count >= 1) (void) POPs;
        surface_trampoline_error(aTHX_ "transition_set_final");
    } else if (count >= 1) {
        SV *ret = POPs;
        if (SvOK(ret)) {
            result = transition_data_from_sv(aTHX_ ret);
        }
    }

    PUTBACK;
    FREETMPS;
    LEAVE;
    return result;
}
