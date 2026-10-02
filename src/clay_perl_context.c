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

/* The sweep at the start of a frame keeps the interned ids used by the
 * last this many completed frames (see clay_perl_context_begin_frame). */
#define INTERNED_ID_KEEP_COMPLETED_FRAMES 2

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

/* ---------------------------------------------------------------------------
 * Context lifecycle.
 * ------------------------------------------------------------------------ */

clay_perl_context *clay_perl_context_new(pTHX_ size_t clay_arena_capacity)
{
    CV *dispatch_cv = get_cv("Clay::XS::_dispatch", 0);
    if (!dispatch_cv) {
        croak("Clay::XS: internal error: Clay::XS::_dispatch is not defined");
    }

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
    self->dispatch_cv       = (CV *) SvREFCNT_inc_simple_NN((SV *) dispatch_cv);
    self->layout_state      = CLAY_PERL_LAYOUT_COMPLETE;
    return self;
}

void clay_perl_context_free(pTHX_ clay_perl_context *self)
{
    if (!self) return;

    clay_perl_callbacks_free(aTHX_ self);
    SvREFCNT_dec(self->held_error);
    SvREFCNT_dec((SV *) self->hover_callbacks);
    SvREFCNT_dec((SV *) self->interned_ids);
    SvREFCNT_dec((SV *) self->dispatch_cv);

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
 * Buffers exiting elements still use.
 *
 * A sorted array of the text and id-string pointers Clay's exiting
 * element clones hold (clay_perl_clay_visit_exiting_buffers). When it
 * could not be collected (out of memory) it is marked incomplete, and
 * its users keep everything.
 * ------------------------------------------------------------------------ */

typedef struct buffer_set {
    const char **items;
    size_t length;
    size_t capacity;
    bool complete;
} buffer_set;

static void buffer_set_add(const char *chars, void *data)
{
    buffer_set *set = (buffer_set *) data;
    if (!set->complete) return;
    if (!chars) {
        set->complete = false;
        return;
    }
    if (set->length == set->capacity) {
        size_t capacity = set->capacity ? set->capacity * 2 : 64;
        const char **items = (const char **) realloc((void *) set->items, capacity * sizeof(*items));
        if (!items) {
            set->complete = false;
            return;
        }
        set->items    = items;
        set->capacity = capacity;
    }
    set->items[set->length++] = chars;
}

static int compare_pointers(const void *a, const void *b)
{
    uintptr_t left  = (uintptr_t) *(const char *const *) a;
    uintptr_t right = (uintptr_t) *(const char *const *) b;
    return left < right ? -1 : left > right ? 1 : 0;
}

static buffer_set exiting_buffers_collect(void)
{
    buffer_set set = { NULL, 0, 0, true };
    clay_perl_clay_visit_exiting_buffers(buffer_set_add, &set);
    if (set.complete && set.length > 1) {
        qsort((void *) set.items, set.length, sizeof(*set.items), compare_pointers);
    }
    return set;
}

static void buffer_set_free(buffer_set *set)
{
    free((void *) set->items);
    set->items  = NULL;
    set->length = set->capacity = 0;
}

/* True when some pointer of the set lies in [start, start + length). */
static bool buffer_set_hits(const buffer_set *set, const char *start, size_t length)
{
    if (!set->complete) return true;
    size_t low = 0, high = set->length;
    while (low < high) {   /* first pointer >= start */
        size_t middle = low + (high - low) / 2;
        if ((uintptr_t) set->items[middle] < (uintptr_t) start) low = middle + 1;
        else high = middle;
    }
    return low < set->length && (uintptr_t) set->items[low] < (uintptr_t) start + length;
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
 *   - An older chunk stays alive while an exiting element's text points
 *     into it; memory during long exit animations stays bounded by the
 *     text those elements show.
 *   - After an unfinished frame Clay may point into the text of any frame
 *     since the last completed one, so every chunk is kept until a frame
 *     completes.
 * Steady state: one chunk for this frame and one for the last, recycled
 * without any per-frame allocation. A new chunk gets half again the
 * bytes it needs, so text that grows a little every frame does not
 * reallocate every frame.
 * ------------------------------------------------------------------------ */

static size_t chunk_bytes_for(size_t wanted)
{
    size_t padded = wanted + wanted / 2;
    return padded > MIN_STRING_CHUNK_BYTES ? padded : MIN_STRING_CHUNK_BYTES;
}

/* exiting is NULL after an unfinished frame: keep every chunk. */
static void arena_begin_frame(clay_perl_string_arena *arena, const buffer_set *exiting)
{
    size_t wanted = arena->frame_bytes;
    clay_perl_arena_chunk *older = arena->retained;

    arena->retained    = arena->current;
    arena->current     = NULL;
    arena->frame_bytes = 0;

    /* Sort the older chunks into the ones Clay may still read and the
     * free ones; the first free chunk large enough becomes this frame's. */
    clay_perl_arena_chunk *spare = NULL;
    while (older) {
        clay_perl_arena_chunk *chunk = older;
        older = chunk->next;
        bool in_use = !exiting || buffer_set_hits(exiting, chunk->bytes, chunk->used);
        if (in_use) {
            chunk->next     = arena->retained;
            arena->retained = chunk;
        } else if (!arena->current && chunk->capacity >= wanted) {
            chunk->next    = NULL;
            chunk->used    = 0;
            arena->current = chunk;
        } else {
            chunk->next = spare;
            spare       = chunk;
        }
    }
    chunk_list_free(spare);

    /* If this allocation fails, current stays NULL and arena_reserve
     * allocates (or croaks) on the next copy. */
    if (!arena->current) arena->current = chunk_new(chunk_bytes_for(wanted));
}

static char *arena_reserve(pTHX_ clay_perl_string_arena *arena, size_t len)
{
    clay_perl_arena_chunk *head = arena->current;
    if (!head || head->capacity - head->used < len) {
        size_t previous = head ? head->capacity : MIN_STRING_CHUNK_BYTES / 2;
        size_t capacity = previous * 2 > len ? previous * 2 : chunk_bytes_for(len);
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
 * debug view, and carried along with exiting elements) and
 * pointerOverIds. The intern table keeps one SV per id string; its buffer
 * never moves, and the SV's IV slot records the frame that last used it
 * (completed_frames at the time).
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
    SvIV_set(entry, (IV) self->completed_frames);

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

static void interned_ids_sweep(pTHX_ clay_perl_context *self, const buffer_set *exiting)
{
    if (self->completed_frames < INTERNED_ID_KEEP_COMPLETED_FRAMES) return;
    IV cutoff = (IV) (self->completed_frames - INTERNED_ID_KEEP_COMPLETED_FRAMES);
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
        if (buffer_set_hits(exiting, SvPVX(entry), 1)) continue;
        av_push(stale, newSVhek(HeKEY_hek(he)));
    }

    SSize_t count = av_top_index(stale) + 1;
    for (SSize_t i = 0; i < count; i++) {
        SV **key = av_fetch(stale, i, 0);
        (void) hv_delete_ent(self->interned_ids, *key, G_DISCARD, 0);
    }
}

/* ---------------------------------------------------------------------------
 * Frame start. Must run while this context is Clay's current context,
 * before Clay_BeginLayout discards the previous frame and before
 * layout_state moves on.
 * ------------------------------------------------------------------------ */

void clay_perl_context_begin_frame(pTHX_ clay_perl_context *self)
{
    if (self->layout_state != CLAY_PERL_LAYOUT_COMPLETE) {
        arena_begin_frame(&self->strings, NULL);
        clay_perl_hover_registry_sweep(aTHX_ self);
        return;
    }

    buffer_set exiting = exiting_buffers_collect();
    arena_begin_frame(&self->strings, &exiting);
    interned_ids_sweep(aTHX_ self, &exiting);
    buffer_set_free(&exiting);
    clay_perl_hover_registry_sweep(aTHX_ self);
}
