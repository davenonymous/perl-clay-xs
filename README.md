# Clay::Layout

Perl XS bindings for [Clay](https://github.com/nicbarker/clay), a header-only
C UI layout library.

Every public `Clay_*` and internal `Clay__*` function from clay.h v0.14 is
exposed under its exact C name. The C macros (`CLAY()`, `CLAY_TEXT()`, ...)
do not translate directly because they use C-specific control flow tricks;
this binding instead exposes the underlying open / configure / close
primitives those macros expand to.

## Build

```sh
perl Makefile.PL
make
make test
```

Requirements:

- Perl 5.22 or later
- A C99 compiler (GCC, Clang, or MSVC with `/std:c99`)
- ExtUtils::MakeMaker 7.12+
- Test2::V0 and JSON::PP (test only)

Clay's header is vendored in `src/clay/clay.h`; no external runtime
dependencies.

## Quick taste

```perl
use Clay::Layout qw(:all);

my $ctx = Clay_Initialize(
    Clay_MinMemorySize(),
    { width => 800, height => 600 },
    sub ($err, $userdata) { warn $err->{errorText} },
);

Clay_SetMeasureTextFunction(sub ($text, $config, $userdata) {
    return {
        width  => length($text) * $config->{fontSize},
        height => $config->{fontSize},
    };
});

Clay_BeginLayout();

Clay__OpenElementWithId( Clay_GetElementId("root") );
Clay__ConfigureOpenElement({
    layout          => { sizing => { width => sizing_grow(), height => sizing_grow() } },
    backgroundColor => [240, 240, 240, 255],
});
Clay__CloseElement();

my $render_commands = Clay_EndLayout(0);
# dispatch on $_->{commandType} for each command...
```

See `examples/01-minimal.pl` and `examples/02-sidebar-demo.pl` for fuller
illustrations, and `lib/Clay/Layout.pm`'s POD for the complete C-macro
to Perl-helper mapping.

## What's here

| Layer                                                              | Status        |
|--------------------------------------------------------------------|---------------|
| Phase 1: project bootstrap                                          | Complete      |
| Phase 2: type marshalling foundation                                | Complete      |
| Phase 3: rich `Clay_ElementDeclaration` marshalling                  | Complete      |
| Phase 4: lifecycle (Init / BeginLayout / EndLayout)                 | Complete      |
| Phase 5: element open / configure / close                            | Complete      |
| Phase 6: text-measurement callback                                  | Complete      |
| Phase 7: pointer state and per-element hover                        | Complete      |
| Phase 8: scroll containers and query-scroll callback                | Complete      |
| Phase 9: debug, culling, capacity, ease-out                         | Complete      |
| Phase 10: transition handlers (single per-context handler set)       | Complete      |
| Phase 11: golden-fixture regression harness                         | Complete      |
| Phase 12: documentation and examples                                | Complete      |
| Phase 13: Perl-idiomatic high-level layer (closures, snake_case)    | Future work   |

## Known limitations

- **Per-element transition callbacks are not supported.** Clay's transition
  callback signatures lack an element id, so a single C trampoline cannot
  dispatch to different Perl coderefs per element. Use
  `Clay_SetTransitionHandlers` to install a single set that fires for every
  transitioning element; dispatch in your handler based on the transition
  arguments. See `src/clay_perl.h` for the design rationale.

- **Single-threaded.** Matches Clay's own constraint. Multi-context use is
  supported via `Clay_SetCurrentContext`; multi-thread use is not.

## Renderers

Clay::Layout only produces a sorted array of `Clay_RenderCommand` hashrefs.
It does not draw anything. Renderers will ship as separate distributions
(`Clay::Layout::Renderer::Cairo`, `Clay::Layout::Renderer::Terminal`, ...).

## License

zlib/libpng, matching Clay itself. See `src/clay/LICENSE.md` for the
upstream notice.
