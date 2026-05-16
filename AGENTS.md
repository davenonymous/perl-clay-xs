# AGENTS.md

XS bindings for the Clay v0.14 C UI layout library. Single distribution,
header-only C dependency, no system libraries.

## Build and test

```
perl Makefile.PL && make && make test
```

Useful invocations:

| Need                                    | Command                                                               |
|-----------------------------------------|-----------------------------------------------------------------------|
| Single test                             | `prove -lvb t/04-elements.t`                                          |
| Regenerate golden fixtures              | `CLAY_LAYOUT_UPDATE_FIXTURES=1 prove -lb t/99-golden.t`               |
| Disable SIMD probe (exotic platforms)   | `PERL_CLAY_DISABLE_SIMD=1 perl Makefile.PL`                            |
| Run an example                          | `perl -Ilib -Iblib/lib -Iblib/arch examples/01-minimal.pl`            |

`prove` requires `-lb` because the loadable XS object lives under `blib/arch/`.

## Source layout

- `Layout.xs`, `src/*.c`, `src/clay_perl.h` - the binding.
- `src/clay/clay.h` - the **vendored** Clay v0.14 header used by the build.
- `references/clay/` - the upstream repo kept for reference only. Not in the
  build path. Do not edit; do not assume edits there propagate.
- `t/fixtures/*.pl` + matching `.json` - golden-output harness used by
  `t/99-golden.t`. Each `.pl` returns a coderef that builds a layout and
  returns the render-command arrayref.

## Build invariants that look weird but are deliberate

1. **`Makefile.PL` has a `postamble` adding `src/%.o : src/%.c`.** EUMM's
   default `.c.o` suffix rule omits `-o $@`, so gcc dumps subdirectory
   objects into the CWD and the link step fails. Removing the postamble
   breaks the build.
2. **`typemap` maps `uint8_t` ... `int64_t`.** Without it `xsubpp` fails
   with "Could not find a typemap for C type 'uint32_t'".
3. **`#define CLAY_IMPLEMENTATION` lives in exactly one file:
   `src/clay_impl.c`.** Every other `.c` (and `Layout.xs`) includes
   `clay/clay.h` without the define. Bumping Clay requires preserving
   this pattern.
4. **`src/clay_impl.c` brackets its include in `#pragma GCC diagnostic
   ignored` lines.** Upstream Clay v0.14 emits `-Wunused-variable`,
   `-Wunused-function`, and `-Wsign-compare` under `-Wall -Wextra`. The
   suppression must travel with any clay.h bump.
5. **`PERL_NO_GET_CONTEXT` is intentionally NOT defined.** `src/clay_perl.h`
   documents why. Adding it forces explicit `aTHX` threading through every
   helper and was tried in early development; do not re-add without a
   wholesale conversion.

## Runtime invariants and Clay-API traps

1. **`xs_ctx_DESTROY` calls `Clay_SetCurrentContext(NULL)` before freeing
   the arena.** Clay's `Clay_Initialize` reads `oldContext->maxElementCount`
   (clay.h v0.14 line 4192). Without the reset, the next `Clay_Initialize`
   dereferences freed memory. If you see SIGSEGV on the second
   `Clay_Initialize`, this is the cause.
2. **`Clay_SetPointerState` walks the previous frame's layout tree to
   populate `pointerOverIds`.** Pointer-over assertions need at least one
   prior `EndLayout`. See `t/06-pointer.t` for the two-frame pattern.
3. **Wheel-based scrolling only applies when the pointer is over the
   scroll container.** `Clay_UpdateScrollContainers` picks the highest
   priority element from `pointerOverIds`. See `t/07-scroll.t`.
4. **Per-element transition callbacks are NOT supported.** Clay's transition
   callback signatures lack an element id. Use `Clay_SetTransitionHandlers`
   to install one handler set per context; the handler must dispatch on
   the arguments if it needs to distinguish elements. See `src/clay_perl.h`
   for the design note.
5. **Strings passed to Clay are copied into a per-frame arena that resets
   at `Clay_BeginLayout`.** `isStaticallyAllocated` is always `false`. Do
   not hold returned `Clay_String` pointers across frames.
6. **The hover-callback registry sweeps entries older than 2 generations
   at `Clay_BeginLayout`.** Callers should call `Clay_OnHover` every frame
   inside the element body, matching idiomatic Clay usage. Registering
   once and never re-registering will eventually reap the entry.
7. **The C `CLAY()` / `CLAY_TEXT()` macros have no Perl analog.** They
   expand to control-flow tricks tied to C `for`-loops. Use the
   open / configure / close primitives instead. See the POD in
   `lib/Clay/Layout.pm` for the mapping table.

## Repo conventions

- All Perl files start with:
  ```perl
  use v5.22;
  use warnings;
  use feature 'signatures';
  no warnings 'experimental::signatures';
  ```
- Function and struct names mirror C exactly (`Clay_Initialize`,
  `Clay__OpenElement`). Helpers that replace un-bindable C macros use
  snake_case (`sizing_fit`, `padding_all`, `corner_radius_all`).
- Hash keys for marshalled structs use the exact camelCase field names
  from clay.h (`backgroundColor`, `cornerRadius`, `layoutDirection`).
- Tests use `Test2::V0`. The smoke test in `t/00-load.t` doubles as the
  constants-loaded check.
- Render commands are returned as plain `AoH`

## What is and is not done

- Phases 1 to 13 of the implementation plan are complete. Renderer
  bindings will ship as separate distributions
  (`Clay::Layout::Renderer::*`).
- Phase 13 added the high-level `Clay::UI` layer on top of `Clay::Layout`.
  Source: `lib/Clay/UI.pm` (walker), `lib/Clay/UI/_keys.pm` (snake -> camel
  translator), `lib/Clay/UI/Role/*.pm` (Element + Stateful + Hoverable +
  TextNode archetype roles; `Has*` property mixin roles), and
  `lib/Clay/UI/{Box,Text,Button,ScrollPanel}.pm` (reference widgets).
  Tests: `t/10-ui-camelize.t`, `t/10b-ui-walker.t`, `t/11-ui-mixins.t`,
  `t/12-ui-widgets.t`. Example: `examples/04-ui-sidebar.pl`.

## Clay::UI invariants

1. Widgets are Object::Pad classes; the `class` keyword opens a fresh
   package, so `use Clay::Layout qw(...)` at file scope does NOT seed
   helper subs inside the class block. Either qualify
   (`Clay::Layout::sizing_fixed(...)`) or `use` again inside the body.
2. `Clay::UI::Role::Element::to_config` discovers contributor methods
   via `Object::Pad::MOP::Class`. Each mixin role provides one method
   named `contribute_<slice>(\%config)`. Names must be unique across
   composed roles (Object::Pad role composition errors on method
   conflict).
3. Widget classes that need to participate without making their own
   role can also expose a `contribute_*` method directly on the class;
   the walker iterates the class's `direct_methods` in addition to
   roles' (see `Clay::UI::ScrollPanel`).
4. Text leaves consume `Clay::UI::Role::TextNode`; the walker
   dispatches them to `Clay__OpenTextElement` instead of the normal
   open/configure/close trio and ignores their `children`.
5. Hover-callback registration must re-run every frame (existing
   runtime-invariant 6). The walker calls `install_hover_callback` on
   every `Hoverable` widget per frame, so user widgets MUST register
   inside that hook, not in `ADJUST`.
6. Clay's pointer-state struct is zero-initialised, which equals
   `CLAY_POINTER_DATA_PRESSED_THIS_FRAME`. The first `SetPointerState`
   after `Clay_Initialize` will dispatch hover callbacks with that
   ghost state regardless of `isPointerDown`. Tests of click behavior
   need a warm-up frame to settle Clay into `RELEASED`.
7. The walker injects `user_data => refaddr($widget)` into every
   element and text config and maintains a module-level weak registry
   so `Clay::UI::widget_for($cmd->{userData})` can recover the
   originating widget from a render command. A widget's `to_config`
   (or `text_config`) that sets `user_data` itself triggers a fail-loud
   error - pick one mechanism. The walker builds + validates the config
   BEFORE calling `Clay__OpenElementWithId` so a conflict cannot leave
   Clay's open-element stack unbalanced (an unbalanced stack SEGVs
   `Clay_EndLayout`).

## Pointers when something breaks

- Build fails on second `.c` file: the postamble was removed or renamed.
  Check `Makefile.PL`.
- `Could not find a typemap`: the `typemap` file moved or a new fixed-width
  int type appeared in the API. Update `typemap`.
- Segfault on second `Clay_Initialize`: re-read invariant #1 above.
- Hover/scroll test that worked yesterday now fails: a previous test left
  the context in a non-reset state, or you skipped the prior-frame
  pattern. Initialise a fresh context in each `subtest` when possible.
- `Clay::Layout: <name> callback threw: ...` warnings: an exception
  escaped a callback trampoline. The trampoline cannot propagate to
  Clay, so it warns. Fix the Perl callback.
