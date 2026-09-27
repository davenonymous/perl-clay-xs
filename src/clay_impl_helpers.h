/*
 * clay_impl_helpers.h - Binding helpers compiled together with the Clay
 * implementation in src/clay_impl.c.
 *
 * They read Clay internals (struct Clay_Context, the default counts, the
 * arena allocation routines) that the public clay.h API does not expose.
 * This header is Perl-free so src/clay_impl.c stays a pure Clay
 * compilation unit; src/clay_perl.h includes it for the rest of the
 * binding.
 */

#ifndef CLAY_IMPL_HELPERS_H
#define CLAY_IMPL_HELPERS_H

#include <stdbool.h>
#include <stdint.h>

/* True while any element of the current context plays its exit transition. */
bool clay_perl_clay_has_exiting_transitions(void);

/* Clay's default element and measure-cache word counts, used by
 * Clay_Initialize when no context is current. */
void clay_perl_clay_default_counts(int32_t *element_count, int32_t *word_count);

/* Upper bound of the arena bytes Clay needs for the given counts, computed
 * in 64 bits. Clay's own size arithmetic is 32-bit and wraps silently, so
 * callers keep this bound below 4 GiB. */
uint64_t clay_perl_clay_arena_bytes_upper_bound(int32_t element_count, int32_t word_count);

#endif /* CLAY_IMPL_HELPERS_H */
