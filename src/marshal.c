/*
 * marshal.c - HV/AV <-> Clay struct converters.
 *
 * Functions named *_from_sv take a Perl SV and return a fully-populated
 * Clay struct (or croak on bad input). Functions named *_to_sv take a
 * Clay struct and return a new, non-mortal Perl value owning fresh memory.
 *
 * The design choices baked into this file:
 *
 *   - Compact types (Color, Vector2, Dimensions) accept either an
 *     arrayref or a hashref. Fields use exact C names (backgroundColor,
 *     layoutDirection, etc.) so users can read clay.h verbatim and
 *     translate to Perl hash keys.
 *
 *   - Missing or undef fields default to a zero-initialised struct value,
 *     exactly like C's designated initialisers. Clay's defaults
 *     (left-to-right layout, fit sizing, etc.) are themselves zero, so a
 *     bare {} gives sensible behaviour.
 *
 *   - Fail Fast: every present value is parsed at this boundary. A wrong
 *     reference type (e.g. an arrayref where a hashref is needed, at any
 *     nesting level), a non-numeric value, a non-finite float, a
 *     fractional integer or an integer outside the C field's range croaks
 *     with the struct and field name. Values are fetched once (one
 *     get-magic call) and read with the _nomg accessors.
 *
 *   - Strings are characters: text comes back from Clay as UTF-8 flagged
 *     Perl strings (clay_perl_utf8_sv).
 */

#include "clay_perl.h"

#include <math.h>
#include <string.h>

/* ===========================================================================
 * Labels and error messages.
 *
 * A label names the value being parsed: a chain of names from the
 * outermost struct (or function argument) inwards, plus an optional field
 * name at the point of use. Labels are compound literals on the parser's
 * stack and are formatted only when a croak needs them, so a successful
 * parse builds no strings.
 * ======================================================================== */

typedef struct marshal_label {
    const struct marshal_label *outer;
    const char *name;
} marshal_label;

#define ROOT_LABEL(name)          (&(const marshal_label){ NULL, (name) })
#define NESTED_LABEL(outer, name) (&(const marshal_label){ (outer), (name) })

static void append_label(pTHX_ SV *out, const marshal_label *label)
{
    if (!label) return;
    append_label(aTHX_ out, label->outer);
    if (SvCUR(out)) sv_catpvs(out, ".");
    sv_catpv(out, label->name);
}

/* "outer.inner.field" as a mortal SV. */
static SV *format_label(pTHX_ const marshal_label *what, const char *field)
{
    SV *out = sv_2mortal(newSVpvs(""));
    append_label(aTHX_ out, what);
    if (field) {
        if (SvCUR(out)) sv_catpvs(out, ".");
        sv_catpv(out, field);
    }
    return out;
}

static void croak_bad_value(pTHX_ const marshal_label *what, const char *field,
                            const char *expected, SV *sv)
    __attribute__noreturn__;

static void croak_bad_value(pTHX_ const marshal_label *what, const char *field,
                            const char *expected, SV *sv)
{
    SV *label = format_label(aTHX_ what, field);
    if (!SvOK(sv)) {
        croak("%" SVf ": expected %s, got undef", SVfARG(label), expected);
    }
    if (SvROK(sv)) {
        croak("%" SVf ": expected %s, got a %s reference",
              SVfARG(label), expected, sv_reftype(SvRV(sv), 0));
    }
    croak("%" SVf ": expected %s, got '%" SVf "'", SVfARG(label), expected, SVfARG(sv));
}

static void croak_bad_integer(pTHX_ const marshal_label *what, const char *field,
                              NV min, NV max, SV *sv)
    __attribute__noreturn__;

static void croak_bad_integer(pTHX_ const marshal_label *what, const char *field,
                              NV min, NV max, SV *sv)
{
    SV *expected = sv_2mortal(newSVpvf("an integer in %.0f..%.0f", (double) min, (double) max));
    croak_bad_value(aTHX_ what, field, SvPV_nolen(expected), sv);
}

/* ===========================================================================
 * Scalar parsing. Every parser takes a defined SV whose get-magic has run.
 * ======================================================================== */

static bool is_number_nomg(pTHX_ SV *sv)
{
    return SvROK(sv) ? cBOOL(SvAMAGIC(sv)) : cBOOL(looks_like_number(sv));
}

static float parse_finite_nomg(pTHX_ SV *sv, const marshal_label *what, const char *field)
{
    if (!is_number_nomg(aTHX_ sv)) croak_bad_value(aTHX_ what, field, "a finite number", sv);
    NV nv = SvNV_nomg(sv);
    if (Perl_isnan(nv) || Perl_isinf(nv)) croak_bad_value(aTHX_ what, field, "a finite number", sv);
    return (float) nv;
}

/* A size maximum: finite, or +Inf for "unbounded" (Clay also treats 0 as
 * "no max"). */
static float parse_max_nomg(pTHX_ SV *sv, const marshal_label *what, const char *field)
{
    static const char expected[] = "a finite number or +Inf";
    if (!is_number_nomg(aTHX_ sv)) croak_bad_value(aTHX_ what, field, expected, sv);
    NV nv = SvNV_nomg(sv);
    if (Perl_isnan(nv) || (Perl_isinf(nv) && nv < 0)) croak_bad_value(aTHX_ what, field, expected, sv);
    return (float) nv;
}

/* Integers are range-checked as NV: every bound used here (at most
 * 32 bits) is exact in a double, also on perls with a 32-bit IV. */
static NV parse_integer_nomg(pTHX_ SV *sv, const marshal_label *what, const char *field,
                             NV min, NV max)
{
    if (!is_number_nomg(aTHX_ sv)) croak_bad_integer(aTHX_ what, field, min, max, sv);
    NV nv = SvNV_nomg(sv);
    if (Perl_isnan(nv) || nv != Perl_floor(nv) || nv < min || nv > max) {
        croak_bad_integer(aTHX_ what, field, min, max, sv);
    }
    return nv;
}

/* Opaque pointer-sized integers (userData, imageData, customData). */
static void *parse_pointer_nomg(pTHX_ SV *sv, const marshal_label *what, const char *field)
{
    bool integral = !SvROK(sv) && looks_like_number(sv)
                 && (SvIOK(sv) || SvNV_nomg(sv) == Perl_floor(SvNV_nomg(sv)));
    if (!integral) croak_bad_value(aTHX_ what, field, "an integer", sv);
    if (SvIOK(sv) && SvIsUV(sv)) return INT2PTR(void *, SvUV_nomg(sv));
    return INT2PTR(void *, SvIV_nomg(sv));
}

double clay_perl_parse_float(pTHX_ SV *sv, const char *what)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) croak_bad_value(aTHX_ ROOT_LABEL(what), NULL, "a finite number", sv);
    return parse_finite_nomg(aTHX_ sv, ROOT_LABEL(what), NULL);
}

double clay_perl_parse_max_float(pTHX_ SV *sv, const char *what)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) croak_bad_value(aTHX_ ROOT_LABEL(what), NULL, "a finite number or +Inf", sv);
    return parse_max_nomg(aTHX_ sv, ROOT_LABEL(what), NULL);
}

UV clay_perl_parse_uint(pTHX_ SV *sv, const char *what, UV max)
{
    return (UV) clay_perl_parse_integer(aTHX_ sv, what, 0, (NV) max);
}

NV clay_perl_parse_integer(pTHX_ SV *sv, const char *what, NV min, NV max)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) croak_bad_integer(aTHX_ ROOT_LABEL(what), NULL, min, max, sv);
    return parse_integer_nomg(aTHX_ sv, ROOT_LABEL(what), NULL, min, max);
}

SV *clay_perl_require_code(pTHX_ SV *sv, const char *what, bool allow_undef)
{
    SvGETMAGIC(sv);
    if (!SvOK(sv)) {
        if (allow_undef) return NULL;
        croak("%s: expected a CODE reference, got undef", what);
    }
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVCV) {
        croak_bad_value(aTHX_ ROOT_LABEL(what), NULL,
                        allow_undef ? "a CODE reference or undef" : "a CODE reference", sv);
    }
    return sv;
}

/* ===========================================================================
 * Hash and array field access.
 * ======================================================================== */

/* Returns the value stored under key, or NULL if the key is absent. Its
 * get-magic has not run; the consumer runs it exactly once. */
static SV *fetch_slot(pTHX_ HV *hv, const char *key)
{
    SV **slot = hv_fetch(hv, key, (I32) strlen(key), 0);
    return (slot && *slot) ? *slot : NULL;
}

/* Like fetch_slot, with get-magic applied; NULL for absent or undef. */
static SV *fetch_defined(pTHX_ HV *hv, const char *key)
{
    SV *sv = fetch_slot(aTHX_ hv, key);
    if (!sv) return NULL;
    SvGETMAGIC(sv);
    return SvOK(sv) ? sv : NULL;
}

static SV *fetch_index_defined(pTHX_ AV *av, SSize_t index)
{
    SV **slot = av_fetch(av, index, 0);
    if (!slot || !*slot) return NULL;
    SvGETMAGIC(*slot);
    return SvOK(*slot) ? *slot : NULL;
}

static float fetch_float(pTHX_ HV *hv, const char *key, const marshal_label *what)
{
    SV *sv = fetch_defined(aTHX_ hv, key);
    return sv ? parse_finite_nomg(aTHX_ sv, what, key) : 0.0f;
}

static float fetch_index_float(pTHX_ AV *av, SSize_t index, const marshal_label *what, const char *field)
{
    SV *sv = fetch_index_defined(aTHX_ av, index);
    return sv ? parse_finite_nomg(aTHX_ sv, what, field) : 0.0f;
}

static uint16_t fetch_u16(pTHX_ HV *hv, const char *key, const marshal_label *what)
{
    SV *sv = fetch_defined(aTHX_ hv, key);
    return sv ? (uint16_t) parse_integer_nomg(aTHX_ sv, what, key, 0, UINT16_MAX) : 0;
}

static int16_t fetch_i16(pTHX_ HV *hv, const char *key, const marshal_label *what)
{
    SV *sv = fetch_defined(aTHX_ hv, key);
    return sv ? (int16_t) parse_integer_nomg(aTHX_ sv, what, key, INT16_MIN, INT16_MAX) : 0;
}

static uint32_t fetch_u32(pTHX_ HV *hv, const char *key, const marshal_label *what)
{
    SV *sv = fetch_defined(aTHX_ hv, key);
    return sv ? (uint32_t) parse_integer_nomg(aTHX_ sv, what, key, 0, (NV) UINT32_MAX) : 0;
}

/* Clay enums are one-byte packed; values run 0..max. */
static int fetch_enum(pTHX_ HV *hv, const char *key, const marshal_label *what, int max)
{
    SV *sv = fetch_defined(aTHX_ hv, key);
    return sv ? (int) parse_integer_nomg(aTHX_ sv, what, key, 0, max) : 0;
}

static bool fetch_bool(pTHX_ HV *hv, const char *key)
{
    SV *sv = fetch_defined(aTHX_ hv, key);
    return sv ? cBOOL(SvTRUE_nomg(sv)) : false;
}

static void *fetch_pointer(pTHX_ HV *hv, const char *key, const marshal_label *what)
{
    SV *sv = fetch_defined(aTHX_ hv, key);
    return sv ? parse_pointer_nomg(aTHX_ sv, what, key) : NULL;
}

/* sv is defined and its get-magic has run: returns the referenced hash
 * or croaks. */
static HV *hash_nomg(pTHX_ SV *sv, const marshal_label *what)
{
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak_bad_value(aTHX_ what, NULL, "a hash reference", sv);
    }
    return (HV *) SvRV(sv);
}

/* Runs sv's get-magic and returns the referenced hash; NULL for NULL or
 * undef; croaks for any other value. */
static HV *as_hash(pTHX_ SV *sv, const marshal_label *what)
{
    if (!sv) return NULL;
    SvGETMAGIC(sv);
    if (!SvOK(sv)) return NULL;
    return hash_nomg(aTHX_ sv, what);
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
 * Compact types: Clay_Color {r,g,b,a} / [r,g,b,a], Clay_Vector2 {x,y} /
 * [x,y], Clay_Dimensions {width,height} / [width,height].
 * ======================================================================== */

/* sv is defined and its get-magic has run: resolves it to an array or a
 * hash, croaking for anything else. */
static void array_or_hash_nomg(pTHX_ SV *sv, const marshal_label *what, AV **av, HV **hv)
{
    *av = NULL;
    *hv = NULL;
    if (SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVAV) {
        *av = (AV *) SvRV(sv);
        return;
    }
    if (SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVHV) {
        *hv = (HV *) SvRV(sv);
        return;
    }
    croak_bad_value(aTHX_ what, NULL, "a hash or array reference", sv);
}

/* Runs sv's get-magic and resolves it; returns false for NULL or undef. */
static bool array_or_hash(pTHX_ SV *sv, const marshal_label *what, AV **av, HV **hv)
{
    *av = NULL;
    *hv = NULL;
    if (!sv) return false;
    SvGETMAGIC(sv);
    if (!SvOK(sv)) return false;
    array_or_hash_nomg(aTHX_ sv, what, av, hv);
    return true;
}

static Clay_Color color_from_parts(pTHX_ AV *av, HV *hv, const marshal_label *what)
{
    static const char *const channel[4] = { "r", "g", "b", "a" };
    Clay_Color c = { 0, 0, 0, 0 };
    float *out[4] = { &c.r, &c.g, &c.b, &c.a };
    for (int i = 0; i < 4; i++) {
        *out[i] = av ? fetch_index_float(aTHX_ av, i, what, channel[i])
                     : fetch_float(aTHX_ hv, channel[i], what);
    }
    return c;
}

static Clay_Color color_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_Color zero = { 0, 0, 0, 0 };
    AV *av;
    HV *hv;
    if (!array_or_hash(aTHX_ sv, what, &av, &hv)) return zero;
    return color_from_parts(aTHX_ av, hv, what);
}

Clay_Color clay_color_from_sv(pTHX_ SV *sv, const char *what)
{
    return color_from_sv(aTHX_ sv, ROOT_LABEL(what));
}

SV *clay_color_to_sv(pTHX_ Clay_Color value)
{
    HV *hv = newHV();
    hv_store_nv(aTHX_ hv, "r", value.r);
    hv_store_nv(aTHX_ hv, "g", value.g);
    hv_store_nv(aTHX_ hv, "b", value.b);
    hv_store_nv(aTHX_ hv, "a", value.a);
    return newRV_noinc((SV *) hv);
}

static Clay_Vector2 vector2_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_Vector2 v = { 0, 0 };
    AV *av;
    HV *hv;
    if (!array_or_hash(aTHX_ sv, what, &av, &hv)) return v;
    v.x = av ? fetch_index_float(aTHX_ av, 0, what, "x") : fetch_float(aTHX_ hv, "x", what);
    v.y = av ? fetch_index_float(aTHX_ av, 1, what, "y") : fetch_float(aTHX_ hv, "y", what);
    return v;
}

Clay_Vector2 clay_vector2_from_sv(pTHX_ SV *sv, const char *what)
{
    return vector2_from_sv(aTHX_ sv, ROOT_LABEL(what));
}

SV *clay_vector2_to_sv(pTHX_ Clay_Vector2 value)
{
    HV *hv = newHV();
    hv_store_nv(aTHX_ hv, "x", value.x);
    hv_store_nv(aTHX_ hv, "y", value.y);
    return newRV_noinc((SV *) hv);
}

static Clay_Dimensions dimensions_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_Dimensions d = { 0, 0 };
    AV *av;
    HV *hv;
    if (!array_or_hash(aTHX_ sv, what, &av, &hv)) return d;
    d.width  = av ? fetch_index_float(aTHX_ av, 0, what, "width")  : fetch_float(aTHX_ hv, "width", what);
    d.height = av ? fetch_index_float(aTHX_ av, 1, what, "height") : fetch_float(aTHX_ hv, "height", what);
    return d;
}

Clay_Dimensions clay_dimensions_from_sv(pTHX_ SV *sv, const char *what)
{
    return dimensions_from_sv(aTHX_ sv, ROOT_LABEL(what));
}

SV *clay_dimensions_to_sv(pTHX_ Clay_Dimensions value)
{
    HV *hv = newHV();
    hv_store_nv(aTHX_ hv, "width",  value.width);
    hv_store_nv(aTHX_ hv, "height", value.height);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_BoundingBox - {x,y,width,height}.
 * ======================================================================== */

static Clay_BoundingBox bounding_box_from_hv(pTHX_ HV *hv, const marshal_label *what)
{
    Clay_BoundingBox bb = { 0, 0, 0, 0 };
    if (!hv) return bb;
    bb.x      = fetch_float(aTHX_ hv, "x", what);
    bb.y      = fetch_float(aTHX_ hv, "y", what);
    bb.width  = fetch_float(aTHX_ hv, "width", what);
    bb.height = fetch_float(aTHX_ hv, "height", what);
    return bb;
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

/* ===========================================================================
 * Clay_CornerRadius - {topLeft,topRight,bottomLeft,bottomRight}.
 * Also accepts a number (applied to all four corners), like the C
 * CLAY_CORNER_RADIUS(r) macro.
 * ======================================================================== */

static Clay_CornerRadius clay_corner_radius_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_CornerRadius r = { 0, 0, 0, 0 };
    if (!sv) return r;
    SvGETMAGIC(sv);
    if (!SvOK(sv)) return r;

    if (!SvROK(sv) || SvAMAGIC(sv)) {
        float n = parse_finite_nomg(aTHX_ sv, what, NULL);
        r.topLeft = r.topRight = r.bottomLeft = r.bottomRight = n;
        return r;
    }
    if (SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak_bad_value(aTHX_ what, NULL, "a number or hash reference", sv);
    }
    HV *hv = (HV *) SvRV(sv);
    r.topLeft     = fetch_float(aTHX_ hv, "topLeft", what);
    r.topRight    = fetch_float(aTHX_ hv, "topRight", what);
    r.bottomLeft  = fetch_float(aTHX_ hv, "bottomLeft", what);
    r.bottomRight = fetch_float(aTHX_ hv, "bottomRight", what);
    return r;
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

/* ===========================================================================
 * Clay_Padding - {left,right,top,bottom}.
 * ======================================================================== */

static Clay_Padding clay_padding_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_Padding p = { 0, 0, 0, 0 };
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return p;
    p.left   = fetch_u16(aTHX_ hv, "left", what);
    p.right  = fetch_u16(aTHX_ hv, "right", what);
    p.top    = fetch_u16(aTHX_ hv, "top", what);
    p.bottom = fetch_u16(aTHX_ hv, "bottom", what);
    return p;
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

/* ===========================================================================
 * Clay_BorderWidth - {left,right,top,bottom,betweenChildren}.
 * ======================================================================== */

static Clay_BorderWidth border_width_from_hv(pTHX_ HV *hv, const marshal_label *what)
{
    Clay_BorderWidth w = { 0, 0, 0, 0, 0 };
    if (!hv) return w;
    w.left            = fetch_u16(aTHX_ hv, "left", what);
    w.right           = fetch_u16(aTHX_ hv, "right", what);
    w.top             = fetch_u16(aTHX_ hv, "top", what);
    w.bottom          = fetch_u16(aTHX_ hv, "bottom", what);
    w.betweenChildren = fetch_u16(aTHX_ hv, "betweenChildren", what);
    return w;
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

/* ===========================================================================
 * Clay_ChildAlignment - {x,y} (enum values).
 * ======================================================================== */

static Clay_ChildAlignment clay_child_alignment_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_ChildAlignment a = { CLAY_ALIGN_X_LEFT, CLAY_ALIGN_Y_TOP };
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return a;
    a.x = (Clay_LayoutAlignmentX) fetch_enum(aTHX_ hv, "x", what, CLAY_ALIGN_X_CENTER);
    a.y = (Clay_LayoutAlignmentY) fetch_enum(aTHX_ hv, "y", what, CLAY_ALIGN_Y_CENTER);
    return a;
}

/* ===========================================================================
 * Clay_SizingAxis - { type, min, max } for fit/grow/fixed (union member
 * minMax) or { type, percent } for percent. The XS sizing_*() helpers
 * produce these hashes; users can also build them directly.
 * ======================================================================== */

static Clay_SizingAxis clay_sizing_axis_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_SizingAxis axis;
    memset(&axis, 0, sizeof(axis));
    axis.type = CLAY__SIZING_TYPE_FIT;

    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return axis;
    axis.type = (Clay__SizingType) fetch_enum(aTHX_ hv, "type", what, CLAY__SIZING_TYPE_FIXED);

    if (axis.type == CLAY__SIZING_TYPE_PERCENT) {
        axis.size.percent = fetch_float(aTHX_ hv, "percent", what);
        return axis;
    }
    axis.size.minMax.min = fetch_float(aTHX_ hv, "min", what);
    SV *max = fetch_defined(aTHX_ hv, "max");
    axis.size.minMax.max = max ? parse_max_nomg(aTHX_ max, what, "max") : 0.0f;
    return axis;
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

/* ===========================================================================
 * Clay_Sizing - { width => SizingAxis, height => SizingAxis }.
 * ======================================================================== */

static Clay_Sizing clay_sizing_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_Sizing s;
    memset(&s, 0, sizeof(s));
    s.width.type  = CLAY__SIZING_TYPE_FIT;
    s.height.type = CLAY__SIZING_TYPE_FIT;

    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return s;
    s.width  = clay_sizing_axis_from_sv(aTHX_ fetch_slot(aTHX_ hv, "width"),
                                        NESTED_LABEL(what, "width"));
    s.height = clay_sizing_axis_from_sv(aTHX_ fetch_slot(aTHX_ hv, "height"),
                                        NESTED_LABEL(what, "height"));
    return s;
}

/* ===========================================================================
 * Clay_LayoutConfig.
 * ======================================================================== */

static Clay_LayoutConfig clay_layout_config_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_LayoutConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return cfg;

    cfg.sizing         = clay_sizing_from_sv(aTHX_ fetch_slot(aTHX_ hv, "sizing"),
                                             NESTED_LABEL(what, "sizing"));
    cfg.padding        = clay_padding_from_sv(aTHX_ fetch_slot(aTHX_ hv, "padding"),
                                              NESTED_LABEL(what, "padding"));
    cfg.childAlignment = clay_child_alignment_from_sv(aTHX_ fetch_slot(aTHX_ hv, "childAlignment"),
                                                      NESTED_LABEL(what, "childAlignment"));
    cfg.childGap        = fetch_u16(aTHX_ hv, "childGap", what);
    cfg.layoutDirection = (Clay_LayoutDirection)
                          fetch_enum(aTHX_ hv, "layoutDirection", what, CLAY_TOP_TO_BOTTOM);
    return cfg;
}

/* ===========================================================================
 * Clay_TextElementConfig.
 *
 * userData is held as an opaque pointer-sized integer (no SV refcount is
 * taken); render commands carry it back unchanged.
 * ======================================================================== */

Clay_TextElementConfig clay_text_element_config_from_sv(pTHX_ SV *sv)
{
    const marshal_label *what = ROOT_LABEL("Clay_TextElementConfig");
    Clay_TextElementConfig cfg;
    memset(&cfg, 0, sizeof(cfg));
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return cfg;

    cfg.textColor     = color_from_sv(aTHX_ fetch_slot(aTHX_ hv, "textColor"),
                                           NESTED_LABEL(what, "textColor"));
    cfg.fontId        = fetch_u16(aTHX_ hv, "fontId", what);
    cfg.fontSize      = fetch_u16(aTHX_ hv, "fontSize", what);
    cfg.letterSpacing = fetch_u16(aTHX_ hv, "letterSpacing", what);
    cfg.lineHeight    = fetch_u16(aTHX_ hv, "lineHeight", what);
    cfg.wrapMode      = (Clay_TextElementConfigWrapMode)
                        fetch_enum(aTHX_ hv, "wrapMode", what, CLAY_TEXT_WRAP_NONE);
    cfg.textAlignment = (Clay_TextAlignment)
                        fetch_enum(aTHX_ hv, "textAlignment", what, CLAY_TEXT_ALIGN_RIGHT);
    cfg.userData      = fetch_pointer(aTHX_ hv, "userData", what);
    return cfg;
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
    hv_store_iv(aTHX_ hv, "userData",      PTR2IV(value.userData));
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Sub-configs that compose Clay_ElementDeclaration.
 * ======================================================================== */

static Clay_AspectRatioElementConfig clay_aspect_ratio_config_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_AspectRatioElementConfig c = { 0 };
    if (!sv) return c;
    SvGETMAGIC(sv);
    if (!SvOK(sv)) return c;
    if (!SvROK(sv) || SvAMAGIC(sv)) {
        c.aspectRatio = parse_finite_nomg(aTHX_ sv, what, NULL);
        return c;
    }
    if (SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak_bad_value(aTHX_ what, NULL, "a number or hash reference", sv);
    }
    c.aspectRatio = fetch_float(aTHX_ (HV *) SvRV(sv), "aspectRatio", what);
    return c;
}

static Clay_ImageElementConfig clay_image_config_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_ImageElementConfig c = { 0 };
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return c;
    c.imageData = fetch_pointer(aTHX_ hv, "imageData", what);
    return c;
}

static Clay_CustomElementConfig clay_custom_config_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_CustomElementConfig c = { 0 };
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return c;
    c.customData = fetch_pointer(aTHX_ hv, "customData", what);
    return c;
}

static Clay_ClipElementConfig clay_clip_config_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_ClipElementConfig c = { false, false, { 0, 0 } };
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return c;
    c.horizontal  = fetch_bool(aTHX_ hv, "horizontal");
    c.vertical    = fetch_bool(aTHX_ hv, "vertical");
    c.childOffset = vector2_from_sv(aTHX_ fetch_slot(aTHX_ hv, "childOffset"),
                                         NESTED_LABEL(what, "childOffset"));
    return c;
}

static Clay_BorderElementConfig clay_border_config_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_BorderElementConfig c;
    memset(&c, 0, sizeof(c));
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return c;
    c.color = color_from_sv(aTHX_ fetch_slot(aTHX_ hv, "color"),
                                 NESTED_LABEL(what, "color"));
    const marshal_label *width_what = NESTED_LABEL(what, "width");
    c.width = border_width_from_hv(aTHX_ as_hash(aTHX_ fetch_slot(aTHX_ hv, "width"), width_what),
                                   width_what);
    return c;
}

/* floating.parentId: a numeric element id or an element-id hashref as
 * returned by Clay_GetElementId (its {id} is used). */
static uint32_t floating_parent_id(pTHX_ HV *hv, const marshal_label *what)
{
    SV *sv = fetch_defined(aTHX_ hv, "parentId");
    if (!sv) return 0;
    if (SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVHV) {
        return fetch_u32(aTHX_ (HV *) SvRV(sv), "id", NESTED_LABEL(what, "parentId"));
    }
    return (uint32_t) parse_integer_nomg(aTHX_ sv, what, "parentId", 0, (NV) UINT32_MAX);
}

static Clay_FloatingElementConfig clay_floating_config_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_FloatingElementConfig c;
    memset(&c, 0, sizeof(c));
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return c;

    c.offset   = vector2_from_sv(aTHX_ fetch_slot(aTHX_ hv, "offset"),
                                      NESTED_LABEL(what, "offset"));
    c.expand   = dimensions_from_sv(aTHX_ fetch_slot(aTHX_ hv, "expand"),
                                         NESTED_LABEL(what, "expand"));
    c.parentId = floating_parent_id(aTHX_ hv, what);
    c.zIndex   = fetch_i16(aTHX_ hv, "zIndex", what);

    const marshal_label *attach_what = NESTED_LABEL(what, "attachPoints");
    HV *attach = as_hash(aTHX_ fetch_slot(aTHX_ hv, "attachPoints"), attach_what);
    if (attach) {
        c.attachPoints.element = (Clay_FloatingAttachPointType)
            fetch_enum(aTHX_ attach, "element", attach_what, CLAY_ATTACH_POINT_RIGHT_BOTTOM);
        c.attachPoints.parent  = (Clay_FloatingAttachPointType)
            fetch_enum(aTHX_ attach, "parent", attach_what, CLAY_ATTACH_POINT_RIGHT_BOTTOM);
    }
    c.pointerCaptureMode = (Clay_PointerCaptureMode)
        fetch_enum(aTHX_ hv, "pointerCaptureMode", what, CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH);
    c.attachTo = (Clay_FloatingAttachToElement)
        fetch_enum(aTHX_ hv, "attachTo", what, CLAY_ATTACH_TO_ROOT);
    c.clipTo = (Clay_FloatingClipToElement)
        fetch_enum(aTHX_ hv, "clipTo", what, CLAY_CLIP_TO_ATTACHED_PARENT);
    return c;
}

/* ===========================================================================
 * Clay_TransitionData - {boundingBox, backgroundColor, overlayColor,
 * borderColor, borderWidth}. from_sv starts from `base` and overrides the
 * keys present, so a partial hash only changes what it names.
 * ======================================================================== */

static Clay_TransitionData transition_data_from_sv(pTHX_ SV *sv, Clay_TransitionData base, const marshal_label *what)
{
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return base;

    AV *av;
    HV *parts;
    SV *field;
    if ((field = fetch_defined(aTHX_ hv, "boundingBox"))) {
        const marshal_label *field_what = NESTED_LABEL(what, "boundingBox");
        base.boundingBox = bounding_box_from_hv(aTHX_ hash_nomg(aTHX_ field, field_what), field_what);
    }
    if ((field = fetch_defined(aTHX_ hv, "backgroundColor"))) {
        const marshal_label *field_what = NESTED_LABEL(what, "backgroundColor");
        array_or_hash_nomg(aTHX_ field, field_what, &av, &parts);
        base.backgroundColor = color_from_parts(aTHX_ av, parts, field_what);
    }
    if ((field = fetch_defined(aTHX_ hv, "overlayColor"))) {
        const marshal_label *field_what = NESTED_LABEL(what, "overlayColor");
        array_or_hash_nomg(aTHX_ field, field_what, &av, &parts);
        base.overlayColor = color_from_parts(aTHX_ av, parts, field_what);
    }
    if ((field = fetch_defined(aTHX_ hv, "borderColor"))) {
        const marshal_label *field_what = NESTED_LABEL(what, "borderColor");
        array_or_hash_nomg(aTHX_ field, field_what, &av, &parts);
        base.borderColor = color_from_parts(aTHX_ av, parts, field_what);
    }
    if ((field = fetch_defined(aTHX_ hv, "borderWidth"))) {
        const marshal_label *field_what = NESTED_LABEL(what, "borderWidth");
        base.borderWidth = border_width_from_hv(aTHX_ hash_nomg(aTHX_ field, field_what), field_what);
    }
    return base;
}

Clay_TransitionData clay_transition_data_from_sv(pTHX_ SV *sv, Clay_TransitionData base, const char *what)
{
    return transition_data_from_sv(aTHX_ sv, base, ROOT_LABEL(what));
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

/* ===========================================================================
 * Clay_TransitionElementConfig.
 *
 * The Perl side describes a transition as:
 *
 *   transition => {
 *       duration            => 0.25,
 *       properties          => CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR | ...,
 *       interactionHandling => CLAY_TRANSITION_DISABLE_INTERACTIONS_WHILE_TRANSITIONING_POSITION,
 *       enter => { trigger => CLAY_TRANSITION_ENTER_SKIP_ON_FIRST_PARENT_FRAME, hasSetInitial => 1 },
 *       exit  => { trigger => ..., siblingOrdering => ..., hasSetFinal => 1 },
 *   }
 *
 * The `hasSetInitial` / `hasSetFinal` booleans install the trampolines
 * for those slots; a set exit trampoline is what gives an element an exit
 * transition. The handler is always installed (Clay requires one to run
 * the transition at all). All three trampolines call the per-context
 * handler set installed with Clay_SetTransitionHandlers.
 * ======================================================================== */

/* Every property flag OR-ed together. */
#define ALL_TRANSITION_PROPERTIES \
    (CLAY_TRANSITION_PROPERTY_BOUNDING_BOX | CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR \
     | CLAY_TRANSITION_PROPERTY_OVERLAY_COLOR | CLAY_TRANSITION_PROPERTY_CORNER_RADIUS \
     | CLAY_TRANSITION_PROPERTY_BORDER)

static Clay_TransitionElementConfig clay_transition_config_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_TransitionElementConfig c;
    memset(&c, 0, sizeof(c));
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return c;

    c.duration   = fetch_float(aTHX_ hv, "duration", what);
    c.properties = (Clay_TransitionProperty)
                   fetch_enum(aTHX_ hv, "properties", what, ALL_TRANSITION_PROPERTIES);
    c.interactionHandling = (Clay_TransitionInteractionHandlingType)
        fetch_enum(aTHX_ hv, "interactionHandling", what,
                   CLAY_TRANSITION_ALLOW_INTERACTIONS_WHILE_TRANSITIONING_POSITION);
    c.handler = clay_perl_transition_handler_trampoline;

    const marshal_label *enter_what = NESTED_LABEL(what, "enter");
    HV *enter = as_hash(aTHX_ fetch_slot(aTHX_ hv, "enter"), enter_what);
    if (enter) {
        c.enter.trigger = (Clay_TransitionEnterTriggerType)
            fetch_enum(aTHX_ enter, "trigger", enter_what,
                       CLAY_TRANSITION_ENTER_TRIGGER_ON_FIRST_PARENT_FRAME);
        if (fetch_bool(aTHX_ enter, "hasSetInitial")) {
            c.enter.setInitialState = clay_perl_transition_set_initial_trampoline;
        }
    }

    const marshal_label *exit_what = NESTED_LABEL(what, "exit");
    HV *exit = as_hash(aTHX_ fetch_slot(aTHX_ hv, "exit"), exit_what);
    if (exit) {
        c.exit.trigger = (Clay_TransitionExitTriggerType)
            fetch_enum(aTHX_ exit, "trigger", exit_what,
                       CLAY_TRANSITION_EXIT_TRIGGER_WHEN_PARENT_EXITS);
        c.exit.siblingOrdering = (Clay_ExitTransitionSiblingOrdering)
            fetch_enum(aTHX_ exit, "siblingOrdering", exit_what,
                       CLAY_EXIT_TRANSITION_ORDERING_ABOVE_SIBLINGS);
        if (fetch_bool(aTHX_ exit, "hasSetFinal")) {
            c.exit.setFinalState = clay_perl_transition_set_final_trampoline;
        }
    }
    return c;
}

/* ===========================================================================
 * Clay_SizingGroup. {width => N, height => M}; either may be omitted.
 * ======================================================================== */

static Clay_SizingGroup clay_sizing_group_from_sv(pTHX_ SV *sv, const marshal_label *what)
{
    Clay_SizingGroup g;
    memset(&g, 0, sizeof(g));
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return g;
    g.width  = fetch_u32(aTHX_ hv, "width", what);
    g.height = fetch_u32(aTHX_ hv, "height", what);
    return g;
}

/* ===========================================================================
 * Clay_ElementDeclaration - the big one. Composes every sub-config above
 * plus the transition config.
 * ======================================================================== */

Clay_ElementDeclaration clay_element_declaration_from_sv(pTHX_ SV *sv)
{
    const marshal_label *what = ROOT_LABEL("Clay_ElementDeclaration");
    Clay_ElementDeclaration d;
    memset(&d, 0, sizeof(d));
    HV *hv = as_hash(aTHX_ sv, what);
    if (!hv) return d;

    d.layout          = clay_layout_config_from_sv(aTHX_ fetch_slot(aTHX_ hv, "layout"),
                                                   NESTED_LABEL(what, "layout"));
    d.backgroundColor = color_from_sv(aTHX_ fetch_slot(aTHX_ hv, "backgroundColor"),
                                           NESTED_LABEL(what, "backgroundColor"));
    d.overlayColor    = color_from_sv(aTHX_ fetch_slot(aTHX_ hv, "overlayColor"),
                                           NESTED_LABEL(what, "overlayColor"));
    d.cornerRadius    = clay_corner_radius_from_sv(aTHX_ fetch_slot(aTHX_ hv, "cornerRadius"),
                                                   NESTED_LABEL(what, "cornerRadius"));
    d.aspectRatio     = clay_aspect_ratio_config_from_sv(aTHX_ fetch_slot(aTHX_ hv, "aspectRatio"),
                                                         NESTED_LABEL(what, "aspectRatio"));
    d.image           = clay_image_config_from_sv(aTHX_ fetch_slot(aTHX_ hv, "image"),
                                                  NESTED_LABEL(what, "image"));
    d.floating        = clay_floating_config_from_sv(aTHX_ fetch_slot(aTHX_ hv, "floating"),
                                                     NESTED_LABEL(what, "floating"));
    d.custom          = clay_custom_config_from_sv(aTHX_ fetch_slot(aTHX_ hv, "custom"),
                                                   NESTED_LABEL(what, "custom"));
    d.clip            = clay_clip_config_from_sv(aTHX_ fetch_slot(aTHX_ hv, "clip"),
                                                 NESTED_LABEL(what, "clip"));
    d.border          = clay_border_config_from_sv(aTHX_ fetch_slot(aTHX_ hv, "border"),
                                                   NESTED_LABEL(what, "border"));
    d.transition      = clay_transition_config_from_sv(aTHX_ fetch_slot(aTHX_ hv, "transition"),
                                                       NESTED_LABEL(what, "transition"));
    d.sizingGroup     = clay_sizing_group_from_sv(aTHX_ fetch_slot(aTHX_ hv, "sizingGroup"),
                                                  NESTED_LABEL(what, "sizingGroup"));
    d.userData        = fetch_pointer(aTHX_ hv, "userData", what);
    return d;
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
    id.id     = fetch_u32(aTHX_ hv, "id", label);
    id.offset = fetch_u32(aTHX_ hv, "offset", label);
    id.baseId = fetch_u32(aTHX_ hv, "baseId", label);
    return id;
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
 *   userData    : the integer passed as userData (0 when none)
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
        hv_store_iv(aTHX_ hv, "imageData", PTR2IV(cmd->renderData.image.imageData));
        break;

    case CLAY_RENDER_COMMAND_TYPE_CUSTOM:
        hv_store_sv(aTHX_ hv, "backgroundColor",
                    clay_color_to_sv(aTHX_ cmd->renderData.custom.backgroundColor));
        hv_store_sv(aTHX_ hv, "cornerRadius",
                    clay_corner_radius_to_sv(aTHX_ cmd->renderData.custom.cornerRadius));
        hv_store_iv(aTHX_ hv, "customData", PTR2IV(cmd->renderData.custom.customData));
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
    hv_store_iv(aTHX_ hv, "userData",    PTR2IV(cmd->userData));
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
