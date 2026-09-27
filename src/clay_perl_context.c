/*
 * clay_perl_context.c - Per-Perl-context state, the per-frame string arena
 * and the element id intern table.
 *
 * Each Clay::XS::Context Perl object owns one clay_perl_context. The
 * object is a reference to a read-only scalar carrying the context pointer
 * in private ext magic; copies (Storable::dclone) and forged objects lack
 * the magic and are rejected. DESTROY frees the context and clears the
 * magic pointer, so a second DESTROY is a no-op.
 */

#include "clay_perl.h"

#include <stdlib.h>
#include <string.h>

#define MIN_STRING_CHUNK_BYTES 4096

/* Interned ids unused for this many frames may be swept. */
#define INTERNED_ID_KEEP_FRAMES 2

/* Hover entries registered this many frames ago are dropped. Entries of
 * the previous frame must survive: Clay_SetPointerState dispatches the
 * hover callbacks registered while declaring the last completed frame. */
#define HOVER_KEEP_FRAMES 2

static MGVTBL clay_perl_context_vtbl = { 0, 0, 0, 0, 0, 0, 0, 0 };

/* ---------------------------------------------------------------------------
 * String arena chunks.
 * ------------------------------------------------------------------------ */

static clay_perl_arena_chunk *chunk_new(size_t capacity)
{
    clay_perl_arena_chunk *chunk =
        (clay_perl_arena_chunk *) malloc(offsetof(clay_perl_arena_chunk, bytes) + capacity);
    if (!chunk) return NULL;
    chunk->next     = NULL;
    chunk->capacity = capacity;
    chunk->used     = 0;
    return chunk;
}

static void chunk_list_free(clay_perl_arena_chunk *chunk)
{
    while (chunk) {
        clay_perl_arena_chunk *next = chunk->next;
        free(chunk);
        chunk = next;
    }
}

/* Appends list `tail` behind list `head` and returns the joined list. */
static clay_perl_arena_chunk *chunk_list_concat(clay_perl_arena_chunk *head,
                                                clay_perl_arena_chunk *tail)
{
    if (!head) return tail;
    clay_perl_arena_chunk *last = head;
    while (last->next) last = last->next;
    last->next = tail;
    return head;
}

/* ---------------------------------------------------------------------------
 * Context lifecycle.
 * ------------------------------------------------------------------------ */

clay_perl_context *clay_perl_context_new(pTHX_ size_t clay_arena_capacity)
{
    char *arena_memory = (char *) malloc(clay_arena_capacity);
    if (!arena_memory) return NULL;

    clay_perl_arena_chunk *first_chunk = chunk_new(MIN_STRING_CHUNK_BYTES);
    if (!first_chunk) {
        free(arena_memory);
        return NULL;
    }

    clay_perl_context *self;
    Newxz(self, 1, clay_perl_context);

    self->owner             = CLAY_PERL_THIS_INTERPRETER;
    self->clay_arena_memory = arena_memory;
    self->clay_arena        = Clay_CreateArenaWithCapacityAndMemory(clay_arena_capacity, arena_memory);
    self->strings.current   = first_chunk;
    self->interned_ids      = newHV();
    self->hover_callbacks   = newHV();
    self->dispatch_cv       = get_cv("Clay::XS::_dispatch", 0);
    return self;
}

void clay_perl_context_free(pTHX_ clay_perl_context *self)
{
    if (!self) return;

    SvREFCNT_dec(self->measure_text_cb);
    SvREFCNT_dec(self->measure_text_userdata);
    SvREFCNT_dec(self->error_handler_cb);
    SvREFCNT_dec(self->error_handler_userdata);
    SvREFCNT_dec(self->query_scroll_offset_cb);
    SvREFCNT_dec(self->query_scroll_offset_userdata);
    SvREFCNT_dec(self->transition_handler_cb);
    SvREFCNT_dec(self->transition_set_initial_cb);
    SvREFCNT_dec(self->transition_set_final_cb);
    SvREFCNT_dec(self->transition_userdata);
    SvREFCNT_dec(self->pending_error);
    SvREFCNT_dec((SV *) self->hover_callbacks);
    SvREFCNT_dec((SV *) self->interned_ids);

    chunk_list_free(self->strings.current);
    chunk_list_free(self->strings.retained);
    free(self->clay_arena_memory);

    Safefree(self);
}

/* ---------------------------------------------------------------------------
 * SV <-> context bridging via ext magic on a shared referent.
 * ------------------------------------------------------------------------ */

SV *clay_perl_context_bless(pTHX_ clay_perl_context *self)
{
    SV *referent = newSV(0);
    sv_magicext(referent, NULL, PERL_MAGIC_ext, &clay_perl_context_vtbl, (const char *) self, 0);
    self->referent = referent;

    SV *ref = newRV_noinc(referent);
    sv_bless(ref, gv_stashpvs("Clay::XS::Context", GV_ADD));
    SvREADONLY_on(referent);
    return ref;
}

SV *clay_perl_context_to_sv(pTHX_ clay_perl_context *self)
{
    return newRV_inc(self->referent);
}

clay_perl_context *clay_perl_context_peek(pTHX_ SV *sv, MAGIC **magic_out)
{
    if (magic_out) *magic_out = NULL;
    if (!sv || !SvROK(sv)) return NULL;
    SV *referent = SvRV(sv);
    if (!SvMAGICAL(referent)) return NULL;
    MAGIC *mg = mg_findext(referent, PERL_MAGIC_ext, &clay_perl_context_vtbl);
    if (!mg) return NULL;
    if (magic_out) *magic_out = mg;
    return (clay_perl_context *) mg->mg_ptr;
}

clay_perl_context *clay_perl_context_from_sv(pTHX_ SV *sv)
{
    clay_perl_context *ctx = clay_perl_context_peek(aTHX_ sv, NULL);
    if (!ctx) {
        croak("Clay::XS: argument is not a live Clay::XS::Context");
    }
    return ctx;
}

/* ---------------------------------------------------------------------------
 * Per-frame string arena.
 *
 * Clay stores the Clay_String of every text element and reads it again in
 * Clay_EndLayout (measure-cache hashing, wrapping, render commands). It
 * also keeps text pointers beyond the frame: Clay_EndLayout copies the
 * subtree of every element with an exit transition into the next frame's
 * layout, and when such an element stops being declared it keeps being
 * rendered, with its old text, until the exit transition finishes.
 *
 * Lifetime rule implemented by clay_perl_context_begin_frame:
 *   - Chunks are never reallocated or freed while Clay may read them.
 *   - The previous frame's chunks stay alive for one more frame (an
 *     element starts exiting in the first frame it is no longer declared,
 *     with the text of the frame before).
 *   - While any exit transition runs, every chunk is retained; memory
 *     only grows during exit animations and is released at the first
 *     frame without one.
 * Steady state: one chunk for this frame and one for the last, recycled
 * without any per-frame allocation.
 * ------------------------------------------------------------------------ */

static void arena_begin_frame(clay_perl_string_arena *arena, bool exits_running)
{
    size_t wanted = arena->frame_bytes > MIN_STRING_CHUNK_BYTES
                  ? arena->frame_bytes : MIN_STRING_CHUNK_BYTES;
    clay_perl_arena_chunk *recyclable = NULL;

    if (exits_running) {
        arena->retained = chunk_list_concat(arena->current, arena->retained);
    } else {
        recyclable       = arena->retained;
        arena->retained  = arena->current;
    }
    arena->current     = NULL;
    arena->frame_bytes = 0;

    bool reuse = recyclable && !recyclable->next && recyclable->capacity >= wanted;
    if (reuse) {
        recyclable->used = 0;
        arena->current   = recyclable;
        return;
    }
    chunk_list_free(recyclable);
    /* If this allocation fails, current stays NULL and arena_reserve
     * allocates (or croaks) on the next copy. */
    arena->current = chunk_new(wanted);
}

static char *arena_reserve(pTHX_ clay_perl_string_arena *arena, size_t len)
{
    clay_perl_arena_chunk *head = arena->current;
    if (!head || head->capacity - head->used < len) {
        size_t previous = head ? head->capacity : MIN_STRING_CHUNK_BYTES / 2;
        size_t capacity = previous * 2 > len ? previous * 2 : len;
        clay_perl_arena_chunk *chunk = chunk_new(capacity);
        if (!chunk) {
            croak("Clay::XS: cannot allocate %" UVuf " bytes for text", (UV) capacity);
        }
        chunk->next    = head;
        arena->current = chunk;
        head           = chunk;
    }
    char *dst = head->bytes + head->used;
    head->used         += len;
    arena->frame_bytes += len;
    return dst;
}

Clay_String clay_perl_arena_copy_text(pTHX_ clay_perl_context *self, SV *sv, const char *what)
{
    if (!sv) croak("%s: text is missing", what);
    SvGETMAGIC(sv);
    if (!SvOK(sv)) croak("%s: text must be a defined string", what);

    STRLEN len = 0;
    const char *pv = SvPVutf8_nomg(sv, len);
    /* Clay_String.length is int32_t; refuse rather than truncate. */
    if (len > (STRLEN) INT32_MAX) {
        croak("%s: text length %" UVuf " exceeds INT32_MAX", what, (UV) len);
    }

    Clay_String s = { false, (int32_t) len, NULL };
    if (len == 0) return s;
    char *dst = arena_reserve(aTHX_ &self->strings, len);
    memcpy(dst, pv, len);
    s.chars = dst;
    return s;
}

/* ---------------------------------------------------------------------------
 * Element id interning.
 *
 * Clay copies Clay_ElementId (including the stringId pointer) into its
 * persistent element hash map, the per-frame id-string array (read by the
 * debug view) and pointerOverIds. The intern table keeps one SV per id
 * string; its buffer never moves, and the SV's IV slot records the frame
 * that last used it.
 * ------------------------------------------------------------------------ */

Clay_String clay_perl_intern_id(pTHX_ clay_perl_context *self, const char *bytes, STRLEN len)
{
    Clay_String s = { false, 0, NULL };
    if (len == 0) return s;
    if (len > (STRLEN) INT32_MAX) {
        croak("Clay::XS: element id length %" UVuf " exceeds INT32_MAX", (UV) len);
    }

    SV **slot = hv_fetch(self->interned_ids, bytes, (I32) len, 0);
    SV *entry;
    if (slot && *slot) {
        entry = *slot;
    } else {
        entry = newSVpvn(bytes, len);
        SvUPGRADE(entry, SVt_PVIV);
        SvREADONLY_on(entry);
        hv_store(self->interned_ids, bytes, (I32) len, entry, 0);
    }
    SvIV_set(entry, (IV) self->frame_generation);

    s.length = (int32_t) len;
    s.chars  = SvPVX(entry);
    return s;
}

static bool id_is_pointer_over(Clay_ElementIdArray over, const char *chars)
{
    for (int32_t i = 0; i < over.length; i++) {
        if (over.internalArray[i].stringId.chars == chars) return true;
    }
    return false;
}

static void interned_ids_sweep(pTHX_ clay_perl_context *self)
{
    if (self->frame_generation < INTERNED_ID_KEEP_FRAMES) return;
    IV cutoff = (IV) (self->frame_generation - INTERNED_ID_KEEP_FRAMES);
    Clay_ElementIdArray over = Clay_GetPointerOverIds();

    /* Collect first, delete afterwards: deleting invalidates the iterator. */
    AV *stale = newAV();
    sv_2mortal((SV *) stale);
    HE *he;
    hv_iterinit(self->interned_ids);
    while ((he = hv_iternext(self->interned_ids)) != NULL) {
        SV *entry = HeVAL(he);
        if (SvIVX(entry) >= cutoff) continue;
        if (id_is_pointer_over(over, SvPVX(entry))) continue;
        av_push(stale, newSVhek(HeKEY_hek(he)));
    }

    SSize_t count = av_top_index(stale) + 1;
    for (SSize_t i = 0; i < count; i++) {
        SV **key = av_fetch(stale, i, 0);
        (void) hv_delete_ent(self->interned_ids, *key, G_DISCARD, 0);
    }
}

/* ---------------------------------------------------------------------------
 * Frame start. Must run while this context is Clay's current context and
 * before Clay_BeginLayout discards the previous frame.
 * ------------------------------------------------------------------------ */

void clay_perl_context_begin_frame(pTHX_ clay_perl_context *self)
{
    bool exits_running = clay_perl_clay_has_exiting_transitions();

    self->frame_generation++;
    arena_begin_frame(&self->strings, exits_running);
    if (!exits_running) {
        interned_ids_sweep(aTHX_ self);
    }
    clay_perl_hover_registry_sweep(aTHX_ self, HOVER_KEEP_FRAMES);
}
