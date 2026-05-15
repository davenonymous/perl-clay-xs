/*
 * clay_perl.h - Shared types and prototypes for the Clay::Layout XS binding.
 *
 * This header is included by the XS file and by every helper .c file under
 * src/. It pulls in Perl's API headers and the Clay v0.14 header (without
 * its implementation - exactly one file defines CLAY_IMPLEMENTATION).
 *
 * Conventions used throughout:
 *
 *   - clay_perl_*   : functions implemented in this binding
 *   - cpc_          : abbreviation for "Clay Perl Context" used on fields
 *   - SV/HV/AV      : standard Perl reference-counted value types
 *
 * Memory ownership rules (read these before touching the helpers):
 *
 *   - The per-frame string arena is owned by clay_perl_context. Buffers
 *     allocated from it remain valid until the next Clay_BeginLayout call,
 *     at which point the arena is reset (offset -> 0). All Clay_String
 *     values passed in from Perl strings live in this arena; their
 *     isStaticallyAllocated flag is always false.
 *
 *   - The callback SV slots (measure_text_cb, error_handler_cb,
 *     query_scroll_offset_cb) hold one increment of refcount. They are
 *     replaced atomically: install increments the new one, decrements the
 *     old one, then writes the slot.
 *
 *   - hover_callbacks and transition_callbacks are HVs that contain
 *     blessed arrayrefs (one ref + userdata per element_id). Standard
 *     Perl GC rules apply; the HV holds one refcount per entry.
 *
 *   - clay_arena_memory is a malloc()-ed buffer owned by the Perl context.
 *     It is freed on context DESTROY. Clay itself never frees it.
 */

#ifndef CLAY_PERL_H
#define CLAY_PERL_H

/*
 * We intentionally do NOT define PERL_NO_GET_CONTEXT.
 *
 * With PERL_NO_GET_CONTEXT every macro that uses the Perl interpreter
 * (newSV, SvREFCNT_dec, hv_store, ...) requires an explicit `aTHX` /
 * `pTHX` argument to be threaded through every C helper. That doubles
 * the signature noise on every internal helper without measurable
 * performance gain in a UI-layout workload.
 *
 * Helpers that need a thread context will use `dTHX` locally. Trampolines
 * called by Clay (which knows nothing about Perl) also use `dTHX`.
 */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "clay/clay.h"

#include <stddef.h>
#include <stdint.h>

/* ---------------------------------------------------------------------------
 * Per-Perl-context state.
 *
 * One of these is allocated per call to clay_perl_context_new() (which wraps
 * Clay_Initialize). A blessed Clay::Layout::Context scalar ref in Perl
 * holds a pointer to one of these. Cleanup happens in DESTROY.
 * ------------------------------------------------------------------------ */

typedef struct clay_perl_context {
    /* Underlying Clay state. */
    Clay_Context *clay_ctx;
    Clay_Arena    clay_arena;
    char         *clay_arena_memory;

    /* Per-frame string arena. Grows monotonically; reset on BeginLayout. */
    char   *string_arena;
    size_t  string_arena_used;
    size_t  string_arena_capacity;

    /* Global-per-context callbacks. Each holds one refcount. */
    SV *measure_text_cb;
    SV *measure_text_userdata;
    SV *error_handler_cb;
    SV *error_handler_userdata;
    SV *query_scroll_offset_cb;
    SV *query_scroll_offset_userdata;

    /* Per-element hover callbacks. Keyed by element id (uint32_t as decimal
     * string). Each value is an arrayref [coderef, userdata, generation]. */
    HV       *hover_callbacks;
    uint32_t  hover_generation;

    /* Transition callbacks.
     *
     * NOTE on the design: Clay's transition callback signatures
     * (Clay_TransitionElementConfig.handler / enter.setInitialState /
     * exit.setFinalState) do not pass the element id to the callback. That
     * means a single C trampoline cannot demultiplex back to a per-element
     * Perl coderef the way Clay_OnHover can. See src/clay/clay.h:4685,
     * src/clay/clay.h:4600, src/clay/clay.h:4486 for the call sites that
     * confirm this.
     *
     * For Phase 1 we expose a single per-context handler set. If the user
     * stores transition handlers in an element declaration's `transition`
     * hashref, we install our trampolines (which call these per-context
     * slots) on every element. The user's handler can dispatch on the
     * transition state and the values in args.target if it needs to
     * distinguish elements. Per-element handlers will require a small
     * upstream patch and are intentionally deferred. */
    SV *transition_handler_cb;
    SV *transition_set_initial_cb;
    SV *transition_set_final_cb;
    SV *transition_userdata;
} clay_perl_context;

/* ---------------------------------------------------------------------------
 * Context lifecycle (src/clay_perl_context.c).
 * ------------------------------------------------------------------------ */

clay_perl_context *clay_perl_context_new(pTHX_ size_t clay_arena_capacity);
void               clay_perl_context_free(pTHX_ clay_perl_context *self);

/* Bless the given pointer as a Clay::Layout::Context. Returns a new mortal SV. */
SV *clay_perl_context_to_sv(pTHX_ clay_perl_context *self);

/* Recover a clay_perl_context * from a blessed SV. Croaks if the SV is not a
 * Clay::Layout::Context. */
clay_perl_context *clay_perl_context_from_sv(pTHX_ SV *sv);

/* ---------------------------------------------------------------------------
 * Per-frame string arena (src/clay_perl_context.c).
 * ------------------------------------------------------------------------ */

void        clay_perl_arena_reset(clay_perl_context *self);
Clay_String clay_perl_arena_copy_pv(pTHX_ clay_perl_context *self, SV *sv);
Clay_String clay_perl_arena_copy_bytes(clay_perl_context *self, const char *bytes, size_t len);

/* ---------------------------------------------------------------------------
 * HV/AV <-> Clay struct converters (src/marshal.c).
 *
 * Naming convention:
 *   *_from_sv  : Perl value -> C struct (used at function entry)
 *   *_to_sv    : C struct  -> Perl value (used at function return)
 *
 * All _from_sv helpers croak on invalid input (Law of Fail Fast).
 * They never return half-initialised structs.
 * ------------------------------------------------------------------------ */

Clay_Color           clay_color_from_sv(pTHX_ SV *sv);
SV                  *clay_color_to_sv(pTHX_ Clay_Color value);

Clay_Vector2         clay_vector2_from_sv(pTHX_ SV *sv);
SV                  *clay_vector2_to_sv(pTHX_ Clay_Vector2 value);

Clay_Dimensions      clay_dimensions_from_sv(pTHX_ SV *sv);
SV                  *clay_dimensions_to_sv(pTHX_ Clay_Dimensions value);

Clay_BoundingBox     clay_bounding_box_from_sv(pTHX_ SV *sv);
SV                  *clay_bounding_box_to_sv(pTHX_ Clay_BoundingBox value);

Clay_CornerRadius    clay_corner_radius_from_sv(pTHX_ SV *sv);
SV                  *clay_corner_radius_to_sv(pTHX_ Clay_CornerRadius value);

Clay_Padding         clay_padding_from_sv(pTHX_ SV *sv);
SV                  *clay_padding_to_sv(pTHX_ Clay_Padding value);

Clay_BorderWidth     clay_border_width_from_sv(pTHX_ SV *sv);
SV                  *clay_border_width_to_sv(pTHX_ Clay_BorderWidth value);

Clay_ChildAlignment  clay_child_alignment_from_sv(pTHX_ SV *sv);
SV                  *clay_child_alignment_to_sv(pTHX_ Clay_ChildAlignment value);

Clay_SizingAxis      clay_sizing_axis_from_sv(pTHX_ SV *sv);
SV                  *clay_sizing_axis_to_sv(pTHX_ Clay_SizingAxis value);

Clay_Sizing          clay_sizing_from_sv(pTHX_ SV *sv);
SV                  *clay_sizing_to_sv(pTHX_ Clay_Sizing value);

Clay_LayoutConfig    clay_layout_config_from_sv(pTHX_ SV *sv);
SV                  *clay_layout_config_to_sv(pTHX_ Clay_LayoutConfig value);

Clay_TextElementConfig clay_text_element_config_from_sv(pTHX_ SV *sv);
SV                    *clay_text_element_config_to_sv(pTHX_ Clay_TextElementConfig value);

Clay_AspectRatioElementConfig clay_aspect_ratio_config_from_sv(pTHX_ SV *sv);
Clay_ImageElementConfig       clay_image_config_from_sv(pTHX_ SV *sv);
Clay_CustomElementConfig      clay_custom_config_from_sv(pTHX_ SV *sv);
Clay_ClipElementConfig        clay_clip_config_from_sv(pTHX_ SV *sv);
Clay_BorderElementConfig      clay_border_config_from_sv(pTHX_ SV *sv);
Clay_FloatingElementConfig    clay_floating_config_from_sv(pTHX_ SV *sv);

Clay_ElementDeclaration       clay_element_declaration_from_sv(pTHX_ clay_perl_context *ctx, SV *sv);

Clay_ElementId      clay_element_id_from_sv(pTHX_ SV *sv);
SV                 *clay_element_id_to_sv(pTHX_ Clay_ElementId id);

Clay_PointerData    clay_pointer_data_from_sv(pTHX_ SV *sv);
SV                 *clay_pointer_data_to_sv(pTHX_ Clay_PointerData data);

/* Render command output (src/marshal.c). */
SV *clay_render_command_to_sv(pTHX_ const Clay_RenderCommand *cmd);
SV *clay_render_command_array_to_sv(pTHX_ const Clay_RenderCommandArray *array);

/* ScrollContainerData and ElementData returns. */
SV *clay_scroll_container_data_to_sv(pTHX_ Clay_ScrollContainerData data);
SV *clay_element_data_to_sv(pTHX_ Clay_ElementData data);

/* String slice -> Perl string (read-only, copied). */
SV *clay_string_slice_to_sv(pTHX_ Clay_StringSlice slice);

/* ---------------------------------------------------------------------------
 * Callback trampolines (src/callbacks.c).
 *
 * These are static C functions that Clay holds as function pointers. They
 * forward into Perl via the clay_perl_context pointer threaded through
 * userData (or through the global current-context for hover/transition).
 * ------------------------------------------------------------------------ */

Clay_Dimensions clay_perl_measure_text_trampoline(
    Clay_StringSlice text,
    Clay_TextElementConfig *config,
    void *userData);

void clay_perl_error_handler_trampoline(Clay_ErrorData error);

Clay_Vector2 clay_perl_query_scroll_offset_trampoline(
    uint32_t element_id,
    void *userData);

void clay_perl_on_hover_trampoline(
    Clay_ElementId element_id,
    Clay_PointerData pointer,
    void *userData);

/* Returns true (1) when this transition handler completes. */
bool clay_perl_transition_handler_trampoline(Clay_TransitionCallbackArguments args);
Clay_TransitionData clay_perl_transition_set_initial_trampoline(
    Clay_TransitionData target, Clay_TransitionProperty properties);
Clay_TransitionData clay_perl_transition_set_final_trampoline(
    Clay_TransitionData initial, Clay_TransitionProperty properties);

/* Thread-local pointer to the context currently inside Clay_EndLayout.
 * The transition trampolines read this to find their per-context handlers.
 * The Clay_EndLayout XS wrapper sets it before calling Clay_EndLayout and
 * resets it to NULL immediately afterward. */
#if defined(__GNUC__) || defined(__clang__)
extern __thread clay_perl_context *clay_perl_active_transition_ctx;
#elif defined(_MSC_VER)
extern __declspec(thread) clay_perl_context *clay_perl_active_transition_ctx;
#else
extern clay_perl_context *clay_perl_active_transition_ctx;
#endif

/* ---------------------------------------------------------------------------
 * Internal hover/transition registry helpers (src/callbacks.c).
 * ------------------------------------------------------------------------ */

void clay_perl_hover_register(pTHX_ clay_perl_context *ctx,
                              uint32_t element_id, SV *cb, SV *userdata);

/* Drop hover entries older than (current_generation - keep_generations).
 * Called from clay_perl_arena_reset at BeginLayout time. */
void clay_perl_hover_registry_sweep(pTHX_ clay_perl_context *ctx,
                                    uint32_t keep_generations);

/* Replace one of the three transition callback slots, managing refcounts. */
void clay_perl_set_transition_handler(pTHX_ clay_perl_context *ctx,
                                      SV *handler, SV *set_initial,
                                      SV *set_final, SV *userdata);

#endif /* CLAY_PERL_H */
