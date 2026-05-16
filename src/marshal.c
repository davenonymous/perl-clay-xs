/*
 * marshal.c - HV/AV <-> Clay struct converters.
 *
 * Functions named *_from_sv take a Perl SV and return a fully-populated
 * Clay struct (or croak on bad input). Functions named *_to_sv take a
 * Clay struct and return a new mortal Perl value owning fresh memory.
 *
 * The design choices baked into this file:
 *
 *   - Compact types (Color, Vector2, Dimensions, BoundingBox) accept
 *     either an arrayref or a hashref. Fields use exact C names
 *     (backgroundColor, layoutDirection, etc.) so users can read
 *     clay.h verbatim and translate to Perl hash keys.
 *
 *   - Missing fields default to a zero-initialised struct value. Clay's
 *     defaults (left-to-right layout, fit sizing, etc.) are themselves
 *     zero, so a bare {} gives sensible behaviour.
 *
 *   - Fail Fast: an SV that is the wrong reference type (e.g. arrayref
 *     where a hashref was needed for a struct with named fields) croaks
 *     immediately rather than silently producing garbage.
 */

#include "clay_perl.h"

#include <math.h>
#include <string.h>

/* ===========================================================================
 * Internal helpers (file-scope).
 * ======================================================================== */

/* Fetch a hash slot by literal C string. Returns NULL if absent. */
static SV *hv_fetch_pv(pTHX_ HV *hv, const char *key)
{
    if (!hv) return NULL;
    SV **slot = hv_fetch(hv, key, (I32) strlen(key), 0);
    return slot ? *slot : NULL;
}

/* Coerce optional numeric slot, defaulting to zero. */
static double hv_fetch_nv_or(pTHX_ HV *hv, const char *key, double def)
{
    SV *sv = hv_fetch_pv(aTHX_ hv, key);
    return (sv && SvOK(sv)) ? SvNV(sv) : def;
}

static IV hv_fetch_iv_or(pTHX_ HV *hv, const char *key, IV def)
{
    SV *sv = hv_fetch_pv(aTHX_ hv, key);
    return (sv && SvOK(sv)) ? SvIV(sv) : def;
}

static UV hv_fetch_uv_or(pTHX_ HV *hv, const char *key, UV def)
{
    SV *sv = hv_fetch_pv(aTHX_ hv, key);
    return (sv && SvOK(sv)) ? SvUV(sv) : def;
}

static bool hv_fetch_bool(pTHX_ HV *hv, const char *key)
{
    SV *sv = hv_fetch_pv(aTHX_ hv, key);
    return (sv && SvTRUE(sv)) ? true : false;
}

/* Coerce arrayref element at index, defaulting to 0. */
static double av_fetch_nv_or(pTHX_ AV *av, SSize_t idx, double def)
{
    SV **slot = av_fetch(av, idx, 0);
    return (slot && *slot && SvOK(*slot)) ? SvNV(*slot) : def;
}

static void hv_store_pv_iv(pTHX_ HV *hv, const char *key, IV value)
{
    hv_store(hv, key, (I32) strlen(key), newSViv(value), 0);
}

static void hv_store_pv_uv(pTHX_ HV *hv, const char *key, UV value)
{
    hv_store(hv, key, (I32) strlen(key), newSVuv(value), 0);
}

static void hv_store_pv_nv(pTHX_ HV *hv, const char *key, NV value)
{
    hv_store(hv, key, (I32) strlen(key), newSVnv(value), 0);
}

static void hv_store_pv_bool(pTHX_ HV *hv, const char *key, bool value)
{
    hv_store(hv, key, (I32) strlen(key), value ? newSVuv(1) : newSVuv(0), 0);
}

static void hv_store_pv_sv(pTHX_ HV *hv, const char *key, SV *value)
{
    hv_store(hv, key, (I32) strlen(key), value, 0);
}

/* ===========================================================================
 * Clay_Color  - accepts {r,g,b,a} or [r,g,b,a].
 * ======================================================================== */

Clay_Color clay_color_from_sv(pTHX_ SV *sv)
{
    Clay_Color c = { 0, 0, 0, 0 };
    if (!sv || !SvOK(sv)) return c;

    if (!SvROK(sv)) {
        croak("Clay_Color: expected hash or array reference");
    }
    SV *target = SvRV(sv);

    if (SvTYPE(target) == SVt_PVAV) {
        AV *av = (AV *) target;
        c.r = (float) av_fetch_nv_or(aTHX_ av, 0, 0);
        c.g = (float) av_fetch_nv_or(aTHX_ av, 1, 0);
        c.b = (float) av_fetch_nv_or(aTHX_ av, 2, 0);
        c.a = (float) av_fetch_nv_or(aTHX_ av, 3, 0);
    }
    else if (SvTYPE(target) == SVt_PVHV) {
        HV *hv = (HV *) target;
        c.r = (float) hv_fetch_nv_or(aTHX_ hv, "r", 0);
        c.g = (float) hv_fetch_nv_or(aTHX_ hv, "g", 0);
        c.b = (float) hv_fetch_nv_or(aTHX_ hv, "b", 0);
        c.a = (float) hv_fetch_nv_or(aTHX_ hv, "a", 0);
    }
    else {
        croak("Clay_Color: expected hash or array reference");
    }
    return c;
}

SV *clay_color_to_sv(pTHX_ Clay_Color value)
{
    HV *hv = newHV();
    hv_store_pv_nv(aTHX_ hv, "r", value.r);
    hv_store_pv_nv(aTHX_ hv, "g", value.g);
    hv_store_pv_nv(aTHX_ hv, "b", value.b);
    hv_store_pv_nv(aTHX_ hv, "a", value.a);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_Vector2  - {x,y} or [x,y].
 * ======================================================================== */

Clay_Vector2 clay_vector2_from_sv(pTHX_ SV *sv)
{
    Clay_Vector2 v = { 0, 0 };
    if (!sv || !SvOK(sv)) return v;
    if (!SvROK(sv)) croak("Clay_Vector2: expected hash or array reference");
    SV *target = SvRV(sv);

    if (SvTYPE(target) == SVt_PVAV) {
        AV *av = (AV *) target;
        v.x = (float) av_fetch_nv_or(aTHX_ av, 0, 0);
        v.y = (float) av_fetch_nv_or(aTHX_ av, 1, 0);
    }
    else if (SvTYPE(target) == SVt_PVHV) {
        HV *hv = (HV *) target;
        v.x = (float) hv_fetch_nv_or(aTHX_ hv, "x", 0);
        v.y = (float) hv_fetch_nv_or(aTHX_ hv, "y", 0);
    }
    else {
        croak("Clay_Vector2: expected hash or array reference");
    }
    return v;
}

SV *clay_vector2_to_sv(pTHX_ Clay_Vector2 value)
{
    HV *hv = newHV();
    hv_store_pv_nv(aTHX_ hv, "x", value.x);
    hv_store_pv_nv(aTHX_ hv, "y", value.y);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_Dimensions  - {width,height} or [width,height].
 * ======================================================================== */

Clay_Dimensions clay_dimensions_from_sv(pTHX_ SV *sv)
{
    Clay_Dimensions d = { 0, 0 };
    if (!sv || !SvOK(sv)) return d;
    if (!SvROK(sv)) croak("Clay_Dimensions: expected hash or array reference");
    SV *target = SvRV(sv);

    if (SvTYPE(target) == SVt_PVAV) {
        AV *av = (AV *) target;
        d.width  = (float) av_fetch_nv_or(aTHX_ av, 0, 0);
        d.height = (float) av_fetch_nv_or(aTHX_ av, 1, 0);
    }
    else if (SvTYPE(target) == SVt_PVHV) {
        HV *hv = (HV *) target;
        d.width  = (float) hv_fetch_nv_or(aTHX_ hv, "width", 0);
        d.height = (float) hv_fetch_nv_or(aTHX_ hv, "height", 0);
    }
    else {
        croak("Clay_Dimensions: expected hash or array reference");
    }
    return d;
}

SV *clay_dimensions_to_sv(pTHX_ Clay_Dimensions value)
{
    HV *hv = newHV();
    hv_store_pv_nv(aTHX_ hv, "width",  value.width);
    hv_store_pv_nv(aTHX_ hv, "height", value.height);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_BoundingBox  - {x,y,width,height}.
 * ======================================================================== */

Clay_BoundingBox clay_bounding_box_from_sv(pTHX_ SV *sv)
{
    Clay_BoundingBox bb = { 0, 0, 0, 0 };
    if (!sv || !SvOK(sv)) return bb;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_BoundingBox: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    bb.x      = (float) hv_fetch_nv_or(aTHX_ hv, "x", 0);
    bb.y      = (float) hv_fetch_nv_or(aTHX_ hv, "y", 0);
    bb.width  = (float) hv_fetch_nv_or(aTHX_ hv, "width", 0);
    bb.height = (float) hv_fetch_nv_or(aTHX_ hv, "height", 0);
    return bb;
}

SV *clay_bounding_box_to_sv(pTHX_ Clay_BoundingBox value)
{
    HV *hv = newHV();
    hv_store_pv_nv(aTHX_ hv, "x",      value.x);
    hv_store_pv_nv(aTHX_ hv, "y",      value.y);
    hv_store_pv_nv(aTHX_ hv, "width",  value.width);
    hv_store_pv_nv(aTHX_ hv, "height", value.height);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_CornerRadius - {topLeft,topRight,bottomLeft,bottomRight}.
 * Also accepts a scalar (applied to all four corners) for ergonomics, since
 * the C CLAY_CORNER_RADIUS(r) macro does the same thing.
 * ======================================================================== */

Clay_CornerRadius clay_corner_radius_from_sv(pTHX_ SV *sv)
{
    Clay_CornerRadius r = { 0, 0, 0, 0 };
    if (!sv || !SvOK(sv)) return r;

    if (!SvROK(sv)) {
        float n = (float) SvNV(sv);
        r.topLeft = r.topRight = r.bottomLeft = r.bottomRight = n;
        return r;
    }
    if (SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_CornerRadius: expected number or hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    r.topLeft     = (float) hv_fetch_nv_or(aTHX_ hv, "topLeft", 0);
    r.topRight    = (float) hv_fetch_nv_or(aTHX_ hv, "topRight", 0);
    r.bottomLeft  = (float) hv_fetch_nv_or(aTHX_ hv, "bottomLeft", 0);
    r.bottomRight = (float) hv_fetch_nv_or(aTHX_ hv, "bottomRight", 0);
    return r;
}

SV *clay_corner_radius_to_sv(pTHX_ Clay_CornerRadius value)
{
    HV *hv = newHV();
    hv_store_pv_nv(aTHX_ hv, "topLeft",     value.topLeft);
    hv_store_pv_nv(aTHX_ hv, "topRight",    value.topRight);
    hv_store_pv_nv(aTHX_ hv, "bottomLeft",  value.bottomLeft);
    hv_store_pv_nv(aTHX_ hv, "bottomRight", value.bottomRight);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_Padding - {left,right,top,bottom}.
 * ======================================================================== */

Clay_Padding clay_padding_from_sv(pTHX_ SV *sv)
{
    Clay_Padding p = { 0, 0, 0, 0 };
    if (!sv || !SvOK(sv)) return p;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_Padding: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    p.left   = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "left", 0);
    p.right  = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "right", 0);
    p.top    = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "top", 0);
    p.bottom = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "bottom", 0);
    return p;
}

SV *clay_padding_to_sv(pTHX_ Clay_Padding value)
{
    HV *hv = newHV();
    hv_store_pv_uv(aTHX_ hv, "left",   value.left);
    hv_store_pv_uv(aTHX_ hv, "right",  value.right);
    hv_store_pv_uv(aTHX_ hv, "top",    value.top);
    hv_store_pv_uv(aTHX_ hv, "bottom", value.bottom);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_BorderWidth - {left,right,top,bottom,betweenChildren}.
 * ======================================================================== */

Clay_BorderWidth clay_border_width_from_sv(pTHX_ SV *sv)
{
    Clay_BorderWidth w = { 0, 0, 0, 0, 0 };
    if (!sv || !SvOK(sv)) return w;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_BorderWidth: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    w.left            = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "left", 0);
    w.right           = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "right", 0);
    w.top             = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "top", 0);
    w.bottom          = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "bottom", 0);
    w.betweenChildren = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "betweenChildren", 0);
    return w;
}

SV *clay_border_width_to_sv(pTHX_ Clay_BorderWidth value)
{
    HV *hv = newHV();
    hv_store_pv_uv(aTHX_ hv, "left",            value.left);
    hv_store_pv_uv(aTHX_ hv, "right",           value.right);
    hv_store_pv_uv(aTHX_ hv, "top",             value.top);
    hv_store_pv_uv(aTHX_ hv, "bottom",          value.bottom);
    hv_store_pv_uv(aTHX_ hv, "betweenChildren", value.betweenChildren);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_ChildAlignment - {x,y} (enum values).
 * ======================================================================== */

Clay_ChildAlignment clay_child_alignment_from_sv(pTHX_ SV *sv)
{
    Clay_ChildAlignment a;
    a.x = CLAY_ALIGN_X_LEFT;
    a.y = CLAY_ALIGN_Y_TOP;
    if (!sv || !SvOK(sv)) return a;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_ChildAlignment: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    a.x = (Clay_LayoutAlignmentX) hv_fetch_iv_or(aTHX_ hv, "x", CLAY_ALIGN_X_LEFT);
    a.y = (Clay_LayoutAlignmentY) hv_fetch_iv_or(aTHX_ hv, "y", CLAY_ALIGN_Y_TOP);
    return a;
}

SV *clay_child_alignment_to_sv(pTHX_ Clay_ChildAlignment value)
{
    HV *hv = newHV();
    hv_store_pv_iv(aTHX_ hv, "x", (IV) value.x);
    hv_store_pv_iv(aTHX_ hv, "y", (IV) value.y);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_SizingAxis - { type, min, max } for fit/grow/fixed (union member
 * minMax) or { type, percent } for percent. The XS sizing_*() helpers
 * produce these hashes; users can also build them directly.
 * ======================================================================== */

Clay_SizingAxis clay_sizing_axis_from_sv(pTHX_ SV *sv)
{
    Clay_SizingAxis axis = { 0 };
    axis.type = CLAY__SIZING_TYPE_FIT;

    if (!sv || !SvOK(sv)) return axis;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_SizingAxis: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    axis.type = (Clay__SizingType) hv_fetch_iv_or(aTHX_ hv, "type",
                                                  CLAY__SIZING_TYPE_FIT);

    if (axis.type == CLAY__SIZING_TYPE_PERCENT) {
        axis.size.percent = (float) hv_fetch_nv_or(aTHX_ hv, "percent", 0);
    } else {
        axis.size.minMax.min = (float) hv_fetch_nv_or(aTHX_ hv, "min", 0);
        axis.size.minMax.max = (float) hv_fetch_nv_or(aTHX_ hv, "max", 0);
    }
    return axis;
}

SV *clay_sizing_axis_to_sv(pTHX_ Clay_SizingAxis value)
{
    HV *hv = newHV();
    hv_store_pv_iv(aTHX_ hv, "type", (IV) value.type);
    if (value.type == CLAY__SIZING_TYPE_PERCENT) {
        hv_store_pv_nv(aTHX_ hv, "percent", value.size.percent);
    } else {
        hv_store_pv_nv(aTHX_ hv, "min", value.size.minMax.min);
        hv_store_pv_nv(aTHX_ hv, "max", value.size.minMax.max);
    }
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_Sizing - { width => SizingAxis, height => SizingAxis }.
 * ======================================================================== */

Clay_Sizing clay_sizing_from_sv(pTHX_ SV *sv)
{
    Clay_Sizing s = { 0 };
    s.width.type  = CLAY__SIZING_TYPE_FIT;
    s.height.type = CLAY__SIZING_TYPE_FIT;

    if (!sv || !SvOK(sv)) return s;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_Sizing: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    SV *width  = hv_fetch_pv(aTHX_ hv, "width");
    SV *height = hv_fetch_pv(aTHX_ hv, "height");
    if (width)  s.width  = clay_sizing_axis_from_sv(aTHX_ width);
    if (height) s.height = clay_sizing_axis_from_sv(aTHX_ height);
    return s;
}

SV *clay_sizing_to_sv(pTHX_ Clay_Sizing value)
{
    HV *hv = newHV();
    hv_store_pv_sv(aTHX_ hv, "width",  clay_sizing_axis_to_sv(aTHX_ value.width));
    hv_store_pv_sv(aTHX_ hv, "height", clay_sizing_axis_to_sv(aTHX_ value.height));
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_LayoutConfig.
 * ======================================================================== */

Clay_LayoutConfig clay_layout_config_from_sv(pTHX_ SV *sv)
{
    Clay_LayoutConfig cfg;
    memset(&cfg, 0, sizeof(cfg));

    if (!sv || !SvOK(sv)) return cfg;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_LayoutConfig: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);

    SV *sizing  = hv_fetch_pv(aTHX_ hv, "sizing");
    SV *padding = hv_fetch_pv(aTHX_ hv, "padding");
    SV *align   = hv_fetch_pv(aTHX_ hv, "childAlignment");

    if (sizing)  cfg.sizing         = clay_sizing_from_sv(aTHX_ sizing);
    if (padding) cfg.padding        = clay_padding_from_sv(aTHX_ padding);
    if (align)   cfg.childAlignment = clay_child_alignment_from_sv(aTHX_ align);

    cfg.childGap        = (uint16_t)        hv_fetch_uv_or(aTHX_ hv, "childGap", 0);
    cfg.layoutDirection = (Clay_LayoutDirection)
                          hv_fetch_iv_or(aTHX_ hv, "layoutDirection",
                                         CLAY_LEFT_TO_RIGHT);
    return cfg;
}

SV *clay_layout_config_to_sv(pTHX_ Clay_LayoutConfig value)
{
    HV *hv = newHV();
    hv_store_pv_sv(aTHX_ hv, "sizing",          clay_sizing_to_sv(aTHX_ value.sizing));
    hv_store_pv_sv(aTHX_ hv, "padding",         clay_padding_to_sv(aTHX_ value.padding));
    hv_store_pv_sv(aTHX_ hv, "childAlignment",  clay_child_alignment_to_sv(aTHX_ value.childAlignment));
    hv_store_pv_uv(aTHX_ hv, "childGap",        value.childGap);
    hv_store_pv_iv(aTHX_ hv, "layoutDirection", (IV) value.layoutDirection);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_TextElementConfig.
 *
 * userData is held as an opaque IV (no SV refcount is taken). The XS layer
 * is responsible for converting it back to a Perl value when the user
 * inspects a render command.
 * ======================================================================== */

Clay_TextElementConfig clay_text_element_config_from_sv(pTHX_ SV *sv)
{
    Clay_TextElementConfig cfg;
    memset(&cfg, 0, sizeof(cfg));

    if (!sv || !SvOK(sv)) return cfg;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_TextElementConfig: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);

    cfg.textColor     = clay_color_from_sv(aTHX_ hv_fetch_pv(aTHX_ hv, "textColor"));
    cfg.fontId        = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "fontId", 0);
    cfg.fontSize      = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "fontSize", 0);
    cfg.letterSpacing = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "letterSpacing", 0);
    cfg.lineHeight    = (uint16_t) hv_fetch_uv_or(aTHX_ hv, "lineHeight", 0);
    cfg.wrapMode      = (Clay_TextElementConfigWrapMode)
                        hv_fetch_iv_or(aTHX_ hv, "wrapMode", CLAY_TEXT_WRAP_WORDS);
    cfg.textAlignment = (Clay_TextAlignment)
                        hv_fetch_iv_or(aTHX_ hv, "textAlignment", CLAY_TEXT_ALIGN_LEFT);

    SV *userdata = hv_fetch_pv(aTHX_ hv, "userData");
    cfg.userData = (userdata && SvOK(userdata))
                   ? INT2PTR(void *, SvIV(userdata)) : NULL;

    return cfg;
}

SV *clay_text_element_config_to_sv(pTHX_ Clay_TextElementConfig value)
{
    HV *hv = newHV();
    hv_store_pv_sv(aTHX_ hv, "textColor",     clay_color_to_sv(aTHX_ value.textColor));
    hv_store_pv_uv(aTHX_ hv, "fontId",        value.fontId);
    hv_store_pv_uv(aTHX_ hv, "fontSize",      value.fontSize);
    hv_store_pv_uv(aTHX_ hv, "letterSpacing", value.letterSpacing);
    hv_store_pv_uv(aTHX_ hv, "lineHeight",    value.lineHeight);
    hv_store_pv_iv(aTHX_ hv, "wrapMode",      (IV) value.wrapMode);
    hv_store_pv_iv(aTHX_ hv, "textAlignment", (IV) value.textAlignment);
    hv_store_pv_iv(aTHX_ hv, "userData",      PTR2IV(value.userData));
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Sub-configs that compose Clay_ElementDeclaration.
 * ======================================================================== */

Clay_AspectRatioElementConfig clay_aspect_ratio_config_from_sv(pTHX_ SV *sv)
{
    Clay_AspectRatioElementConfig c = { 0 };
    if (!sv || !SvOK(sv)) return c;
    if (!SvROK(sv)) {
        c.aspectRatio = (float) SvNV(sv);
        return c;
    }
    if (SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_AspectRatioElementConfig: expected number or hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    c.aspectRatio = (float) hv_fetch_nv_or(aTHX_ hv, "aspectRatio", 0);
    return c;
}

Clay_ImageElementConfig clay_image_config_from_sv(pTHX_ SV *sv)
{
    Clay_ImageElementConfig c = { 0 };
    if (!sv || !SvOK(sv)) return c;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_ImageElementConfig: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    SV *data = hv_fetch_pv(aTHX_ hv, "imageData");
    c.imageData = (data && SvOK(data)) ? INT2PTR(void *, SvIV(data)) : NULL;
    return c;
}

Clay_CustomElementConfig clay_custom_config_from_sv(pTHX_ SV *sv)
{
    Clay_CustomElementConfig c = { 0 };
    if (!sv || !SvOK(sv)) return c;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_CustomElementConfig: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    SV *data = hv_fetch_pv(aTHX_ hv, "customData");
    c.customData = (data && SvOK(data)) ? INT2PTR(void *, SvIV(data)) : NULL;
    return c;
}

Clay_ClipElementConfig clay_clip_config_from_sv(pTHX_ SV *sv)
{
    Clay_ClipElementConfig c = { false, false, { 0, 0 } };
    if (!sv || !SvOK(sv)) return c;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_ClipElementConfig: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    c.horizontal  = hv_fetch_bool(aTHX_ hv, "horizontal");
    c.vertical    = hv_fetch_bool(aTHX_ hv, "vertical");
    c.childOffset = clay_vector2_from_sv(aTHX_ hv_fetch_pv(aTHX_ hv, "childOffset"));
    return c;
}

Clay_BorderElementConfig clay_border_config_from_sv(pTHX_ SV *sv)
{
    Clay_BorderElementConfig c;
    memset(&c, 0, sizeof(c));
    if (!sv || !SvOK(sv)) return c;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_BorderElementConfig: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    c.color = clay_color_from_sv(aTHX_ hv_fetch_pv(aTHX_ hv, "color"));
    c.width = clay_border_width_from_sv(aTHX_ hv_fetch_pv(aTHX_ hv, "width"));
    return c;
}

Clay_FloatingElementConfig clay_floating_config_from_sv(pTHX_ SV *sv)
{
    Clay_FloatingElementConfig c;
    memset(&c, 0, sizeof(c));
    if (!sv || !SvOK(sv)) return c;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_FloatingElementConfig: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);

    c.offset   = clay_vector2_from_sv(aTHX_ hv_fetch_pv(aTHX_ hv, "offset"));
    c.expand   = clay_dimensions_from_sv(aTHX_ hv_fetch_pv(aTHX_ hv, "expand"));
    c.parentId = (uint32_t) hv_fetch_uv_or(aTHX_ hv, "parentId", 0);
    c.zIndex   = (int16_t)  hv_fetch_iv_or(aTHX_ hv, "zIndex", 0);

    SV *attach = hv_fetch_pv(aTHX_ hv, "attachPoints");
    if (attach && SvROK(attach) && SvTYPE(SvRV(attach)) == SVt_PVHV) {
        HV *ah = (HV *) SvRV(attach);
        c.attachPoints.element = (Clay_FloatingAttachPointType)
            hv_fetch_iv_or(aTHX_ ah, "element", CLAY_ATTACH_POINT_LEFT_TOP);
        c.attachPoints.parent  = (Clay_FloatingAttachPointType)
            hv_fetch_iv_or(aTHX_ ah, "parent", CLAY_ATTACH_POINT_LEFT_TOP);
    }
    c.pointerCaptureMode = (Clay_PointerCaptureMode)
        hv_fetch_iv_or(aTHX_ hv, "pointerCaptureMode",
                       CLAY_POINTER_CAPTURE_MODE_CAPTURE);
    c.attachTo = (Clay_FloatingAttachToElement)
        hv_fetch_iv_or(aTHX_ hv, "attachTo", CLAY_ATTACH_TO_NONE);
    c.clipTo = (Clay_FloatingClipToElement)
        hv_fetch_iv_or(aTHX_ hv, "clipTo", CLAY_CLIP_TO_NONE);
    return c;
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
 * The `hasSetInitial` / `hasSetFinal` booleans tell us whether to install
 * our trampolines for those slots. The handler is always installed (Clay
 * requires one to actually run the transition).
 *
 * Per-element Perl coderefs are not supported in Phase 1; see the note in
 * clay_perl.h. Use clay_perl_set_transition_handler() to install the
 * single set of Perl coderefs that handle every element's transition.
 * ======================================================================== */

static Clay_TransitionElementConfig clay_transition_config_from_sv(pTHX_ clay_perl_context *ctx, SV *sv)
{
    Clay_TransitionElementConfig c;
    memset(&c, 0, sizeof(c));

    if (!sv || !SvOK(sv)) return c;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_TransitionElementConfig: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);

    c.duration   = (float) hv_fetch_nv_or(aTHX_ hv, "duration", 0);
    c.properties = (Clay_TransitionProperty) hv_fetch_uv_or(aTHX_ hv, "properties", 0);
    c.interactionHandling = (Clay_TransitionInteractionHandlingType)
        hv_fetch_iv_or(aTHX_ hv, "interactionHandling",
                       CLAY_TRANSITION_DISABLE_INTERACTIONS_WHILE_TRANSITIONING_POSITION);

    /* Always install our handler trampoline when a transition is configured.
     * Clay needs a non-NULL handler to drive the transition; ours will be a
     * no-op (returning "complete") if no Perl handler is registered on the
     * context. */
    c.handler = clay_perl_transition_handler_trampoline;

    SV *enter_sv = hv_fetch_pv(aTHX_ hv, "enter");
    if (enter_sv && SvROK(enter_sv) && SvTYPE(SvRV(enter_sv)) == SVt_PVHV) {
        HV *enter_hv = (HV *) SvRV(enter_sv);
        c.enter.trigger = (Clay_TransitionEnterTriggerType)
            hv_fetch_iv_or(aTHX_ enter_hv, "trigger",
                           CLAY_TRANSITION_ENTER_SKIP_ON_FIRST_PARENT_FRAME);
        if (hv_fetch_bool(aTHX_ enter_hv, "hasSetInitial")) {
            c.enter.setInitialState = clay_perl_transition_set_initial_trampoline;
        }
    }

    SV *exit_sv = hv_fetch_pv(aTHX_ hv, "exit");
    if (exit_sv && SvROK(exit_sv) && SvTYPE(SvRV(exit_sv)) == SVt_PVHV) {
        HV *exit_hv = (HV *) SvRV(exit_sv);
        c.exit.trigger = (Clay_TransitionExitTriggerType)
            hv_fetch_iv_or(aTHX_ exit_hv, "trigger",
                           CLAY_TRANSITION_EXIT_SKIP_WHEN_PARENT_EXITS);
        c.exit.siblingOrdering = (Clay_ExitTransitionSiblingOrdering)
            hv_fetch_iv_or(aTHX_ exit_hv, "siblingOrdering",
                           CLAY_EXIT_TRANSITION_ORDERING_NATURAL_ORDER);
        if (hv_fetch_bool(aTHX_ exit_hv, "hasSetFinal")) {
            c.exit.setFinalState = clay_perl_transition_set_final_trampoline;
        }
    }

    (void) ctx;
    return c;
}

/* ===========================================================================
 * Clay_SizingGroup. {width => N, height => M}; either may be omitted.
 * ======================================================================== */

static Clay_SizingGroup clay_sizing_group_from_sv(pTHX_ SV *sv)
{
    Clay_SizingGroup g;
    memset(&g, 0, sizeof(g));
    if (!sv || !SvOK(sv)) return g;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_SizingGroup: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    g.width  = (uint32_t) hv_fetch_uv_or(aTHX_ hv, "width",  0);
    g.height = (uint32_t) hv_fetch_uv_or(aTHX_ hv, "height", 0);
    return g;
}

/* ===========================================================================
 * Clay_ElementDeclaration - the big one. Composes every sub-config above
 * plus the transition config.
 * ======================================================================== */

Clay_ElementDeclaration clay_element_declaration_from_sv(pTHX_ clay_perl_context *ctx, SV *sv)
{
    (void) ctx; /* unused for now; reserved for transition cookie threading */

    Clay_ElementDeclaration d;
    memset(&d, 0, sizeof(d));

    if (!sv || !SvOK(sv)) return d;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_ElementDeclaration: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);

    SV *layout      = hv_fetch_pv(aTHX_ hv, "layout");
    SV *bg          = hv_fetch_pv(aTHX_ hv, "backgroundColor");
    SV *overlay     = hv_fetch_pv(aTHX_ hv, "overlayColor");
    SV *corner      = hv_fetch_pv(aTHX_ hv, "cornerRadius");
    SV *aspect      = hv_fetch_pv(aTHX_ hv, "aspectRatio");
    SV *image       = hv_fetch_pv(aTHX_ hv, "image");
    SV *floating    = hv_fetch_pv(aTHX_ hv, "floating");
    SV *custom      = hv_fetch_pv(aTHX_ hv, "custom");
    SV *clip        = hv_fetch_pv(aTHX_ hv, "clip");
    SV *border      = hv_fetch_pv(aTHX_ hv, "border");
    SV *transition  = hv_fetch_pv(aTHX_ hv, "transition");
    SV *sizinggroup = hv_fetch_pv(aTHX_ hv, "sizingGroup");
    SV *userdata    = hv_fetch_pv(aTHX_ hv, "userData");

    if (layout)      d.layout          = clay_layout_config_from_sv(aTHX_ layout);
    if (bg)          d.backgroundColor = clay_color_from_sv(aTHX_ bg);
    if (overlay)     d.overlayColor    = clay_color_from_sv(aTHX_ overlay);
    if (corner)      d.cornerRadius    = clay_corner_radius_from_sv(aTHX_ corner);
    if (aspect)      d.aspectRatio     = clay_aspect_ratio_config_from_sv(aTHX_ aspect);
    if (image)       d.image           = clay_image_config_from_sv(aTHX_ image);
    if (floating)    d.floating        = clay_floating_config_from_sv(aTHX_ floating);
    if (custom)      d.custom          = clay_custom_config_from_sv(aTHX_ custom);
    if (clip)        d.clip            = clay_clip_config_from_sv(aTHX_ clip);
    if (border)      d.border          = clay_border_config_from_sv(aTHX_ border);
    if (transition)  d.transition      = clay_transition_config_from_sv(aTHX_ ctx, transition);
    if (sizinggroup) d.sizingGroup     = clay_sizing_group_from_sv(aTHX_ sizinggroup);

    if (userdata && SvOK(userdata)) {
        d.userData = INT2PTR(void *, SvIV(userdata));
    }
    return d;
}

/* ===========================================================================
 * Clay_ElementId.
 * ======================================================================== */

Clay_ElementId clay_element_id_from_sv(pTHX_ SV *sv)
{
    Clay_ElementId id;
    memset(&id, 0, sizeof(id));
    if (!sv || !SvOK(sv)) return id;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_ElementId: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    id.id     = (uint32_t) hv_fetch_uv_or(aTHX_ hv, "id", 0);
    id.offset = (uint32_t) hv_fetch_uv_or(aTHX_ hv, "offset", 0);
    id.baseId = (uint32_t) hv_fetch_uv_or(aTHX_ hv, "baseId", 0);

    /* stringId is informational; we don't round-trip the chars back through
     * the per-frame arena here because reconstructing the original Clay
     * context is not available. The id/offset/baseId triple is enough. */
    return id;
}

SV *clay_element_id_to_sv(pTHX_ Clay_ElementId id)
{
    HV *hv = newHV();
    hv_store_pv_uv(aTHX_ hv, "id",     id.id);
    hv_store_pv_uv(aTHX_ hv, "offset", id.offset);
    hv_store_pv_uv(aTHX_ hv, "baseId", id.baseId);
    if (id.stringId.chars && id.stringId.length > 0) {
        SV *s = newSVpvn(id.stringId.chars, (STRLEN) id.stringId.length);
        hv_store_pv_sv(aTHX_ hv, "stringId", s);
    }
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_PointerData.
 * ======================================================================== */

Clay_PointerData clay_pointer_data_from_sv(pTHX_ SV *sv)
{
    Clay_PointerData p;
    memset(&p, 0, sizeof(p));
    if (!sv || !SvOK(sv)) return p;
    if (!SvROK(sv) || SvTYPE(SvRV(sv)) != SVt_PVHV) {
        croak("Clay_PointerData: expected hash reference");
    }
    HV *hv = (HV *) SvRV(sv);
    p.position = clay_vector2_from_sv(aTHX_ hv_fetch_pv(aTHX_ hv, "position"));
    p.state    = (Clay_PointerDataInteractionState)
                 hv_fetch_iv_or(aTHX_ hv, "state", CLAY_POINTER_DATA_RELEASED);
    return p;
}

SV *clay_pointer_data_to_sv(pTHX_ Clay_PointerData data)
{
    HV *hv = newHV();
    hv_store_pv_sv(aTHX_ hv, "position", clay_vector2_to_sv(aTHX_ data.position));
    hv_store_pv_iv(aTHX_ hv, "state",    (IV) data.state);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_ElementData and Clay_ScrollContainerData (return-only).
 * ======================================================================== */

SV *clay_element_data_to_sv(pTHX_ Clay_ElementData data)
{
    HV *hv = newHV();
    hv_store_pv_sv(aTHX_ hv, "boundingBox", clay_bounding_box_to_sv(aTHX_ data.boundingBox));
    hv_store_pv_bool(aTHX_ hv, "found", data.found);
    return newRV_noinc((SV *) hv);
}

SV *clay_scroll_container_data_to_sv(pTHX_ Clay_ScrollContainerData data)
{
    HV *hv = newHV();
    if (data.scrollPosition) {
        hv_store_pv_sv(aTHX_ hv, "scrollPosition",
                       clay_vector2_to_sv(aTHX_ *data.scrollPosition));
    } else {
        Clay_Vector2 zero = { 0, 0 };
        hv_store_pv_sv(aTHX_ hv, "scrollPosition",
                       clay_vector2_to_sv(aTHX_ zero));
    }
    hv_store_pv_sv(aTHX_ hv, "scrollContainerDimensions",
                   clay_dimensions_to_sv(aTHX_ data.scrollContainerDimensions));
    hv_store_pv_sv(aTHX_ hv, "contentDimensions",
                   clay_dimensions_to_sv(aTHX_ data.contentDimensions));

    HV *config_hv = newHV();
    hv_store_pv_bool(aTHX_ config_hv, "horizontal", data.config.horizontal);
    hv_store_pv_bool(aTHX_ config_hv, "vertical",   data.config.vertical);
    hv_store_pv_sv  (aTHX_ config_hv, "childOffset",
                     clay_vector2_to_sv(aTHX_ data.config.childOffset));
    hv_store_pv_sv(aTHX_ hv, "config", newRV_noinc((SV *) config_hv));

    hv_store_pv_bool(aTHX_ hv, "found", data.found);
    return newRV_noinc((SV *) hv);
}

/* ===========================================================================
 * Clay_StringSlice -> Perl string (copy).
 * ======================================================================== */

SV *clay_string_slice_to_sv(pTHX_ Clay_StringSlice slice)
{
    if (slice.chars && slice.length > 0) {
        return newSVpvn(slice.chars, (STRLEN) slice.length);
    }
    return newSVpvs("");
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
 *   userData    : opaque IV or undef
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
        hv_store_pv_sv(aTHX_ hv, "backgroundColor",
                       clay_color_to_sv(aTHX_ cmd->renderData.rectangle.backgroundColor));
        hv_store_pv_sv(aTHX_ hv, "cornerRadius",
                       clay_corner_radius_to_sv(aTHX_ cmd->renderData.rectangle.cornerRadius));
        break;

    case CLAY_RENDER_COMMAND_TYPE_TEXT:
        hv_store_pv_sv(aTHX_ hv, "stringContents",
                       clay_string_slice_to_sv(aTHX_ cmd->renderData.text.stringContents));
        hv_store_pv_sv(aTHX_ hv, "textColor",
                       clay_color_to_sv(aTHX_ cmd->renderData.text.textColor));
        hv_store_pv_uv(aTHX_ hv, "fontId",        cmd->renderData.text.fontId);
        hv_store_pv_uv(aTHX_ hv, "fontSize",      cmd->renderData.text.fontSize);
        hv_store_pv_uv(aTHX_ hv, "letterSpacing", cmd->renderData.text.letterSpacing);
        hv_store_pv_uv(aTHX_ hv, "lineHeight",    cmd->renderData.text.lineHeight);
        break;

    case CLAY_RENDER_COMMAND_TYPE_IMAGE:
        hv_store_pv_sv(aTHX_ hv, "backgroundColor",
                       clay_color_to_sv(aTHX_ cmd->renderData.image.backgroundColor));
        hv_store_pv_sv(aTHX_ hv, "cornerRadius",
                       clay_corner_radius_to_sv(aTHX_ cmd->renderData.image.cornerRadius));
        hv_store_pv_iv(aTHX_ hv, "imageData",
                       PTR2IV(cmd->renderData.image.imageData));
        break;

    case CLAY_RENDER_COMMAND_TYPE_CUSTOM:
        hv_store_pv_sv(aTHX_ hv, "backgroundColor",
                       clay_color_to_sv(aTHX_ cmd->renderData.custom.backgroundColor));
        hv_store_pv_sv(aTHX_ hv, "cornerRadius",
                       clay_corner_radius_to_sv(aTHX_ cmd->renderData.custom.cornerRadius));
        hv_store_pv_iv(aTHX_ hv, "customData",
                       PTR2IV(cmd->renderData.custom.customData));
        break;

    case CLAY_RENDER_COMMAND_TYPE_BORDER:
        hv_store_pv_sv(aTHX_ hv, "color",
                       clay_color_to_sv(aTHX_ cmd->renderData.border.color));
        hv_store_pv_sv(aTHX_ hv, "cornerRadius",
                       clay_corner_radius_to_sv(aTHX_ cmd->renderData.border.cornerRadius));
        hv_store_pv_sv(aTHX_ hv, "width",
                       clay_border_width_to_sv(aTHX_ cmd->renderData.border.width));
        break;

    case CLAY_RENDER_COMMAND_TYPE_SCISSOR_START:
    case CLAY_RENDER_COMMAND_TYPE_SCISSOR_END:
        hv_store_pv_bool(aTHX_ hv, "horizontal", cmd->renderData.clip.horizontal);
        hv_store_pv_bool(aTHX_ hv, "vertical",   cmd->renderData.clip.vertical);
        break;

    case CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_START:
    case CLAY_RENDER_COMMAND_TYPE_OVERLAY_COLOR_END:
        hv_store_pv_sv(aTHX_ hv, "color",
                       clay_color_to_sv(aTHX_ cmd->renderData.overlayColor.color));
        break;

    case CLAY_RENDER_COMMAND_TYPE_NONE:
    default:
        /* No payload. */
        break;
    }
    return newRV_noinc((SV *) hv);
}

SV *clay_render_command_to_sv(pTHX_ const Clay_RenderCommand *cmd)
{
    HV *hv = newHV();
    hv_store_pv_sv  (aTHX_ hv, "boundingBox", clay_bounding_box_to_sv(aTHX_ cmd->boundingBox));
    hv_store_pv_sv  (aTHX_ hv, "renderData",  clay_render_data_to_sv(aTHX_ cmd));
    hv_store_pv_iv  (aTHX_ hv, "userData",    PTR2IV(cmd->userData));
    hv_store_pv_uv  (aTHX_ hv, "id",          cmd->id);
    hv_store_pv_iv  (aTHX_ hv, "zIndex",      (IV) cmd->zIndex);
    hv_store_pv_iv  (aTHX_ hv, "commandType", (IV) cmd->commandType);
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
