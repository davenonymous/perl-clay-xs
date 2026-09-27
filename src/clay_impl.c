/*
 * clay_impl.c - The one and only compilation unit that materialises the
 * Clay v0.14 implementation, plus the few binding helpers that need to
 * see Clay's internals (declared in src/clay_impl_helpers.h).
 *
 * Clay is a header-only library. The convention requires exactly one .c
 * file in the project to define CLAY_IMPLEMENTATION before including
 * clay.h; every other file includes clay.h normally and gets only the
 * declarations. The helpers below live here because struct Clay_Context,
 * the default counts and the arena routines are only visible inside the
 * implementation section. This file includes no Perl headers.
 *
 * The diagnostic suppression below silences three categories of warning
 * that Clay v0.14 emits under -Wall -Wextra. They are upstream issues
 * (unused locals, sign mismatch in a comparison) and are not bugs in
 * the binding. Suppressing them here keeps Clay::XS's own diagnostic
 * output clean for users running tests under default flags.
 */

#if defined(__GNUC__) || defined(__clang__)
# pragma GCC diagnostic push
# pragma GCC diagnostic ignored "-Wunused-variable"
# pragma GCC diagnostic ignored "-Wunused-function"
# pragma GCC diagnostic ignored "-Wsign-compare"
#endif

#define CLAY_IMPLEMENTATION
#include "clay/clay.h"

#if defined(__GNUC__) || defined(__clang__)
# pragma GCC diagnostic pop
#endif

#include "clay_impl_helpers.h"

/* Upper bound on the alignment padding Clay adds between its arena arrays:
 * less than 64 bytes per array, and Clay allocates fewer than 64 arrays. */
#define CLAY_PERL_ALIGNMENT_SLACK ((uint64_t) 64 * 64)

bool clay_perl_clay_has_exiting_transitions(void)
{
    Clay_Context *context = Clay_GetCurrentContext();
    if (!context) return false;
    for (int32_t i = 0; i < context->transitionDatas.length; ++i) {
        if (context->transitionDatas.internalArray[i].state == CLAY_TRANSITION_STATE_EXITING) {
            return true;
        }
    }
    return false;
}

void clay_perl_clay_default_counts(int32_t *element_count, int32_t *word_count)
{
    *element_count = Clay__defaultMaxElementCount;
    *word_count    = Clay__defaultMaxMeasureTextWordCacheCount;
}

/* Clay_MinMemorySize() for explicit counts. Exact while every array fits
 * Clay's 32-bit size arithmetic, which holds for the small counts the
 * upper-bound computation below uses. */
static uint64_t min_memory_size_for(int32_t element_count, int32_t word_count)
{
    Clay_Context fake_context = {
        .maxElementCount = element_count,
        .maxMeasureTextCacheWordCount = word_count,
        .internalArena = {
            .capacity = SIZE_MAX,
            .memory = NULL,
        }
    };
    Clay__Context_Allocate_Arena(&fake_context.internalArena);
    Clay__InitializePersistentMemory(&fake_context);
    Clay__InitializeEphemeralMemory(&fake_context);
    return (uint64_t) fake_context.internalArena.nextAllocation + 128;
}

/* Bytes the sizing-group patch spends beyond 2 x element_count int32 slots:
 * it rounds its hash table up to the next power of two of at least
 * 2 x maxElementCount slots (see Clay__InitializeEphemeralMemory). */
static uint64_t sizing_group_slot_rounding(int32_t element_count)
{
    uint64_t wanted = 2 * (uint64_t) element_count;
    uint64_t slots  = 1;
    while (slots < wanted) slots *= 2;
    return (slots - wanted) * sizeof(int32_t);
}

/* Clay's arena size is affine in the two counts except for alignment
 * padding and the sizing-group table's power-of-two rounding: with both
 * counts a power of two of at least 64, every count-sized array is a
 * multiple of 64 bytes and the table is exactly 2 x count slots, so the
 * per-element and per-word costs fall out exactly from three small
 * probes. The bound adds the table rounding and the worst-case padding
 * for arbitrary counts. */
uint64_t clay_perl_clay_arena_bytes_upper_bound(int32_t element_count, int32_t word_count)
{
    uint64_t base        = min_memory_size_for(64, 64);
    uint64_t per_element = (min_memory_size_for(128, 64) - base) / 64;
    uint64_t per_word    = (min_memory_size_for(64, 128) - base) / 64;
    uint64_t fixed       = base - 64 * per_element - 64 * per_word;

    return fixed
         + per_element * (uint64_t) element_count
         + per_word    * (uint64_t) word_count
         + sizing_group_slot_rounding(element_count)
         + CLAY_PERL_ALIGNMENT_SLACK;
}
