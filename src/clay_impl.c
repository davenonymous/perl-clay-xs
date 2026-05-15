/*
 * clay_impl.c - The one and only compilation unit that materialises the
 * Clay v0.14 implementation.
 *
 * Clay is a header-only library. The convention requires exactly one .c
 * file in the project to define CLAY_IMPLEMENTATION before including
 * clay.h; every other file includes clay.h normally and gets only the
 * declarations. This file does the former and nothing else.
 *
 * See src/clay/clay.h:1-11 for the upstream comment that enforces this.
 *
 * The diagnostic suppression below silences three categories of warning
 * that Clay v0.14 emits under -Wall -Wextra. They are upstream issues
 * (unused locals, sign mismatch in a comparison) and are not bugs in
 * the binding. Suppressing them here keeps Clay::Layout's own diagnostic
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
