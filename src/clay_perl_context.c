/*
 * clay_perl_context.c - Per-Perl-context state and the per-frame string arena.
 *
 * Each Clay::Layout::Context Perl object owns one clay_perl_context. The
 * Perl object is a blessed scalar ref whose IV slot holds a pointer to
 * this struct. DESTROY frees it.
 */

#include "clay_perl.h"

#include <stdlib.h>
#include <string.h>

#define INITIAL_STRING_ARENA_CAPACITY 4096

/* ---------------------------------------------------------------------------
 * Context lifecycle.
 * ------------------------------------------------------------------------ */

clay_perl_context *clay_perl_context_new(pTHX_ size_t clay_arena_capacity)
{
    clay_perl_context *self;

    Newxz(self, 1, clay_perl_context);

    self->clay_arena_memory = (char *) safemalloc(clay_arena_capacity);
    self->clay_arena = Clay_CreateArenaWithCapacityAndMemory(
        clay_arena_capacity, self->clay_arena_memory);

    self->string_arena_capacity = INITIAL_STRING_ARENA_CAPACITY;
    self->string_arena = (char *) safemalloc(self->string_arena_capacity);
    self->string_arena_used = 0;

    self->hover_callbacks = newHV();
    self->hover_generation = 0;

    /* The clay_ctx pointer is filled in by clay_perl_context_initialize_clay()
     * which the XS Clay_Initialize wrapper calls once it has dimensions and
     * an error handler. We do not call Clay_Initialize from here so that
     * the Perl side stays in full control of when Clay starts up. */
    self->clay_ctx = NULL;

    return self;
}

void clay_perl_context_free(pTHX_ clay_perl_context *self)
{
    if (!self) return;

    /* Drop callback SVs we hold a refcount on. */
    if (self->measure_text_cb)            SvREFCNT_dec(self->measure_text_cb);
    if (self->measure_text_userdata)      SvREFCNT_dec(self->measure_text_userdata);
    if (self->error_handler_cb)           SvREFCNT_dec(self->error_handler_cb);
    if (self->error_handler_userdata)     SvREFCNT_dec(self->error_handler_userdata);
    if (self->query_scroll_offset_cb)     SvREFCNT_dec(self->query_scroll_offset_cb);
    if (self->query_scroll_offset_userdata) SvREFCNT_dec(self->query_scroll_offset_userdata);

    if (self->hover_callbacks) SvREFCNT_dec((SV *) self->hover_callbacks);

    if (self->transition_handler_cb)     SvREFCNT_dec(self->transition_handler_cb);
    if (self->transition_set_initial_cb) SvREFCNT_dec(self->transition_set_initial_cb);
    if (self->transition_set_final_cb)   SvREFCNT_dec(self->transition_set_final_cb);
    if (self->transition_userdata)       SvREFCNT_dec(self->transition_userdata);

    if (self->string_arena)      safefree(self->string_arena);
    if (self->clay_arena_memory) safefree(self->clay_arena_memory);

    Safefree(self);
}

/* ---------------------------------------------------------------------------
 * SV <-> context pointer bridging. The blessed object is a scalar ref
 * whose referent is an IV holding the pointer.
 * ------------------------------------------------------------------------ */

SV *clay_perl_context_to_sv(pTHX_ clay_perl_context *self)
{
    SV *iv  = newSViv(PTR2IV(self));
    SV *ref = newRV_noinc(iv);
    sv_bless(ref, gv_stashpv("Clay::Layout::Context", GV_ADD));
    return ref;
}

clay_perl_context *clay_perl_context_from_sv(pTHX_ SV *sv)
{
    if (!sv || !SvROK(sv) ||
        !sv_derived_from(sv, "Clay::Layout::Context")) {
        croak("Argument is not a Clay::Layout::Context");
    }
    return INT2PTR(clay_perl_context *, SvIV(SvRV(sv)));
}

/* ---------------------------------------------------------------------------
 * Per-frame string arena.
 *
 * Strategy: a single growable buffer. clay_perl_arena_copy_bytes appends a
 * copy of the input bytes and returns a Clay_String pointing into the
 * buffer. The buffer is reset (used -> 0) at every BeginLayout call.
 *
 * Growing must invalidate existing pointers, so we double the capacity when
 * needed. This means callers MUST NOT mix-and-match Clay_String values
 * captured before and after a grow. In practice every Clay_String we
 * produce is consumed by Clay before the next call, so this is safe.
 * ------------------------------------------------------------------------ */

void clay_perl_arena_reset(clay_perl_context *self)
{
    if (!self) return;
    self->string_arena_used = 0;
    self->hover_generation++;
}

static void clay_perl_arena_grow(clay_perl_context *self, size_t need)
{
    size_t new_capacity = self->string_arena_capacity;
    while (new_capacity < need) {
        new_capacity *= 2;
    }
    self->string_arena = (char *) saferealloc(self->string_arena, new_capacity);
    self->string_arena_capacity = new_capacity;
}

Clay_String clay_perl_arena_copy_bytes(clay_perl_context *self,
                                       const char *bytes, size_t len)
{
    /* Clay_String.length is int32_t; refuse strings that would overflow
     * rather than silently truncating. A 2 GiB string in a UI layout is
     * almost certainly a bug. */
    if (len > (size_t) INT32_MAX) {
        dTHX;
        croak("Clay::Layout: string length %zu exceeds INT32_MAX", len);
    }

    size_t needed = self->string_arena_used + len;
    if (needed > self->string_arena_capacity) {
        clay_perl_arena_grow(self, needed);
    }

    char *dst = self->string_arena + self->string_arena_used;
    if (len > 0 && bytes != NULL) {
        memcpy(dst, bytes, len);
    }
    self->string_arena_used += len;

    Clay_String s;
    s.isStaticallyAllocated = false;
    s.length = (int32_t) len;
    s.chars  = dst;
    return s;
}

Clay_String clay_perl_arena_copy_pv(pTHX_ clay_perl_context *self, SV *sv)
{
    if (!sv || !SvOK(sv)) {
        Clay_String empty = { false, 0, NULL };
        return empty;
    }
    STRLEN len = 0;
    const char *pv = SvPVbyte(sv, len);
    return clay_perl_arena_copy_bytes(self, pv, (size_t) len);
}
