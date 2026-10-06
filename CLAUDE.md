# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Perl bindings for the header-only Clay v0.14 C UI layout library (vendored,
no system libraries). Two layers:

- `Clay::XS` - low-level binding. Public `Clay_*` and internal `Clay__*`
  functions keep their exact C names; the C `CLAY()` / `CLAY_TEXT()` macros
  have no Perl analog (use the open / configure / close primitives, see the
  mapping table in `lib/Clay/XS.pm`).
- `Clay::UI` - Object::Pad widget layer: compose widget classes from roles,
  build a tree, and `Clay::UI->render` lays it out and turns pointer input
  into widget events. Nothing is drawn; layout returns render commands (AoH).

## Build and test

```
perl Makefile.PL && make && make test
prove -lvb t/04-elements.t                            # single test
CLAY_UI_UPDATE_FIXTURES=1 prove -lb t/99-golden.t     # regenerate golden fixtures
PERL_CLAY_DISABLE_SIMD=1 perl Makefile.PL             # skip Clay's SIMD probe
perl -Ilib -Iblib/lib -Iblib/arch examples/01-minimal.pl
```

Always test against `blib` (`prove -lb` or `make test`): the XS object lives
in `blib/arch/`, and plain `prove -l` can pick up a stale installed copy.

Golden fixtures: each `t/fixtures/*.pl` returns a coderef producing render
commands, compared against the matching `.json`. `09-ui-tree.pl` goes
through Clay::UI and replaces `userData` with widget class and id.

## Layout and build mechanics

- `lib/Clay/XS.xs` + `src/*.c` + `src/clay_perl.h` are the binding;
  `src/marshal.c` converts Perl hashes to Clay structs (keys are the exact
  camelCase field names from clay.h) and range-checks every argument. Each
  struct a function takes is one schema table there; the same tables run
  in parse mode (lenient, per frame) and check mode (`check_struct`,
  strict), which both croak `Clay::XS::StructError`, and in write mode
  (`schema_write`: the `*_to_sv` of those structs and the transition
  handler's `Clay_TransitionCallbackArguments` hash). Add a field by
  extending its table; t/23 checks every field against
  `lib/Clay/XS/Structs.pod` through `Clay::XS::_struct_schemas`. Element
  id hashes (including the `stringId` interning) are read only in
  `src/marshal.c`.
- `src/clay_perl_enums.h` lists every exported Clay enum once, as X-macros
  in clay.h's member order (`CLAY_PERL_ENUM_<Group>`, all groups in
  `CLAY_PERL_ENUMS`). BOOT installs the constants from it,
  `Clay::XS::_constant_names` returns their names for `@EXPORT_OK`, and
  the schema rows take their ranges from `CLAY_PERL_ENUM_MAX(Group)` (the
  last member; the build checks that members are 0..N-1) or, for the
  transition property flags, `CLAY_PERL_FLAGS_ALL`. Add a constant to its
  group's list and give it an `=item` in `lib/Clay/XS.pm`; nothing else.
- `src/clay/clay.h.orig` is the pristine upstream header (committed).
  `make` generates the gitignored `src/clay/clay.h` from it plus the
  patches in `@clay_patches` (`Makefile.PL`), applied in order:
  `patches/0001-clay-sizing-groups.patch` adds sizing groups
  (`sizingGroup`, `Clay__ApplySizingGroups`, a cycle error type;
  members share their group's largest size and largest minimum, so
  they still compress and wrap when their parents are too small);
  `patches/0002-clay-flow-layout.patch` adds `CLAY_LEFT_TO_RIGHT_WRAP`,
  `lineGap` and `lineSizing` (per element in `flowLines`: the X sizing
  pass records where lines start, the Y sizing pass how tall they are;
  later passes read both instead of recomputing);
  `patches/0003-clay-back-to-front.patch` adds `CLAY_BACK_TO_FRONT`
  (stack layout: both axes sized like the off axis, every child placed
  by `childAlignment`, no `betweenChildren` bars);
  `patches/0004-clay-upstream-fixes.patch` fixes upstream bugs without
  adding features (a completing exit transition no longer skips the
  next one, an exit starts from the current state, no background
  rectangle under image or custom elements, every command of a floating
  element carries its zIndex, `CLAY_TEXT_WRAP_NONE` never breaks,
  `lineHeight` boxes stack from the element's top, no `BORDER` for a
  transparent colour, a culled clip container still emits its scissor
  commands, a floating element may attach to an element declared later
  in the frame (the clip lookup waits until `Clay_EndLayout`), scroll
  containers are pruned by the frame generation they were last declared
  in, so repeated `Clay_UpdateScrollContainers` calls between frames are
  harmless, and the container swapped into a pruned slot is not skipped).
  The
  `postamble` in `Makefile.PL` holds that rule and a `src/%.o : src/%.c`
  rule; EUMM's default rule drops subdirectory objects in the CWD, so
  removing it breaks the build.
- `src/clay_impl.c` is the only file defining `CLAY_IMPLEMENTATION`. It
  also holds the Perl-free helpers that read Clay internals
  (`src/clay_impl_helpers.h`) and wraps the include in `#pragma GCC
  diagnostic ignored` for upstream's warnings.
- `PERL_NO_GET_CONTEXT` is on: helpers take `pTHX_`, callers pass `aTHX_`,
  trampolines Clay calls use `dTHX`.
- `typemap` only needs `uint32_t` (the sole fixed-width XS return type).
- `references/clay/` is an upstream clone for reading only; not built.

## Clay::XS runtime rules

- **Contexts** are a reference to a read-only scalar holding the pointer in
  ext magic (`src/clay_perl_context.c`); copies, forged objects and other
  threads croak. DESTROY calls `Clay_SetCurrentContext(NULL)` before
  freeing, otherwise the next `Clay_Initialize` reads freed memory.
- **Callbacks never croak through Clay.** Trampolines make one `G_EVAL`
  call into `Clay::XS::_dispatch` through `invoke_callback`
  (`src/callbacks.c`), which owns the temporaries scope, `$@` and the
  trailing userdata argument; errors are held on the context and
  rethrown by the XS wrapper after Clay returns (never while a callback
  still runs). Per-context callbacks
  live in `ctx->callbacks[kind]` (set with `clay_perl_callback_set`); a
  new kind needs an enum entry, a `store_result` case and a trampoline
  with its argument builder.
- **Callbacks cannot re-enter Clay.** Every exported XSUB has a wrapper
  guard in `CLAY_PERL_WRAPPERS` (`lib/Clay/XS.xs`): context, mutating or
  query, counts check, frame requirement, rethrow policy. Wrappers call
  `wrapper_enter` (refuses mutating calls inside callbacks, pins the
  context) and, when the rethrow policy is AFTER, `wrapper_leave`. A new
  exported XSUB needs a table row and a POD heading: `@EXPORT_OK` is built
  from the table's names, and t/19 checks that every export has a heading
  and the table against the POD. Internal `_` XSUBs (for the tests and
  Clay::UI) have no row and are not exported. "Inside a callback" spans
  the whole trampoline scope (`invoke_callback`), so DESTROYs of callback
  arguments count too.
- **Frame state** (`layout_state`): COMPLETE, DECLARING (between
  `Clay_BeginLayout` and `Clay_EndLayout`) or ABANDONED (a begun frame
  whose held error the next `Clay_BeginLayout` re-threw). Functions that
  walk Clay's layout tree (`Clay_SetPointerState`,
  `Clay_UpdateScrollContainers`) need COMPLETE; an element may be
  configured once, right after it is opened. The frame module (the last
  section of `src/clay_perl_context.c`, `clay_perl_frame_*` in
  `src/clay_perl.h`) owns this state, the open/close bookkeeping and
  `completed_frames`; the frame and element XSUBs only guard, parse,
  call it and call Clay, and the wrapper guards only read the state.
  `Clay::XS::_context_stats($ctx)` shows it to the tests.
- **Never give Clay a pointer it keeps into a caller's SV.** Text goes
  into a per-context chunked arena that lives an extra frame (longer for
  chunks an exiting element still shows, and for everything after an
  unfinished frame); element id strings are interned in private,
  read-only SVs. Only the hashing helpers borrow the caller's buffer for
  the duration of the call. The frame module decides when they may go:
  it recycles the arena and sweeps the interned ids (kept 2 completed
  frames, plus while under the pointer or shown by an exiting element)
  and the hover callbacks (kept 1) through one stamped-registry sweep,
  with both keep counts and their reasons side by side.
- Open/close balance is tracked; `Clay_EndLayout` auto-closes leftovers,
  then croaks.
- Pointer-over, hover and scroll test against the previous frame's layout,
  so tests need one completed frame first (see `t/06-pointer.t`,
  `t/07-scroll.t`). Clay clears hover callbacks on re-declaration, so
  `Clay_OnHover` must be called every frame.
- Transition handlers are per context (`Clay_SetTransitionHandlers`);
  Clay's callback signatures carry no element id.

## Clay::UI rules

- The Object::Pad `class` keyword opens a fresh package: file-scope
  `use Clay::XS qw(...)` imports are not visible inside it.
- `to_config` collects every `contribute_<slice>(\%config)` method from
  the class, its superclasses and roles (sorted by name, cached per class).
  Contributors must be order-independent and merge shared slices; method
  names must be unique across composed roles.
- `render` does all pointer work before `Clay_BeginLayout` (no element
  open, so listeners may change the tree): it maps `Clay_GetPointerOverIds`
  through the last frame's registry (`Clay::UI::_FrameRegistry`: built by
  the walk, swapped in only when a frame completes; it also holds walk
  order, `widget_for` back-references and scroll containers with their
  element ids) and hands the widgets, the down
  flag and scroll changes to `Clay::UI::Interaction` (`$ui->interaction`),
  which owns hover / armed / pressed / focus state and fires the events.
  Widgets hold no interaction state; `is_hovered`, `is_pressed`,
  `is_focused` and the derived `hovered` / `pressed` / `focused` states
  ask the tracker (the derived `disabled` state asks Disableable).
  Clay::UI registers no `Clay_OnHover` callbacks. Every queued event
  that is still due fires (each carries a claim check: events an earlier
  listener made stale are dropped, and stop / blur only follow a
  delivered start / focus), the layout pass always runs, then the first
  listener error is rethrown. Focus moves only through the tracker's `set_focused_widget` /
  `focus_next` / `focus_previous` (live tree order, not frame order);
  detaching a subtree drops its interaction state (`OnHoverStopped`) and
  focus (`OnBlur`) at once (`release_subtrees`; while its events fire the
  subtree no longer counts as part of the UI). Subtree questions have one
  answer each: Element's `descendants` (layout pre-order, internal
  children included; the only subtree walk in Clay::UI), HasParent's
  `contains` (walks up), and the tracker's `has_focus_within`,
  `focusables(within => ...)` and `default_next_focus` /
  `default_previous_focus(within => ...)` (a focus scope: the same
  stepping, limited to a subtree). Consumers use these instead of
  walking `children` themselves.
- Focus eligibility is derived, never pushed into a flag: Focusable's
  `can_focus` reader answers "the users' wish (the `can_focus` argument
  or last write) and `accepts_focus` and not `disabled`"; the writer
  only records the wish. A class that never takes focus overrides
  `accepts_focus` in a subclass (a class cannot override a method of a
  role it composes itself); one whose answer depends on its own state
  calls Focusable's `focus_eligibility_changed` from that state's
  setter. Writers that can make a widget ineligible
  (`can_focus`, Disableable's `disabled`, `focus_eligibility_changed`)
  call the tracker's `release_ineligible`, which disarms and unpresses a disabled widget
  and blurs a focused widget that cannot focus any more, at once. The
  tracker never arms or presses a disabled widget; `can_take_focus` is
  the one predicate for "may be focused now".
- Preparation runs between the events and the layout pass: `render`
  calls `Clay::UI::Role::Core::Preparable::_prepare_pending`, which
  calls `prepare_layout` on every queued widget that belongs to this UI
  (the queue is process-global and holds widgets weakly), again while
  preparations queue more, and dies after 100 rounds. A
  `prepare_layout` error is held like a listener error and rethrown
  after the layout pass. Widgets whose children follow from their own
  state call `request_prepare` from their setters (it bumps the
  revision) and rebuild in `prepare_layout`, not in every setter.
- `render` stores `current_revision()` in `laid_out_revision` right
  before the layout pass; nothing may change the tree after that point.
  Renderers remember `laid_out_revision` as the revision they drew, so
  changes made by listeners and preparations need no second frame.
- `Clay::UI::Role::Layout::GridCell` is a marker role (no fields; it
  implements no methods and requires Element's sizing-group methods): Grid stamps its column and row group ids on such a widget
  directly and wraps any other widget in a `Clay::UI::Grid::Cell`
  (which composes the marker). Grid keeps one list: its children are
  `Clay::UI::Grid::Row`s, whose children are the cell wrappers and
  which carry their `spans` flag and `height_id`; Grid holds no
  per-row arrays. Grids made with `share_columns_with`
  share one `Clay::UI::Grid::_IdSpace` (grid id and id counters) and a
  common grid `width_group`. Object::Pad 0.825 keeps `ADJUST :params`
  values alive until the next construction, so an `ADJUST :params`
  that receives another widget undefs it when done (see Grid).
- A scroll container is a widget composing HasScroll
  (`_FrameRegistry::is_scroll_container`): only it gets Clay's scroll
  offset injected as `childOffset` and receives OnScroll. The frame
  registry also snapshots and diffs scroll positions for `render`.
- The walker injects `user_data => refaddr($widget)` so
  `$ui->widget_for($cmd->{userData})` works; a widget setting `user_data`
  itself is an error.
- Children are changed only through `Element`'s validating primitives;
  the public mutators live in the `Container` role. A widget can be
  attached whenever it has no parent (removed ones can come back).
  Removal is by identity (`remove_child(@widgets)`, which dies for
  anything but widgets) or by id (`remove_child_with_id`); the identity
  query is `Element`'s `has_child`.
  Internal children (`add_internal_children`) are a widget class's own
  helpers in the laid-out tree; `children` and the Container mutators
  never see them. Every tree walk (the walker, the focus order, the
  frame registry) reads `layout_children`, never `children`. `$widget->ui` walks to the root, which a Clay::UI
  stamps at construction (write-once).
- Tree changes have one public seam: HasParent's no-op `tree_changed`.
  Clay::UI calls it (`_announce_tree_change`) on every widget of a
  subtree whose top got a parent, lost it (in `_release_children`, after
  the tracker's release) or became a UI root (end of Clay::UI's
  `ADJUST`), in layout pre-order, once the change is complete; never on
  reorder. Every hook runs; the first error is rethrown afterwards (a
  release listener's error wins). `_set_parent` / `_detach_parent` /
  `_set_ui_controller` are private: only `Element`'s primitives and
  Clay::UI's `ADJUST` call them, and no consumer overrides them.
  Classes react through `tree_changed :override` in a subclass.
- Attributes are validated where set (accessors and `ADJUST` via
  `Clay::UI::_validate`) and copied there with snake_case keys
  (`snake_keys`; both spellings of one key die there), so stored slices
  and their readers use one spelling; readers return copies too
  (`copy_value`), so no container is shared with callers. Contributors
  build fresh slices around the widget's own values (no per-frame deep
  copy: the walker's `camelize_keys` makes one), so `to_config` output is
  read-only. Clay values go through `check_struct`, the
  strict check mode of the struct schemas in `src/marshal.c`, so there is
  no Perl copy of Clay's keys or ranges. Classes are `:strict(params)`. User ids must not start with `anon:`; user
  sizing-group ids are `0 .. USER_GROUP_ID_MAX` (`2**20 - 1`, exported by
  `Clay::UI::_validate`; Grid derives its id packing from it and owns the
  ids above).
- Every setter that changes what a frame lays out or draws calls
  `bump_revision()` (`Clay::UI::Revision`) after its value is accepted,
  never on a read; child changes bump in `Element`'s primitives, the
  tracker when its hovered / armed / pressed / focused sets change,
  `render` when a scroll container moved. A new setter must bump too.
- `max_element_count` reaches Clay through a throwaway seed context
  (`Clay::UI::_initialize_context`): `Clay_MinMemorySize` and
  `Clay_Initialize` read the current context's counts, and setting them
  on another UI's context or with none current would disable that context
  or change Clay's process-wide defaults.

## Documentation

- `lib/Clay/Manual.pod` (user guide, feature index), `lib/Clay/Cookbook.pod`
  (task recipes), `lib/Clay/XS/Structs.pod` (every struct key) and the
  module POD are the docs; `README.md` is a short entry point.
- Every public function, method, parameter, event, constant group and
  struct key gets its own heading spelled as in code, so one grep finds
  it. Code samples in the POD must run (test them).
- Each example starts with the header block (`Shows:`, `Features:`,
  `Requires:`, `Run with:`); `Features:` lists the exact identifiers
  used. New examples go into the README table and the Manual's
  FEATURE INDEX.
- Figures live in `images/`, rendered by `tools/make-images` (`make
  images`; `make images-check` reports stale files): each is a Clay::UI
  tree in that script, laid out by Clay and drawn with Imager, plus the
  outputs of examples 06, 15 and 16. The POD shows a figure as a
  `=for text Figure: images/NAME.png in the distribution.` paragraph
  followed by a `=begin html` block with
  `<img src="https://raw.githubusercontent.com/davenonymous/perl-clay-xs/vVERSION/images/NAME.png" alt="...">`
  (MetaCPAN needs absolute URLs); the PDF is linked through its
  `github.com/.../blob/vVERSION/images/` URL. The script dies when the
  POD and the rendered set differ and rewrites `vVERSION` to the current
  `$Clay::UI::VERSION`, so run `make images` after changing a figure,
  a POD reference or the version, and commit what it wrote.

## Conventions

- Perl files start with `use v5.22; use warnings; use feature 'signatures';
  no warnings 'experimental::signatures';`.
- Helpers replacing C macros use snake_case (`sizing_fit`, `padding_all`).
- Tests use `Test2::V0`.

## Bumping Clay

1. Update `references/clay`, copy its `clay.h` to `src/clay/clay.h.orig`.
2. `rm -f src/clay/clay.h && make`. On rejects, fix `src/clay/clay.h.tmp`
   and regenerate the failing patch as a diff from the header with only the
   earlier patches applied to the fixed one, e.g. `diff -u --label
   a/src/clay/clay.h --label b/src/clay/clay.h <before> <after> >
   patches/0002-clay-flow-layout.patch`. Each patch applies on top of the
   previous ones.
3. Re-check the helpers in `src/clay_impl.c` against Clay's internals and
   extend its warning pragmas if the build warns. Compare the enums in
   clay.h with `src/clay_perl_enums.h`: new members go into their group's
   list (with POD), new enums the binding needs into a new group.
4. Regenerate golden fixtures; drift unrelated to upstream changes means
   one of the patches interacts badly with the new code.
