# Known issues

Problems found in the code while the documentation was reviewed and
rewritten (October 2026) that are still open. Each entry says what
happens, how to reproduce it and what would be expected. Entries are
ordered by severity. Fixed entries are removed (the history is in git);
the fixes for upstream Clay bugs live in `patches/`.

## 1. Upstream Clay: floating element attached to an element declared later

**Where:** `src/clay/clay.h`, `Clay__ConfigureOpenElementPtr` (around
lines 2221-2229 of the generated header)

**What happens:** A floating element with
`attachTo => CLAY_ATTACH_TO_ELEMENT_WITH_ID` whose target is declared
**after** it in the frame reports
`CLAY_ERROR_TYPE_FLOATING_CONTAINER_PARENT_NOT_FOUND` in the first frame
and `CLAY_ERROR_TYPE_INTERNAL_ERROR` ("Clay attempted to make an out of
bounds array access") in every later frame: Clay looks the target's
clip element up with an element index from the previous frame. The
element is still positioned correctly. With Clay::UI's default error
handler, `render` dies.

**Repro:** declare element `f` with
`floating => { attachTo => CLAY_ATTACH_TO_ELEMENT_WITH_ID, parentId => Clay_GetElementId('t') }`,
then element `t`, for three frames with an error handler that prints.

**Expected:** no error; declare the target first as a workaround.

## 2. Calling Clay_UpdateScrollContainers twice between frames forgets every scroll position

**Where:** upstream `src/clay/clay.h` around lines 4936-4940

**What happens:** `Clay_UpdateScrollContainers` removes every scroll
container that was not declared since its previous call. Calling it
twice without a frame in between therefore removes all of them:
`Clay_GetScrollContainerData($id)->{found}` becomes 0 and positions
reset to 0. Clay::UI calls it exactly once per `render`, and its
documentation warns against calling it yourself.

**Expected:** upstream behaviour; documented in Clay::XS and
Clay::UI::Role::Layout::HasScroll. Listed here because it is easy to
trigger from Clay::XS code.

## 3. Running transitions do not bump the Clay::UI revision

**Where:** `lib/Clay/UI.pm` (`render`), `lib/Clay/UI/Revision.pm`

**What happens:** While an element with a `transition` animates, its
render commands change from frame to frame, but nothing bumps the
revision: `laid_out_revision` stays the same. A renderer that follows
the documented "draw only when the revision moved" loop never draws the
animation, only its first frame.

**Repro:** a Clay::UI widget whose `contribute_transition` adds
`transition => { duration => 1, properties => CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR }`,
transition handlers installed after `Clay::UI->new`, then
`background_color` changed and `render(delta_time => 0.25)` called four
times: the colour goes 255 -> 108 -> 32 -> 4 while `laid_out_revision`
stays at the same value.

**Expected:** `render` bumps the revision while a transition is running
(Clay reports transition state to the handlers), or the documentation
tells renderers to draw every frame while transitions may run. The
Manual currently does the latter.
