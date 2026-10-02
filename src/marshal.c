/*
 * marshal.c - HV/AV <-> Clay struct converters.
 *
 * Functions named *_from_sv take a Perl SV and return a fully-populated
 * Clay struct (or croak on bad input). Functions named *_to_sv take a
 * Clay struct and return a new, non-mortal Perl value owning fresh memory.
 *
 * The design choices baked into this file:
 *
 *   - Every input struct is described once, by a struct schema: a table
 *     of its fields (C name, offset, kind, range or enum maximum, nested
 *     schema). One engine walks a Perl value against a schema, so the
 *     field list, the ranges and the error paths of a struct live in one
 *     place. Fields use exact C names (backgroundColor, layoutDirection,
 *     etc.) so users can read clay.h verbatim and translate to Perl hash
 *     keys.
 *
 *   - The engine runs in two modes. Parse mode builds the struct for a
 *     Clay call; it runs for every element in every frame and ignores
 *     unknown keys. Check mode (check_struct) walks the same tables into
 *     a scratch struct and is strict: unknown keys, wrong array lengths
 *     and references used as booleans croak, and shape errors carry the
 *     schema's hint.
 *
 *   - Compact types (Color, Vector2, Dimensions) accept either an
 *     arrayref or a hashref; CornerRadius and AspectRatio also accept a
 *     plain number.
 *
 *   - Missing or undef fields keep the value the struct starts from: zero
 *     for a fresh struct, exactly like C's designated initialisers (Clay's
 *     defaults - left-to-right layout, fit sizing, etc. - are themselves
 *     zero, so a bare {} gives sensible behaviour), or the caller's base
 *     for transition data. A nested struct that is present starts from
 *     zero.
 *
 *   - Fail Fast: every present value is parsed at this boundary. A wrong
 *     reference type (at any nesting level), a non-numeric value, a
 *     float that is not finite as a C float (beyond +-FLT_MAX), a
 *     fractional integer or an integer outside the C field's range croaks
 *     with a Clay::XS::StructError naming the struct and field. Values are fetched once (one get-magic call) and read
 *     with the _nomg accessors.
 *
 *   - Strings are characters: text comes back from Clay as UTF-8 flagged
 *     Perl strings (clay_perl_utf8_sv).
 */

#include "clay_perl.h"

#include <float.h>
#include <math.h>
#include <stddef.h>
#include <string.h>

/* ===========================================================================
 * Labels and struct errors.
 *
 * A label names the value being parsed: a chain of names from the
 * outermost struct (or function argument) inwards, plus an optional field
 * name at the point of use. Labels are compound literals on the parser's
 * stack and are turned into a path only when a croak needs them, so a
 * successful parse builds no strings.
 * ======================================================================== */

typedef struct marshal_label {
    const struct marshal_label *outer;
    const char *name;
} marshal_label;

#define ROOT_LABEL(name)          (&(const marshal_label){ NULL, (name) })
#define NESTED_LABEL(outer, name) (&(const marshal_label){ (outer), (name) })

static void append_label(pTHX_ AV *path, const marshal_label *label)
{
    if (!label) return;
    append_label(aTHX_ path, label->outer);
    av_push(path, newSVpv(label->name, 0));
}

/* "undef", "a HASH reference" or "'value'": how a croak shows a value. */
static SV *describe_value(pTHX_ SV *sv)
{
    if (!SvOK(sv)) return newSVpvs("undef");
    if (SvROK(sv)) return newSVpvf("a %s reference", sv_reftype(SvRV(sv), 0));
    return newSVpvf("'%" SVf "'", SVfARG(sv));
}

/* The parts of a struct error that only some errors carry. */
typedef struct struct_error_extras {
    const char *hint;     /* check mode only */
    AV *unknown_keys;     /* sorted, for unknown-key errors */
    AV *known_keys;
} struct_error_extras;

static void croak_struct_error(pTHX_ const marshal_label *what, const char *field,
                               SV *expected, SV *got, const struct_error_extras *extras)
    __attribute__noreturn__;

/* Croaks a Clay::XS::StructError. Takes ownership of expected and got. */
static void croak_struct_error(pTHX_ const marshal_label *what, const char *field,
                               SV *expected, SV *got, const struct_error_extras *extras)
{
    AV *path = newAV();
    append_label(aTHX_ path, what);
    if (field) av_push(path, newSVpv(field, 0));

    HV *error = newHV();
    (void) hv_stores(error, "path",     newRV_noinc((SV *) path));
    (void) hv_stores(error, "expected", expected);
    (void) hv_stores(error, "got",      got);
    if (extras && extras->hint)         (void) hv_stores(error, "hint", newSVpv(extras->hint, 0));
    if (extras && extras->unknown_keys) (void) hv_stores(error, "unknown_keys", newRV_noinc((SV *) extras->unknown_keys));
    if (extras && extras->known_keys)   (void) hv_stores(error, "known_keys",   newRV_noinc((SV *) extras->known_keys));
    (void) hv_stores(error, "file", newSVpv(CopFILE(PL_curcop), 0));
    (void) hv_stores(error, "line", newSVuv(CopLINE(PL_curcop)));

    SV *object = sv_bless(newRV_noinc((SV *) error), gv_stashpvs("Clay::XS::StructError", GV_ADD));
    croak_sv(sv_2mortal(object));
}

static void croak_bad_value(pTHX_ const marshal_label *what, const char *field,
                            const char *expected, SV *sv)
    __attribute__noreturn__;

static void croak_bad_value(pTHX_ const marshal_label *what, const char *field,
                            const char *expected, SV *sv)
{
    croak_struct_error(aTHX_ what, field, newSVpv(expected, 0), describe_value(aTHX_ sv), NULL);
}

static void croak_bad_integer(pTHX_ const marshal_label *what, const char *field,
                              NV min, NV max, SV *sv)
    __attribute__noreturn__;

static void croak_bad_integer(pTHX_ const marshal_label *what, const char *field,
                              NV min, NV max, SV *sv)
{
    croak_struct_error(aTHX_ what, field,
                       newSVpvf("an integer in %.0f..%.0f", (double) min, (double) max),
                       describe_value(aTHX_ sv), NULL);
}

/* Function arguments that are not structs croak plain strings. */
static void croak_bad_argument(pTHX_ const char *what, const char *expected, SV *sv)
    __attribute__noreturn__;

static void croak_bad_argument(pTHX_ const char *what, const char *expected, SV *sv)
{
    SV *got = sv_2mortal(describe_value(aTHX_ sv));
    croak("%s: expected %s, got %" SVf, what, expected, SVfARG(got));
}

/* ===========================================================================
 * Scalar parsing. Each reader takes an SV whose get-magic has run and
 * reports whether it holds the wanted kind of value; callers decide how
 * to croak.
 * ======================================================================== */

static bool is_number_nomg(pTHX_ SV *sv)
{
    return SvROK(sv) ? cBOOL(SvAMAGIC(sv)) : cBOOL(looks_like_number(sv));
}

/* A number that stays finite as a C float: anything beyond +-FLT_MAX
 * would turn into an infinity when narrowed. */
static bool read_finite(pTHX_ SV *sv, float *out)
{
    if (!is_number_nomg(aTHX_ sv)) return false;
    NV nv = SvNV_nomg(sv);
    if (Perl_isnan(nv) || nv > FLT_MAX || nv < -FLT_MAX) return false;
    *out = (float) nv;
    return true;
}

/* A size maximum: finite, or +Inf for "unbounded" (Clay also treats 0 as
 * "no max"); a value beyond FLT_MAX is unbounded too. */
static bool read_maximum(pTHX_ SV *sv, float *out)
{
    if (!is_number_nomg(aTHX_ sv)) return false;
    NV nv = SvNV_nomg(sv);
    if (Perl_isnan(nv) || nv < -FLT_MAX) return false;
    *out = nv > FLT_MAX ? (float) INFINITY : (float) nv;
    return true;
}

/* Integers are range-checked as NV: every bound used here (at most
 * 32 bits) is exact in a double, also on perls with a 32-bit IV. */
static bool read_integer(pTHX_ SV *sv, NV min, NV max, NV *out)
{
    if (!is_number_nomg(aTHX_ sv)) return false;
    NV nv = SvNV_nomg(sv);
    if (Perl_isnan(nv) || nv != Perl_floor(nv) || nv < min || nv > max) return false;
    *out = nv;
    return true;
}

/* Opaque pointer-sized integers (userData, imageData, customData): an
 * unsigned integer that fits a pointer, read exactly. Integers above 2**53
 * are exact only as Perl integers or decimal strings, not as floats. */
static bool read_pointer(pTHX_ SV *sv, void **out)
{
    if (SvROK(sv) || !looks_like_number(sv)) return false;
    UV value;
    int flags = 0;
    if (SvPOK(sv) && !SvIOK(sv) && !SvNOK(sv)) {
        STRLEN length;
        const char *pv = SvPV_nomg(sv, length);
        flags = grok_number(pv, length, &value);
    }
    if ((flags & (IS_NUMBER_IN_UV | IS_NUMBER_GREATER_THAN_UV_MAX | IS_NUMBER_NOT_INT | IS_NUMBER_NEG
                  | IS_NUMBER_INFINITY | IS_NUMBER_NAN)) == IS_NUMBER_IN_UV) {
        /* value holds the decimal string's integer */
    } else if (SvIOK(sv)) {
        if (!SvIsUV(sv) && SvIVX(sv) < 0) return false;
        value = SvIsUV(sv) ? SvUVX(sv) : (UV) SvIVX(sv);
    } else {
        NV nv = SvNV_nomg(sv);
        /* UV_MAX + 1 is a power of two, exact as an NV. */
        if (Perl_isnan(nv) || nv != Perl_floor(nv) || nv < 0 || nv >= (NV) UV_MAX + 1.0) return false;
        value = (UV) nv;
    }
    if (sizeof(void *) < sizeof(UV) && value > (UV) UINTPTR_MAX) return false;
    *out = INT2PTR(void *, value);
    return true;
}

double clay_perl_parse_float(pTHX_ SV *sv, const char *what)
{
    SvGETMAGIC(sv);
    float value;
    if (!read_finite(aTHX_ sv, &value)) croak_bad_argument(aTHX_ what, "a finite number", sv);
    return value;
}

double clay_perl_parse_max_float(pTHX_ SV *sv, const char *what)
{
    SvGETMAGIC(sv);
    float value;
    if (!read_maximum(aTHX_ sv, &value)) croak_bad_argument(aTHX_ what, "a finite number or +Inf", sv);
    return value;
}

UV clay_perl_parse_uint(pTHX_ SV *sv, const char *what, UV max)
{
    return (UV) clay_perl_parse_integer(aTHX_ sv, what, 0, (NV) max);
}

double clay_perl_parse_float_or(pTHX_ SV *sv, const char *what, double fallback)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) return fallback;
    float value;
    if (!read_finite(aTHX_ sv, &value)) croak_bad_argument(aTHX_ what, "a finite number", sv);
    return value;
}

double clay_perl_parse_max_float_or(pTHX_ SV *sv, const char *what, double fallback)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) return fallback;
    float value;
    if (!read_maximum(aTHX_ sv, &value)) croak_bad_argument(aTHX_ what, "a finite number or +Inf", sv);
    return value;
}

UV clay_perl_parse_uint_or(pTHX_ SV *sv, const char *what, UV max, UV fallback)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) return fallback;
    NV value;
    if (read_integer(aTHX_ sv, 0, (NV) max, &value)) return (UV) value;
    SV *expected = sv_2mortal(newSVpvf("an integer in 0..%.0f", (double) max));
    croak_bad_argument(aTHX_ what, SvPV_nolen(expected), sv);
}

NV clay_perl_parse_integer(pTHX_ SV *sv, const char *what, NV min, NV max)
{
    SvGETMAGIC(sv);
    NV value;
    if (read_integer(aTHX_ sv, min, max, &value)) return value;
    SV *expected = sv_2mortal(newSVpvf("an integer in %.0f..%.0f", (double) min, (double) max));
    croak_bad_argument(aTHX_ what, SvPV_nolen(expected), sv);
}

SV *clay_perl_require_code(pTHX_ SV *sv, const char *what, bool allow_undef)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) {
        if (allow_undef) return NULL;
        croak("%s: expected a CODE reference, got undef", what);
    }
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVCV) {
        croak_bad_argument(aTHX_ what, allow_undef ? "a CODE reference or undef" : "a CODE reference", sv);
    }
    /* A plain copy, so callers do not run get-magic again. */
    SV *code = sv_newmortal();
    sv_setsv_nomg(code, sv);
    return code;
}

/* ===========================================================================
 * Struct field values: the scalar readers, croaking a struct error.
 * ======================================================================== */

static float field_float(pTHX_ SV *sv, const marshal_label *what, const char *field)
{
    float value;
    if (!read_finite(aTHX_ sv, &value)) croak_bad_value(aTHX_ what, field, "a finite number", sv);
    return value;
}

static float field_maximum(pTHX_ SV *sv, const marshal_label *what, const char *field)
{
    float value;
    if (!read_maximum(aTHX_ sv, &value)) croak_bad_value(aTHX_ what, field, "a finite number or +Inf", sv);
    return value;
}

static NV field_integer(pTHX_ SV *sv, const marshal_label *what, const char *field, NV min, NV max)
{
    NV value;
    if (!read_integer(aTHX_ sv, min, max, &value)) croak_bad_integer(aTHX_ what, field, min, max, sv);
    return value;
}

static void *field_pointer(pTHX_ SV *sv, const marshal_label *what, const char *field)
{
    void *value;
    if (!read_pointer(aTHX_ sv, &value)) {
        SV *expected = newSVpvf("an integer in 0..%" UVuf, (UV) (sizeof(void *) < sizeof(UV) ? (UV) UINTPTR_MAX : UV_MAX));
        croak_struct_error(aTHX_ what, field, expected, describe_value(aTHX_ sv), NULL);
    }
    return value;
}

/* Parse mode reads any value as a boolean; check mode rejects references,
 * which are always true and so almost always a mistake. */
static bool field_bool(pTHX_ SV *sv, const marshal_label *what, const char *field, bool strict)
{
    if (strict && SvROK(sv)) croak_bad_value(aTHX_ what, field, "a plain boolean value", sv);
    return cBOOL(SvTRUE_nomg(sv));
}

/* ===========================================================================
 * Hash access.
 * ======================================================================== */

/* Returns the value stored under key with get-magic applied; NULL for an
 * absent key or undef. */
static SV *fetch_defined(pTHX_ HV *hv, const char *key)
{
    SV **slot = hv_fetch(hv, key, (I32) strlen(key), 0);
    if (!slot || !*slot) return NULL;
    SvGETMAGIC(*slot);
    return SvOK(*slot) ? *slot : NULL;
}

static void hv_store_nv(pTHX_ HV *hv, const char *key, NV value)
{
    (void) hv_store(hv, key, (I32) strlen(key), newSVnv(value), 0);
}

static void hv_store_iv(pTHX_ HV *hv, const char *key, IV value)
{
    (void) hv_store(hv, key, (I32) strlen(key), newSViv(value), 0);
}

static void hv_store_uv(pTHX_ HV *hv, const char *key, UV value)
{
    (void) hv_store(hv, key, (I32) strlen(key), newSVuv(value), 0);
}

static void hv_store_bool(pTHX_ HV *hv, const char *key, bool value)
{
    (void) hv_store(hv, key, (I32) strlen(key), newSVuv(value ? 1 : 0), 0);
}

static void hv_store_sv(pTHX_ HV *hv, const char *key, SV *value)
{
    (void) hv_store(hv, key, (I32) strlen(key), value, 0);
}

SV *clay_perl_utf8_sv(pTHX_ const char *bytes, int32_t length)
{
    if (!bytes || length <= 0) return newSVpvs("");
    SV *sv = newSVpvn(bytes, (STRLEN) length);
    SvUTF8_on(sv);
    return sv;
}

/* ===========================================================================
 * Struct schemas.
 *
 * A schema lists a struct's fields; the engine below walks a Perl value
 * against it. Each field names its C member, where it lives in the struct
 * and how its value is read. Integers carry their range (enums run
 * 0..maximum) and are stored at the member's size. A custom field has its
 * own reader; a schema may also replace the whole hash walk (a union) or
 * finish a parsed struct (fields that are not in the hash).
 * ======================================================================== */

typedef enum {
    FIELD_FLOAT,
    FIELD_INTEGER,
    FIELD_BOOL,
    FIELD_POINTER,
    FIELD_STRUCT,
    FIELD_CUSTOM
} field_kind;

typedef struct struct_schema struct_schema;

/* Reads a defined value (get-magic has run) into the member at slot. */
typedef void (*field_reader)(pTHX_ SV *sv, void *slot, const marshal_label *what,
                             const char *field, bool strict);

typedef struct schema_field {
    const char *name;
    size_t offset;
    size_t size;
    field_kind kind;
    NV min, max;                  /* FIELD_INTEGER */
    const struct_schema *nested;  /* FIELD_STRUCT */
    field_reader read;            /* FIELD_CUSTOM */
} schema_field;

enum {
    SHAPE_HASH   = 1,   /* { field => value, ... } */
    SHAPE_ARRAY  = 2,   /* [ value, ... ] in field order */
    SHAPE_NUMBER = 4    /* one number for every float field */
};

struct struct_schema {
    const char *c_name;
    size_t size;
    const schema_field *fields;
    size_t field_count;
    unsigned shapes;
    void (*read_hash)(pTHX_ HV *hv, void *out, const marshal_label *what, bool strict);
    void (*finish)(void *out);
    const char *hint;
};

#define FIELD_COUNT(fields) (sizeof(fields) / sizeof((fields)[0]))
#define MEMBER_SIZE(type, member) sizeof(((type *) 0)->member)

#define F_FLOAT(type, member) \
    { #member, offsetof(type, member), MEMBER_SIZE(type, member), FIELD_FLOAT, 0, 0, NULL, NULL }
#define F_INT(type, member, lo, hi) \
    { #member, offsetof(type, member), MEMBER_SIZE(type, member), FIELD_INTEGER, (lo), (hi), NULL, NULL }
#define F_U16(type, member)       F_INT(type, member, 0, UINT16_MAX)
#define F_U32(type, member)       F_INT(type, member, 0, (NV) UINT32_MAX)
#define F_ENUM(type, member, max) F_INT(type, member, 0, (max))
#define F_BOOL(type, member) \
    { #member, offsetof(type, member), MEMBER_SIZE(type, member), FIELD_BOOL, 0, 0, NULL, NULL }
#define F_POINTER(type, member) \
    { #member, offsetof(type, member), MEMBER_SIZE(type, member), FIELD_POINTER, 0, 0, NULL, NULL }
#define F_STRUCT(type, member, schema) \
    { #member, offsetof(type, member), MEMBER_SIZE(type, member), FIELD_STRUCT, 0, 0, &(schema), NULL }
#define F_CUSTOM(name, type, member, reader) \
    { (name), offsetof(type, member), MEMBER_SIZE(type, member), FIELD_CUSTOM, 0, 0, NULL, (reader) }

/* Members of an anonymous struct nested in `type` (transition enter and
 * exit), with offsets relative to that inner struct. */
#define INNER_OFFSET(type, inner, member) (offsetof(type, inner.member) - offsetof(type, inner))
#define F_INNER_ENUM(type, inner, member, max) \
    { #member, INNER_OFFSET(type, inner, member), MEMBER_SIZE(type, inner.member), FIELD_INTEGER, 0, (max), NULL, NULL }
#define F_INNER_CUSTOM(name, type, inner, member, reader) \
    { (name), INNER_OFFSET(type, inner, member), MEMBER_SIZE(type, inner.member), FIELD_CUSTOM, 0, 0, NULL, (reader) }

#define SCHEMA(c_name, type, fields, shapes, read_hash, finish, hint) \
    { (c_name), sizeof(type), (fields), FIELD_COUNT(fields), (shapes), (read_hash), (finish), (hint) }

/* ===========================================================================
 * The schema engine.
 * ======================================================================== */

static void read_defined_struct(pTHX_ const struct_schema *schema, SV *sv, void *out,
                                const marshal_label *what, bool strict);

static void store_integer(pTHX_ const schema_field *field, void *slot, NV value)
{
    switch (field->size) {
    case sizeof(uint8_t):
        *(uint8_t *) slot = (uint8_t) value;
        return;
    case sizeof(uint16_t):
        if (field->min < 0) *(int16_t *) slot = (int16_t) value;
        else                *(uint16_t *) slot = (uint16_t) value;
        return;
    case sizeof(uint32_t):
        *(uint32_t *) slot = (uint32_t) value;
        return;
    }
    croak("marshal.c: field '%s' has unsupported integer size %d", field->name, (int) field->size);
}

/* Reads a defined value (get-magic has run) into the field's member. */
static void read_field(pTHX_ const schema_field *field, SV *sv, char *base,
                       const marshal_label *what, bool strict)
{
    void *slot = base + field->offset;
    switch (field->kind) {
    case FIELD_FLOAT:
        *(float *) slot = field_float(aTHX_ sv, what, field->name);
        return;
    case FIELD_INTEGER:
        store_integer(aTHX_ field, slot, field_integer(aTHX_ sv, what, field->name, field->min, field->max));
        return;
    case FIELD_BOOL:
        *(bool *) slot = field_bool(aTHX_ sv, what, field->name, strict);
        return;
    case FIELD_POINTER:
        *(void **) slot = field_pointer(aTHX_ sv, what, field->name);
        return;
    case FIELD_STRUCT:
        memset(slot, 0, field->size);
        read_defined_struct(aTHX_ field->nested, sv, slot, NESTED_LABEL(what, field->name), strict);
        return;
    case FIELD_CUSTOM:
        field->read(aTHX_ sv, slot, what, field->name, strict);
        return;
    }
}

static bool is_known_key(const schema_field *fields, size_t count, const char *key)
{
    for (size_t i = 0; i < count; i++) {
        if (strEQ(fields[i].name, key)) return true;
    }
    return false;
}

static SV *joined_names(pTHX_ AV *names, const char *quote)
{
    SV *out = newSVpvs("");
    for (SSize_t i = 0; i <= av_top_index(names); i++) {
        if (i) sv_catpvs(out, ", ");
        sv_catpvf(out, "%s%" SVf "%s", quote, SVfARG(*av_fetch(names, i, 0)), quote);
    }
    return out;
}

/* Check mode: every key of hv must name one of fields[0 .. count-1]. */
static void reject_unknown_keys(pTHX_ HV *hv, const schema_field *fields, size_t count,
                                const marshal_label *what, const char *hint)
{
    AV *unknown = (AV *) sv_2mortal((SV *) newAV());
    hv_iterinit(hv);
    HE *entry;
    while ((entry = hv_iternext(hv))) {
        SV *key = hv_iterkeysv(entry);
        if (!is_known_key(fields, count, SvPV_nolen(key))) av_push(unknown, newSVsv(key));
    }
    if (av_top_index(unknown) < 0) return;

    sortsv(AvARRAY(unknown), av_top_index(unknown) + 1, Perl_sv_cmp);
    AV *known = newAV();
    for (size_t i = 0; i < count; i++) av_push(known, newSVpv(fields[i].name, 0));

    SV *expected = newSVpvs("only the keys ");
    sv_catsv(expected, sv_2mortal(joined_names(aTHX_ known, "")));
    SV *got = newSVpv(av_top_index(unknown) ? "the unknown keys " : "the unknown key ", 0);
    sv_catsv(got, sv_2mortal(joined_names(aTHX_ unknown, "'")));

    struct_error_extras extras = { hint, (AV *) SvREFCNT_inc_simple_NN((SV *) unknown), known };
    croak_struct_error(aTHX_ what, NULL, expected, got, &extras);
}

static void read_fields(pTHX_ const struct_schema *schema, HV *hv, void *out,
                        const marshal_label *what, bool strict)
{
    if (strict) {
        reject_unknown_keys(aTHX_ hv, schema->fields, schema->field_count, what, schema->hint);
    }
    for (size_t i = 0; i < schema->field_count; i++) {
        const schema_field *field = &schema->fields[i];
        SV *value = fetch_defined(aTHX_ hv, field->name);
        if (value) read_field(aTHX_ field, value, (char *) out, what, strict);
    }
}

/* [v0, v1, ...] fills the (float) fields in order; check mode wants
 * exactly one element per field. */
static void read_positional(pTHX_ const struct_schema *schema, AV *av, void *out,
                            const marshal_label *what, bool strict)
{
    SSize_t length = av_top_index(av) + 1;
    if (strict && length != (SSize_t) schema->field_count) {
        SV *expected = newSVpvf("an array of %d numbers", (int) schema->field_count);
        SV *got = newSVpvf("an array of %d element%s", (int) length, length == 1 ? "" : "s");
        struct_error_extras extras = { schema->hint, NULL, NULL };
        croak_struct_error(aTHX_ what, NULL, expected, got, &extras);
    }
    for (size_t i = 0; i < schema->field_count; i++) {
        SV **slot = av_fetch(av, (SSize_t) i, 0);
        if (!slot || !*slot) continue;
        SvGETMAGIC(*slot);
        if (SvOK(*slot)) read_field(aTHX_ &schema->fields[i], *slot, (char *) out, what, strict);
    }
}

/* One number for every field. */
static void read_number(pTHX_ const struct_schema *schema, SV *sv, void *out, const marshal_label *what)
{
    float value = field_float(aTHX_ sv, what, NULL);
    for (size_t i = 0; i < schema->field_count; i++) {
        *(float *) ((char *) out + schema->fields[i].offset) = value;
    }
}

static const char *shape_description(unsigned shapes)
{
    if (shapes & SHAPE_NUMBER) return "a number or hash reference";
    if (shapes & SHAPE_ARRAY)  return "a hash or array reference";
    return "a hash reference";
}

/* Reads a defined value (get-magic has run) over *out. */
static void read_defined_struct(pTHX_ const struct_schema *schema, SV *sv, void *out,
                                const marshal_label *what, bool strict)
{
    if ((schema->shapes & SHAPE_NUMBER) && (!SvROK(sv) || SvAMAGIC(sv))) {
        read_number(aTHX_ schema, sv, out, what);
        return;
    }
    if ((schema->shapes & SHAPE_ARRAY) && SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVAV) {
        read_positional(aTHX_ schema, (AV *) SvRV(sv), out, what, strict);
        return;
    }
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        struct_error_extras extras = { strict ? schema->hint : NULL, NULL, NULL };
        croak_struct_error(aTHX_ what, NULL, newSVpv(shape_description(schema->shapes), 0),
                           describe_value(aTHX_ sv), &extras);
    }

    HV *hv = (HV *) SvRV(sv);
    if (schema->read_hash) schema->read_hash(aTHX_ hv, out, what, strict);
    else                   read_fields(aTHX_ schema, hv, out, what, strict);
    if (schema->finish) schema->finish(out);
}

/* Reads sv (any value, get-magic not yet run) over *out. NULL and undef
 * leave *out as it is. */
static void read_struct(pTHX_ const struct_schema *schema, SV *sv, void *out,
                        const marshal_label *what, bool strict)
{
    if (!sv) return;
    SvGETMAGIC(sv);
    if (SvOK(sv)) read_defined_struct(aTHX_ schema, sv, out, what, strict);
}

/* ===========================================================================
 * Custom fields and hash readers.
 * ======================================================================== */

/* floating.parentId: a numeric element id or an element-id hashref as
 * returned by Clay_GetElementId (its {id} is used). */
static void read_parent_id(pTHX_ SV *sv, void *slot, const marshal_label *what,
                           const char *field, bool strict)
{
    PERL_UNUSED_ARG(strict);
    if (SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVHV) {
        SV *id = fetch_defined(aTHX_ (HV *) SvRV(sv), "id");
        *(uint32_t *) slot = id ? (uint32_t) field_integer(aTHX_ id, NESTED_LABEL(what, field), "id", 0, (NV) UINT32_MAX) : 0;
        return;
    }
    *(uint32_t *) slot = (uint32_t) field_integer(aTHX_ sv, what, field, 0, (NV) UINT32_MAX);
}

/* The `hasSetInitial` / `hasSetFinal` booleans install the trampolines
 * for those slots; a set exit trampoline is what gives an element an exit
 * transition. */
static void read_has_set_initial(pTHX_ SV *sv, void *slot, const marshal_label *what,
                                 const char *field, bool strict)
{
    if (!field_bool(aTHX_ sv, what, field, strict)) return;
    *(Clay_TransitionData (**)(Clay_TransitionData, Clay_TransitionProperty)) slot
        = clay_perl_transition_set_initial_trampoline;
}

static void read_has_set_final(pTHX_ SV *sv, void *slot, const marshal_label *what,
                               const char *field, bool strict)
{
    if (!field_bool(aTHX_ sv, what, field, strict)) return;
    *(Clay_TransitionData (**)(Clay_TransitionData, Clay_TransitionProperty)) slot
        = clay_perl_transition_set_final_trampoline;
}

/* The handler is always installed: Clay requires one to run the
 * transition at all. */
static void finish_transition_config(void *out)
{
    ((Clay_TransitionElementConfig *) out)->handler = clay_perl_transition_handler_trampoline;
}

/* ===========================================================================
 * The schemas, innermost first.
 * ======================================================================== */

static const schema_field color_fields[] = {
    F_FLOAT(Clay_Color, r), F_FLOAT(Clay_Color, g), F_FLOAT(Clay_Color, b), F_FLOAT(Clay_Color, a),
};
static const struct_schema color_schema =
    SCHEMA("Clay_Color", Clay_Color, color_fields, SHAPE_HASH | SHAPE_ARRAY, NULL, NULL, NULL);

static const schema_field vector2_fields[] = {
    F_FLOAT(Clay_Vector2, x), F_FLOAT(Clay_Vector2, y),
};
static const struct_schema vector2_schema =
    SCHEMA("Clay_Vector2", Clay_Vector2, vector2_fields, SHAPE_HASH | SHAPE_ARRAY, NULL, NULL, NULL);

static const schema_field dimensions_fields[] = {
    F_FLOAT(Clay_Dimensions, width), F_FLOAT(Clay_Dimensions, height),
};
static const struct_schema dimensions_schema =
    SCHEMA("Clay_Dimensions", Clay_Dimensions, dimensions_fields, SHAPE_HASH | SHAPE_ARRAY, NULL, NULL, NULL);

static const schema_field bounding_box_fields[] = {
    F_FLOAT(Clay_BoundingBox, x), F_FLOAT(Clay_BoundingBox, y),
    F_FLOAT(Clay_BoundingBox, width), F_FLOAT(Clay_BoundingBox, height),
};
static const struct_schema bounding_box_schema =
    SCHEMA("Clay_BoundingBox", Clay_BoundingBox, bounding_box_fields, SHAPE_HASH, NULL, NULL, NULL);

/* Also accepts a number (applied to all four corners), like the C
 * CLAY_CORNER_RADIUS(r) macro. */
static const schema_field corner_radius_fields[] = {
    F_FLOAT(Clay_CornerRadius, topLeft),    F_FLOAT(Clay_CornerRadius, topRight),
    F_FLOAT(Clay_CornerRadius, bottomLeft), F_FLOAT(Clay_CornerRadius, bottomRight),
};
static const struct_schema corner_radius_schema =
    SCHEMA("Clay_CornerRadius", Clay_CornerRadius, corner_radius_fields, SHAPE_HASH | SHAPE_NUMBER, NULL, NULL, NULL);

static const schema_field padding_fields[] = {
    F_U16(Clay_Padding, left), F_U16(Clay_Padding, right),
    F_U16(Clay_Padding, top),  F_U16(Clay_Padding, bottom),
};
static const struct_schema padding_schema =
    SCHEMA("Clay_Padding", Clay_Padding, padding_fields, SHAPE_HASH, NULL, NULL, "padding_all(N) builds one");

static const schema_field border_width_fields[] = {
    F_U16(Clay_BorderWidth, left), F_U16(Clay_BorderWidth, right),
    F_U16(Clay_BorderWidth, top),  F_U16(Clay_BorderWidth, bottom),
    F_U16(Clay_BorderWidth, betweenChildren),
};
static const struct_schema border_width_schema =
    SCHEMA("Clay_BorderWidth", Clay_BorderWidth, border_width_fields, SHAPE_HASH, NULL, NULL, NULL);

static const schema_field child_alignment_fields[] = {
    F_ENUM(Clay_ChildAlignment, x, CLAY_ALIGN_X_CENTER),
    F_ENUM(Clay_ChildAlignment, y, CLAY_ALIGN_Y_CENTER),
};
static const struct_schema child_alignment_schema =
    SCHEMA("Clay_ChildAlignment", Clay_ChildAlignment, child_alignment_fields, SHAPE_HASH, NULL, NULL, NULL);

/* { type, min, max } for fit/grow/fixed (union member minMax) or
 * { type, percent } for percent. The order matters: the keys of a
 * min/max axis are fields 0..2, those of a percent axis fields 2..3. */
/* min, max and percent share a union, so the hash reader below stores
 * them; their entries only name the keys. */
static const schema_field sizing_axis_fields[] = {
    { "min",     0, 0, FIELD_FLOAT, 0, 0, NULL, NULL },
    { "max",     0, 0, FIELD_FLOAT, 0, 0, NULL, NULL },
    F_ENUM(Clay_SizingAxis, type, CLAY__SIZING_TYPE_FIXED),
    { "percent", 0, 0, FIELD_FLOAT, 0, 0, NULL, NULL },
};

static const char sizing_axis_hint[] = "sizing_fit, sizing_grow, sizing_fixed or sizing_percent build one";

/* The axis type selects the union member, so only that member's keys are
 * read (and, in check mode, allowed). */
static void read_sizing_axis(pTHX_ HV *hv, void *out, const marshal_label *what, bool strict)
{
    Clay_SizingAxis *axis = (Clay_SizingAxis *) out;
    SV *type = fetch_defined(aTHX_ hv, "type");
    axis->type = type
        ? (Clay__SizingType) field_integer(aTHX_ type, what, "type", 0, CLAY__SIZING_TYPE_FIXED)
        : CLAY__SIZING_TYPE_FIT;

    if (axis->type == CLAY__SIZING_TYPE_PERCENT) {
        if (strict) reject_unknown_keys(aTHX_ hv, sizing_axis_fields + 2, 2, what, sizing_axis_hint);
        SV *percent = fetch_defined(aTHX_ hv, "percent");
        axis->size.percent = percent ? field_float(aTHX_ percent, what, "percent") : 0.0f;
        return;
    }
    if (strict) reject_unknown_keys(aTHX_ hv, sizing_axis_fields, 3, what, sizing_axis_hint);
    SV *min = fetch_defined(aTHX_ hv, "min");
    SV *max = fetch_defined(aTHX_ hv, "max");
    axis->size.minMax.min = min ? field_float(aTHX_ min, what, "min") : 0.0f;
    axis->size.minMax.max = max ? field_maximum(aTHX_ max, what, "max") : 0.0f;
}

static const struct_schema sizing_axis_schema =
    SCHEMA("Clay_SizingAxis", Clay_SizingAxis, sizing_axis_fields, SHAPE_HASH, read_sizing_axis, NULL, sizing_axis_hint);

static const schema_field sizing_fields[] = {
    F_STRUCT(Clay_Sizing, width,  sizing_axis_schema),
    F_STRUCT(Clay_Sizing, height, sizing_axis_schema),
};
static const struct_schema sizing_schema =
    SCHEMA("Clay_Sizing", Clay_Sizing, sizing_fields, SHAPE_HASH, NULL, NULL, NULL);

static const schema_field layout_config_fields[] = {
    F_STRUCT(Clay_LayoutConfig, sizing,         sizing_schema),
    F_STRUCT(Clay_LayoutConfig, padding,        padding_schema),
    F_U16   (Clay_LayoutConfig, childGap),
    F_STRUCT(Clay_LayoutConfig, childAlignment, child_alignment_schema),
    F_ENUM  (Clay_LayoutConfig, layoutDirection, CLAY_LEFT_TO_RIGHT_WRAP),
    F_U16   (Clay_LayoutConfig, lineGap),
    F_ENUM  (Clay_LayoutConfig, lineSizing, CLAY_LINE_SIZING_FIT),
};
static const struct_schema layout_config_schema =
    SCHEMA("Clay_LayoutConfig", Clay_LayoutConfig, layout_config_fields, SHAPE_HASH, NULL, NULL, NULL);

/* userData is held as an opaque pointer-sized integer (no SV refcount is
 * taken); render commands carry it back unchanged. */
static const schema_field text_element_config_fields[] = {
    F_POINTER(Clay_TextElementConfig, userData),
    F_STRUCT (Clay_TextElementConfig, textColor, color_schema),
    F_U16    (Clay_TextElementConfig, fontId),
    F_U16    (Clay_TextElementConfig, fontSize),
    F_U16    (Clay_TextElementConfig, letterSpacing),
    F_U16    (Clay_TextElementConfig, lineHeight),
    F_ENUM   (Clay_TextElementConfig, wrapMode,      CLAY_TEXT_WRAP_NONE),
    F_ENUM   (Clay_TextElementConfig, textAlignment, CLAY_TEXT_ALIGN_RIGHT),
};
static const struct_schema text_element_config_schema =
    SCHEMA("Clay_TextElementConfig", Clay_TextElementConfig, text_element_config_fields, SHAPE_HASH, NULL, NULL, NULL);

static const schema_field aspect_ratio_fields[] = {
    F_FLOAT(Clay_AspectRatioElementConfig, aspectRatio),
};
static const struct_schema aspect_ratio_schema =
    SCHEMA("Clay_AspectRatioElementConfig", Clay_AspectRatioElementConfig, aspect_ratio_fields,
           SHAPE_HASH | SHAPE_NUMBER, NULL, NULL, NULL);

static const schema_field image_fields[] = {
    F_POINTER(Clay_ImageElementConfig, imageData),
};
static const struct_schema image_schema =
    SCHEMA("Clay_ImageElementConfig", Clay_ImageElementConfig, image_fields, SHAPE_HASH, NULL, NULL, NULL);

static const schema_field custom_fields[] = {
    F_POINTER(Clay_CustomElementConfig, customData),
};
static const struct_schema custom_schema =
    SCHEMA("Clay_CustomElementConfig", Clay_CustomElementConfig, custom_fields, SHAPE_HASH, NULL, NULL, NULL);

static const schema_field clip_fields[] = {
    F_BOOL  (Clay_ClipElementConfig, horizontal),
    F_BOOL  (Clay_ClipElementConfig, vertical),
    F_STRUCT(Clay_ClipElementConfig, childOffset, vector2_schema),
};
static const struct_schema clip_schema =
    SCHEMA("Clay_ClipElementConfig", Clay_ClipElementConfig, clip_fields, SHAPE_HASH, NULL, NULL, NULL);

static const schema_field border_fields[] = {
    F_STRUCT(Clay_BorderElementConfig, color, color_schema),
    F_STRUCT(Clay_BorderElementConfig, width, border_width_schema),
};
static const struct_schema border_schema =
    SCHEMA("Clay_BorderElementConfig", Clay_BorderElementConfig, border_fields, SHAPE_HASH, NULL, NULL, NULL);

static const schema_field attach_points_fields[] = {
    F_ENUM(Clay_FloatingAttachPoints, element, CLAY_ATTACH_POINT_RIGHT_BOTTOM),
    F_ENUM(Clay_FloatingAttachPoints, parent,  CLAY_ATTACH_POINT_RIGHT_BOTTOM),
};
static const struct_schema attach_points_schema =
    SCHEMA("Clay_FloatingAttachPoints", Clay_FloatingAttachPoints, attach_points_fields, SHAPE_HASH, NULL, NULL, NULL);

static const schema_field floating_fields[] = {
    F_STRUCT(Clay_FloatingElementConfig, offset, vector2_schema),
    F_STRUCT(Clay_FloatingElementConfig, expand, dimensions_schema),
    F_CUSTOM("parentId", Clay_FloatingElementConfig, parentId, read_parent_id),
    F_INT   (Clay_FloatingElementConfig, zIndex, INT16_MIN, INT16_MAX),
    F_STRUCT(Clay_FloatingElementConfig, attachPoints, attach_points_schema),
    F_ENUM  (Clay_FloatingElementConfig, pointerCaptureMode, CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH),
    F_ENUM  (Clay_FloatingElementConfig, attachTo, CLAY_ATTACH_TO_ROOT),
    F_ENUM  (Clay_FloatingElementConfig, clipTo,   CLAY_CLIP_TO_ATTACHED_PARENT),
};
static const struct_schema floating_schema =
    SCHEMA("Clay_FloatingElementConfig", Clay_FloatingElementConfig, floating_fields, SHAPE_HASH, NULL, NULL, NULL);

/* Transition data: clay_transition_data_from_sv starts from a base and
 * overrides the keys present, so a partial hash only changes what it
 * names. */
static const schema_field transition_data_fields[] = {
    F_STRUCT(Clay_TransitionData, boundingBox,     bounding_box_schema),
    F_STRUCT(Clay_TransitionData, backgroundColor, color_schema),
    F_STRUCT(Clay_TransitionData, overlayColor,    color_schema),
    F_STRUCT(Clay_TransitionData, borderColor,     color_schema),
    F_STRUCT(Clay_TransitionData, borderWidth,     border_width_schema),
};
static const struct_schema transition_data_schema =
    SCHEMA("Clay_TransitionData", Clay_TransitionData, transition_data_fields, SHAPE_HASH, NULL, NULL, NULL);

/* Every property flag OR-ed together. */
#define ALL_TRANSITION_PROPERTIES \
    (CLAY_TRANSITION_PROPERTY_BOUNDING_BOX | CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR \
     | CLAY_TRANSITION_PROPERTY_OVERLAY_COLOR | CLAY_TRANSITION_PROPERTY_CORNER_RADIUS \
     | CLAY_TRANSITION_PROPERTY_BORDER)

/* The Perl side describes a transition as:
 *
 *   transition => {
 *       duration            => 0.25,
 *       properties          => CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR | ...,
 *       interactionHandling => CLAY_TRANSITION_DISABLE_INTERACTIONS_WHILE_TRANSITIONING_POSITION,
 *       enter => { trigger => CLAY_TRANSITION_ENTER_SKIP_ON_FIRST_PARENT_FRAME, hasSetInitial => 1 },
 *       exit  => { trigger => ..., siblingOrdering => ..., hasSetFinal => 1 },
 *   }
 *
 * All three trampolines call the per-context handler set installed with
 * Clay_SetTransitionHandlers. enter and exit are anonymous structs in
 * clay.h, so their schemas have no C type name and check_struct cannot
 * name them. */
static const schema_field transition_enter_fields[] = {
    F_INNER_ENUM(Clay_TransitionElementConfig, enter, trigger, CLAY_TRANSITION_ENTER_TRIGGER_ON_FIRST_PARENT_FRAME),
    F_INNER_CUSTOM("hasSetInitial", Clay_TransitionElementConfig, enter, setInitialState, read_has_set_initial),
};
static const struct_schema transition_enter_schema = {
    NULL, MEMBER_SIZE(Clay_TransitionElementConfig, enter), transition_enter_fields,
    FIELD_COUNT(transition_enter_fields), SHAPE_HASH, NULL, NULL, NULL
};

static const schema_field transition_exit_fields[] = {
    F_INNER_ENUM(Clay_TransitionElementConfig, exit, trigger, CLAY_TRANSITION_EXIT_TRIGGER_WHEN_PARENT_EXITS),
    F_INNER_ENUM(Clay_TransitionElementConfig, exit, siblingOrdering, CLAY_EXIT_TRANSITION_ORDERING_ABOVE_SIBLINGS),
    F_INNER_CUSTOM("hasSetFinal", Clay_TransitionElementConfig, exit, setFinalState, read_has_set_final),
};
static const struct_schema transition_exit_schema = {
    NULL, MEMBER_SIZE(Clay_TransitionElementConfig, exit), transition_exit_fields,
    FIELD_COUNT(transition_exit_fields), SHAPE_HASH, NULL, NULL, NULL
};

static const schema_field transition_config_fields[] = {
    F_FLOAT (Clay_TransitionElementConfig, duration),
    F_ENUM  (Clay_TransitionElementConfig, properties, ALL_TRANSITION_PROPERTIES),
    F_ENUM  (Clay_TransitionElementConfig, interactionHandling,
             CLAY_TRANSITION_ALLOW_INTERACTIONS_WHILE_TRANSITIONING_POSITION),
    F_STRUCT(Clay_TransitionElementConfig, enter, transition_enter_schema),
    F_STRUCT(Clay_TransitionElementConfig, exit,  transition_exit_schema),
};
static const struct_schema transition_config_schema =
    SCHEMA("Clay_TransitionElementConfig", Clay_TransitionElementConfig, transition_config_fields,
           SHAPE_HASH, NULL, finish_transition_config, NULL);

/* {width => N, height => M}; either may be omitted. */
static const schema_field sizing_group_fields[] = {
    F_U32(Clay_SizingGroup, width), F_U32(Clay_SizingGroup, height),
};
static const struct_schema sizing_group_schema =
    SCHEMA("Clay_SizingGroup", Clay_SizingGroup, sizing_group_fields, SHAPE_HASH, NULL, NULL, NULL);

static const schema_field element_declaration_fields[] = {
    F_STRUCT (Clay_ElementDeclaration, layout,          layout_config_schema),
    F_STRUCT (Clay_ElementDeclaration, backgroundColor, color_schema),
    F_STRUCT (Clay_ElementDeclaration, overlayColor,    color_schema),
    F_STRUCT (Clay_ElementDeclaration, cornerRadius,    corner_radius_schema),
    F_STRUCT (Clay_ElementDeclaration, aspectRatio,     aspect_ratio_schema),
    F_STRUCT (Clay_ElementDeclaration, image,           image_schema),
    F_STRUCT (Clay_ElementDeclaration, floating,        floating_schema),
    F_STRUCT (Clay_ElementDeclaration, custom,          custom_schema),
    F_STRUCT (Clay_ElementDeclaration, clip,            clip_schema),
    F_STRUCT (Clay_ElementDeclaration, border,          border_schema),
    F_STRUCT (Clay_ElementDeclaration, transition,      transition_config_schema),
    F_STRUCT (Clay_ElementDeclaration, sizingGroup,     sizing_group_schema),
    F_POINTER(Clay_ElementDeclaration, userData),
};
static const struct_schema element_declaration_schema =
    SCHEMA("Clay_ElementDeclaration", Clay_ElementDeclaration, element_declaration_fields, SHAPE_HASH, NULL, NULL, NULL);

/* Every schema check_struct can name. */
static const struct_schema *const named_schemas[] = {
    &color_schema, &vector2_schema, &dimensions_schema, &bounding_box_schema,
    &corner_radius_schema, &padding_schema, &border_width_schema, &child_alignment_schema,
    &sizing_axis_schema, &sizing_schema, &layout_config_schema, &text_element_config_schema,
    &aspect_ratio_schema, &image_schema, &custom_schema, &clip_schema, &border_schema,
    &attach_points_schema, &floating_schema, &transition_data_schema, &transition_config_schema,
    &sizing_group_schema, &element_declaration_schema,
};

/* Large enough for any named struct: every one is either part of an
 * element declaration or one of these. */
typedef union check_scratch {
    Clay_ElementDeclaration declaration;
    Clay_TextElementConfig  text;
    Clay_TransitionData     transition;
} check_scratch;

/* ===========================================================================
 * Parse mode and check mode entry points.
 * ======================================================================== */

Clay_Color clay_color_from_sv(pTHX_ SV *sv, const char *what)
{
    Clay_Color c = { 0, 0, 0, 0 };
    read_struct(aTHX_ &color_schema, sv, &c, ROOT_LABEL(what), false);
    return c;
}

Clay_Vector2 clay_vector2_from_sv(pTHX_ SV *sv, const char *what)
{
    Clay_Vector2 v = { 0, 0 };
    read_struct(aTHX_ &vector2_schema, sv, &v, ROOT_LABEL(what), false);
    return v;
}

Clay_Dimensions clay_dimensions_from_sv(pTHX_ SV *sv, const char *what)
{
    Clay_Dimensions d = { 0, 0 };
    read_struct(aTHX_ &dimensions_schema, sv, &d, ROOT_LABEL(what), false);
    return d;
}

Clay_TextElementConfig clay_text_element_config_from_sv(pTHX_ SV *sv)
{
    Clay_TextElementConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    read_struct(aTHX_ &text_element_config_schema, sv, &cfg, ROOT_LABEL("Clay_TextElementConfig"), false);
    return cfg;
}

Clay_ElementDeclaration clay_element_declaration_from_sv(pTHX_ SV *sv)
{
    Clay_ElementDeclaration d;
    memset(&d, 0, sizeof(d));
    read_struct(aTHX_ &element_declaration_schema, sv, &d, ROOT_LABEL("Clay_ElementDeclaration"), false);
    return d;
}

Clay_TransitionData clay_transition_data_from_sv(pTHX_ SV *sv, Clay_TransitionData base, const char *what)
{
    read_struct(aTHX_ &transition_data_schema, sv, &base, ROOT_LABEL(what), false);
    return base;
}

void clay_perl_check_struct(pTHX_ const char *type, SV *value, const char *root)
{
    const struct_schema *schema = NULL;
    for (size_t i = 0; i < FIELD_COUNT(named_schemas); i++) {
        if (strEQ(named_schemas[i]->c_name, type)) schema = named_schemas[i];
    }
    if (!schema) croak("check_struct: unknown struct type '%s'", type);
    if (schema->size > sizeof(check_scratch)) {
        croak("check_struct: %s does not fit the scratch struct", type);
    }

    check_scratch scratch;
    memset(&scratch, 0, sizeof(scratch));
    read_struct(aTHX_ schema, value, &scratch, ROOT_LABEL(root ? root : schema->c_name), true);
}

/* ===========================================================================
 * Clay_ElementId - {id, offset, baseId, stringId}.
 * ======================================================================== */

/* Element ids are always required: an undef id is a bug in the caller
 * (typically a lookup that found nothing), never "no id". */
Clay_ElementId clay_element_id_from_sv(pTHX_ SV *sv, const char *what)
{
    const marshal_label *label = ROOT_LABEL(what);
    SvGETMAGIC(sv);
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak_bad_value(aTHX_ label, NULL, "an element id hash reference (from Clay_GetElementId)", sv);
    }
    HV *hv = (HV *) SvRV(sv);
    Clay_ElementId id;
    memset(&id, 0, sizeof(id));
    static const char *const keys[] = { "id", "offset", "baseId" };
    uint32_t *values[] = { &id.id, &id.offset, &id.baseId };
    for (size_t i = 0; i < FIELD_COUNT(keys); i++) {
        SV *value = fetch_defined(aTHX_ hv, keys[i]);
        if (value) *values[i] = (uint32_t) field_integer(aTHX_ value, label, keys[i], 0, (NV) UINT32_MAX);
    }
    return id;
}

/* ===========================================================================
 * Struct output (*_to_sv).
 * ======================================================================== */

SV *clay_color_to_sv(pTHX_ Clay_Color value)
{
    HV *hv = newHV();
    hv_store_nv(aTHX_ hv, "r", value.r);
    hv_store_nv(aTHX_ hv, "g", value.g);
    hv_store_nv(aTHX_ hv, "b", value.b);
    hv_store_nv(aTHX_ hv, "a", value.a);
    return newRV_noinc((SV *) hv);
}

SV *clay_vector2_to_sv(pTHX_ Clay_Vector2 value)
{
    HV *hv = newHV();
    hv_store_nv(aTHX_ hv, "x", value.x);
    hv_store_nv(aTHX_ hv, "y", value.y);
    return newRV_noinc((SV *) hv);
}

SV *clay_dimensions_to_sv(pTHX_ Clay_Dimensions value)
{
    HV *hv = newHV();
    hv_store_nv(aTHX_ hv, "width",  value.width);
    hv_store_nv(aTHX_ hv, "height", value.height);
    return newRV_noinc((SV *) hv);
}

SV *clay_bounding_box_to_sv(pTHX_ Clay_BoundingBox value)
{
    HV *hv = newHV();
    hv_store_nv(aTHX_ hv, "x",      value.x);
    hv_store_nv(aTHX_ hv, "y",      value.y);
    hv_store_nv(aTHX_ hv, "width",  value.width);
    hv_store_nv(aTHX_ hv, "height", value.height);
    return newRV_noinc((SV *) hv);
}

SV *clay_corner_radius_to_sv(pTHX_ Clay_CornerRadius value)
{
    HV *hv = newHV();
    hv_store_nv(aTHX_ hv, "topLeft",     value.topLeft);
    hv_store_nv(aTHX_ hv, "topRight",    value.topRight);
    hv_store_nv(aTHX_ hv, "bottomLeft",  value.bottomLeft);
    hv_store_nv(aTHX_ hv, "bottomRight", value.bottomRight);
    return newRV_noinc((SV *) hv);
}

SV *clay_padding_to_sv(pTHX_ Clay_Padding value)
{
    HV *hv = newHV();
    hv_store_uv(aTHX_ hv, "left",   value.left);
    hv_store_uv(aTHX_ hv, "right",  value.right);
    hv_store_uv(aTHX_ hv, "top",    value.top);
    hv_store_uv(aTHX_ hv, "bottom", value.bottom);
    return newRV_noinc((SV *) hv);
}

SV *clay_border_width_to_sv(pTHX_ Clay_BorderWidth value)
{
    HV *hv = newHV();
    hv_store_uv(aTHX_ hv, "left",            value.left);
    hv_store_uv(aTHX_ hv, "right",           value.right);
    hv_store_uv(aTHX_ hv, "top",             value.top);
    hv_store_uv(aTHX_ hv, "bottom",          value.bottom);
    hv_store_uv(aTHX_ hv, "betweenChildren", value.betweenChildren);
    return newRV_noinc((SV *) hv);
}

SV *clay_sizing_axis_to_sv(pTHX_ Clay_SizingAxis value)
{
    HV *hv = newHV();
    hv_store_iv(aTHX_ hv, "type", (IV) value.type);
    if (value.type == CLAY__SIZING_TYPE_PERCENT) {
        hv_store_nv(aTHX_ hv, "percent", value.size.percent);
    } else {
        hv_store_nv(aTHX_ hv, "min", value.size.minMax.min);
        hv_store_nv(aTHX_ hv, "max", value.size.minMax.max);
    }
    return newRV_noinc((SV *) hv);
}

SV *clay_text_element_config_to_sv(pTHX_ Clay_TextElementConfig value)
{
    HV *hv = newHV();
    hv_store_sv(aTHX_ hv, "textColor",     clay_color_to_sv(aTHX_ value.textColor));
    hv_store_uv(aTHX_ hv, "fontId",        value.fontId);
    hv_store_uv(aTHX_ hv, "fontSize",      value.fontSize);
    hv_store_uv(aTHX_ hv, "letterSpacing", value.letterSpacing);
    hv_store_uv(aTHX_ hv, "lineHeight",    value.lineHeight);
    hv_store_iv(aTHX_ hv, "wrapMode",      (IV) value.wrapMode);
    hv_store_iv(aTHX_ hv, "textAlignment", (IV) value.textAlignment);
    hv_store_uv(aTHX_ hv, "userData",      PTR2UV(value.userData));
    return newRV_noinc((SV *) hv);
}

SV *clay_transition_data_to_sv(pTHX_ Clay_TransitionData data)
{
    HV *hv = newHV();
    hv_store_sv(aTHX_ hv, "boundingBox",     clay_bounding_box_to_sv(aTHX_ data.boundingBox));
    hv_store_sv(aTHX_ hv, "backgroundColor", clay_color_to_sv(aTHX_ data.backgroundColor));
    hv_store_sv(aTHX_ hv, "overlayColor",    clay_color_to_sv(aTHX_ data.overlayColor));
    hv_store_sv(aTHX_ hv, "borderColor",     clay_color_to_sv(aTHX_ data.borderColor));
    hv_store_sv(aTHX_ hv, "borderWidth",     clay_border_width_to_sv(aTHX_ data.borderWidth));
    return newRV_noinc((SV *) hv);
}

SV *clay_element_id_to_sv(pTHX_ Clay_ElementId id)
{
    HV *hv = newHV();
    hv_store_uv(aTHX_ hv, "id",     id.id);
    hv_store_uv(aTHX_ hv, "offset", id.offset);
    hv_store_uv(aTHX_ hv, "baseId", id.baseId);
    if (id.stringId.chars && id.stringId.length > 0) {
        hv_store_sv(aTHX_ hv, "stringId", clay_perl_utf8_sv(aTHX_ id.stringId.chars, id.stringId.length));
    }
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_PointerData (return-only).
 * ======================================================================== */

SV *clay_pointer_data_to_sv(pTHX_ Clay_PointerData data)
{
    HV *hv = newHV();
    hv_store_sv(aTHX_ hv, "position", clay_vector2_to_sv(aTHX_ data.position));
    hv_store_iv(aTHX_ hv, "state",    (IV) data.state);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_ElementData and Clay_ScrollContainerData (return-only).
 * ======================================================================== */

SV *clay_element_data_to_sv(pTHX_ Clay_ElementData data)
{
    HV *hv = newHV();
    hv_store_sv(aTHX_ hv, "boundingBox", clay_bounding_box_to_sv(aTHX_ data.boundingBox));
    hv_store_bool(aTHX_ hv, "found", data.found);
    return newRV_noinc((SV *) hv);
}

SV *clay_scroll_container_data_to_sv(pTHX_ Clay_ScrollContainerData data)
{
    HV *hv = newHV();
    Clay_Vector2 zero = { 0, 0 };
    hv_store_sv(aTHX_ hv, "scrollPosition",
                clay_vector2_to_sv(aTHX_ data.scrollPosition ? *data.scrollPosition : zero));
    hv_store_sv(aTHX_ hv, "scrollContainerDimensions",
                clay_dimensions_to_sv(aTHX_ data.scrollContainerDimensions));
    hv_store_sv(aTHX_ hv, "contentDimensions",
                clay_dimensions_to_sv(aTHX_ data.contentDimensions));

    HV *config_hv = newHV();
    hv_store_bool(aTHX_ config_hv, "horizontal", data.config.horizontal);
    hv_store_bool(aTHX_ config_hv, "vertical",   data.config.vertical);
    hv_store_sv  (aTHX_ config_hv, "childOffset", clay_vector2_to_sv(aTHX_ data.config.childOffset));
    hv_store_sv(aTHX_ hv, "config", newRV_noinc((SV *) config_hv));

    hv_store_bool(aTHX_ hv, "found", data.found);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_RenderCommand and the render command array.
 *
 * Each command becomes a hashref with these keys:
 *
 *   id          : uint32_t
 *   zIndex      : int16_t
 *   commandType : Clay_RenderCommandType enum value
 *   boundingBox : { x, y, width, height }
 *   userData    : the unsigned integer passed as userData (0 when none)
 *   renderData  : type-specific hashref (see below)
 *
 * The renderData shape depends on commandType. The shape mirrors the C
 * union member that Clay would have populated.
 * ======================================================================== */

static SV *clay_render_data_to_sv(pTHX_ const Clay_RenderCommand *cmd)
{
    HV *hv = newHV();

    switch (cmd->commandType) {
    case CLAY_RENDER_COMMAND_TYPE_RECTANGLE:
        hv_store_sv(aTHX_ hv, "backgroundColor",
                    clay_color_to_sv(aTHX_ cmd->renderData.rectangle.backgroundColor));
        hv_store_sv(aTHX_ hv, "cornerRadius",
                    clay_corner_radius_to_sv(aTHX_ cmd->renderData.rectangle.cornerRadius));
        break;

    case CLAY_RENDER_COMMAND_TYPE_TEXT:
        hv_store_sv(aTHX_ hv, "stringContents",
                    clay_perl_utf8_sv(aTHX_ cmd->renderData.text.stringContents.chars,
                                      cmd->renderData.text.stringContents.length));
        hv_store_sv(aTHX_ hv, "textColor",
                    clay_color_to_sv(aTHX_ cmd->renderData.text.textColor));
        hv_store_uv(aTHX_ hv, "fontId",        cmd->renderData.text.fontId);
        hv_store_uv(aTHX_ hv, "fontSize",      cmd->renderData.text.fontSize);
        hv_store_uv(aTHX_ hv, "letterSpacing", cmd->renderData.text.letterSpacing);
        hv_store_uv(aTHX_ hv, "lineHeight",    cmd->renderData.text.lineHeight);
        break;

    case CLAY_RENDER_COMMAND_TYPE_IMAGE:
        hv_store_sv(aTHX_ hv, "backgroundColor",
                    clay_color_to_sv(aTHX_ cmd->renderData.image.backgroundColor));
        hv_store_sv(aTHX_ hv, "cornerRadius",
                    clay_corner_radius_to_sv(aTHX_ cmd->renderData.image.cornerRadius));
        hv_store_uv(aTHX_ hv, "imageData", PTR2UV(cmd->renderData.image.imageData));
        break;

    case CLAY_RENDER_COMMAND_TYPE_CUSTOM:
        hv_store_sv(aTHX_ hv, "backgroundColor",
                    clay_color_to_sv(aTHX_ cmd->renderData.custom.backgroundColor));
        hv_store_sv(aTHX_ hv, "cornerRadius",
                    clay_corner_radius_to_sv(aTHX_ cmd->renderData.custom.cornerRadius));
        hv_store_uv(aTHX_ hv, "customData", PTR2UV(cmd->renderData.custom.customData));
        break;

    case CLAY_RENDER_COMMAND_TYPE_BORDER:
        hv_store_sv(aTHX_ hv, "color",
                    clay_color_to_sv(aTHX_ cmd->renderData.border.color));
        hv_store_sv(aTHX_ hv, "cornerRadius",
                    clay_corner_radius_to_sv(aTHX_ cmd->renderData.border.cornerRadius));
        hv_store_sv(aTHX_ hv, "width",
                    clay_border_width_to_sv(aTHX_ cmd->renderData.border.width));
        break;

    case CLAY_RENDER_COMMAND_TYPE_SCISSOR_START:
    case CLAY_RENDER_COMMAND_TYPE_SCISSOR_END:
        hv_store_bool(aTHX_ hv, "horizontal", cmd->renderData.clip.horizontal);
        hv_store_bool(aTHX_ hv, "vertical",   cmd->renderData.clip.vertical);
        break;

    case CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_START:
    case CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_END:
        hv_store_sv(aTHX_ hv, "color",
                    clay_color_to_sv(aTHX_ cmd->renderData.overlayColor.color));
        break;

    case CLAY_RENDER_COMMAND_TYPE_NONE:
    default:
        break;
    }
    return newRV_noinc((SV *) hv);
}

static SV *clay_render_command_to_sv(pTHX_ const Clay_RenderCommand *cmd)
{
    HV *hv = newHV();
    hv_store_sv(aTHX_ hv, "boundingBox", clay_bounding_box_to_sv(aTHX_ cmd->boundingBox));
    hv_store_sv(aTHX_ hv, "renderData",  clay_render_data_to_sv(aTHX_ cmd));
    hv_store_uv(aTHX_ hv, "userData",    PTR2UV(cmd->userData));
    hv_store_uv(aTHX_ hv, "id",          cmd->id);
    hv_store_iv(aTHX_ hv, "zIndex",      (IV) cmd->zIndex);
    hv_store_iv(aTHX_ hv, "commandType", (IV) cmd->commandType);
    return newRV_noinc((SV *) hv);
}

SV *clay_render_command_array_to_sv(pTHX_ const Clay_RenderCommandArray *array)
{
    AV *av = newAV();
    if (array && array->internalArray && array->length > 0) {
        av_extend(av, array->length - 1);
        for (int32_t i = 0; i < array->length; i++) {
            av_push(av, clay_render_command_to_sv(aTHX_ &array->internalArray[i]));
        }
    }
    return newRV_noinc((SV *) av);
}
