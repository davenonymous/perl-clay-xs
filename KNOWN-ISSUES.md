# Known issues

Problems found in the code while the documentation was reviewed and
rewritten (October 2026). All but entry 2 are still open. Each entry says
what happens, how to reproduce it and what would be expected. Entries
are ordered by severity.

## 1. A transition without handlers delays the change by one frame

**Where:** `src/marshal.c` (`finish_transition_config`),
`src/callbacks.c` (`clay_perl_transition_handler_trampoline`)

**What happens:** Every element declared with a `transition` key gets
the binding's trampoline as its C transition handler, even when no Perl
handlers are installed with `Clay_SetTransitionHandlers`. In C, a NULL
handler disables transitions entirely (`clay.h` checks
`transition.handler` before starting one). With the trampoline set,
Clay starts a transition; the trampoline finds no Perl handler, leaves
`current` unchanged and reports completion. The element therefore shows
its **old** value for one more frame, then jumps to the new one.

This also affects Clay::UI: a widget whose `contribute_*` method adds a
`transition` key lags one frame behind every change unless the program
installs handlers with `Clay_SetTransitionHandlers` after
`Clay::UI->new`.

**Repro:**

```perl
use v5.22; use warnings; use feature 'signatures'; no warnings 'experimental::signatures';
use Clay::XS qw(:all);
my $ctx = Clay_Initialize(Clay_MinMemorySize(), [100, 100]);
for my $colour ([255, 0, 0, 255], [0, 0, 255, 255], [0, 0, 255, 255]) {
	Clay_BeginLayout();
	Clay__OpenElementWithId(Clay_GetElementId('x'));
	Clay__ConfigureOpenElement({
		layout          => { sizing => { width => sizing_fixed(10), height => sizing_fixed(10) } },
		backgroundColor => $colour,
		transition      => { duration => 1, properties => CLAY_TRANSITION_PROPERTY_BACKGROUND_COLOR },
	});
	Clay__CloseElement();
	my $commands = Clay_EndLayout(0.25);
	say join ',', @{ $commands->[0]{renderData}{backgroundColor} }{qw(r g b)};
}
# prints 255,0,0 / 255,0,0 / 0,0,255
```

**Expected:** Without transition handlers the second frame shows the
new colour (`0,0,255`), as in C. Either leave `handler` NULL when the
context has no Perl transition handler, or document the lag.

A related observation (not analysed further): an element whose exit
transition was interrupted by removing the handlers
(`Clay_SetTransitionHandlers()` with no arguments) and that is then
declared again keeps showing its stale mid-transition colour, even after
a different `backgroundColor` is declared.

## 2. (fixed) examples/06-png-render.pl drew every rectangle with square corners

Imager's `box()` has no `r` parameter, so the example ignored
`cornerRadius`. The example now draws rounded corners with an
antialiased polygon mask, as `examples/15-og-card.pl` does. Kept here so
the numbers of the other entries stay stable.

## 3. Upstream Clay: a running transition skips a frame when an exit transition completes

**Where:** `src/clay/clay.h.orig` line 4740 (upstream Clay v0.14)

**What happens:** When an exit transition completes, Clay removes its
entry with `Clay__TransitionDataInternalArray_RemoveSwapback(..., i)`
but, unlike the two other removal loops (lines 4466 and 4587), does not
follow it with `i--`. The last entry is swapped into slot `i` and is
skipped for that frame: its transition handler is not called and its
transitioned values are not applied, so it shows its target value for
one frame and then continues animating.

**Repro:** In one frame, remove an element that has an exit transition
(`exit => { hasSetFinal => 1 }`, `duration => 0.25`) and add another
element with an enter transition; step frames with `Clay_EndLayout(0.05)`.
In the frame where the exit completes, the entering element's handler is
not called. `examples/10-xs-transitions.pl` staggers the two changes to
avoid this.

**Expected:** every running transition gets one handler call per frame.
Fix: add `i--;` after that call, as a fourth patch under `patches/`.

## 4. Upstream Clay: an image or custom element's background covers the image

**Where:** `src/clay/clay.h` (generated), the render command emission
for `image` / `custom` elements (around line 3714) and the background
rectangle that follows it (around line 3751)

**What happens:** An element with both `image` (or `custom`) and a
`backgroundColor` with alpha above 0 produces its `IMAGE` / `CUSTOM`
command and then a `RECTANGLE` command for the same box, which a
renderer draws over the image. A comment in clay.h says the background
colour is otherwise passed as a property of the IMAGE or CUSTOM command.

**Workaround:** put the background on a parent element, or leave
`backgroundColor` unset on image and custom elements.

**Expected:** no separate rectangle; the colour only travels in the
command's `renderData` (or the rectangle comes before the image).

## 5. A fresh Clay::XS context reports the pointer as "pressed this frame"

**Where:** `Clay_Initialize` / `Clay_GetPointerState`

**What happens:** Before the first `Clay_SetPointerState`,
`Clay_GetPointerState()->{state}` is 0, which is
`CLAY_POINTER_DATA_PRESSED_THIS_FRAME` (the zero value of Clay's enum).
Code that checks for a press before any input sees one. Worse, the
**first real press** is then reported as `CLAY_POINTER_DATA_PRESSED`
(1) instead of `CLAY_POINTER_DATA_PRESSED_THIS_FRAME`, so hover callbacks
and code that wait for "pressed this frame" miss the first click.
`Clay::UI` settles the state in its constructor; Clay::XS users do not
get that. The cause is upstream (`clay.h` around lines 4851-4856), but
the binding could settle the state in `Clay_Initialize`.

**Repro:**

```sh
perl -Iblib/lib -Iblib/arch -MClay::XS=:all -e '
  my $c = Clay_Initialize(Clay_MinMemorySize(), [10, 10]);
  print Clay_GetPointerState()->{state} == CLAY_POINTER_DATA_PRESSED_THIS_FRAME ? "pressed\n" : "released\n"'
# prints "pressed"

perl -Iblib/lib -Iblib/arch -MClay::XS=:all -e '
  my $c = Clay_Initialize(Clay_MinMemorySize(), [100, 100]);
  Clay_BeginLayout(); Clay_EndLayout();
  Clay_SetPointerState([10, 10], 1);
  print Clay_GetPointerState()->{state}, "\n"'
# prints 1 (CLAY_POINTER_DATA_PRESSED), expected 0 (PRESSED_THIS_FRAME)
```

**Expected:** a new context reports `CLAY_POINTER_DATA_RELEASED`, or the
documentation of `Clay_GetPointerState` warns about it.

## 6. Negative corner radii and out-of-range colours are accepted

**Where:** `src/marshal.c`, `corner_radius_fields` (plain `F_FLOAT`)

**What happens:** `check_struct('Clay_CornerRadius', { topLeft => -4 })`
passes, and a negative radius reaches the render commands. Padding,
border widths and gaps are range-checked; radii are not.

Colour channels are plain floats too: `background_color => [300, 0, 0, 255]`
passes validation in Clay::UI and Clay::XS.

**Expected:** radii below 0 are rejected like other out-of-range values;
colour channels are either checked against 0..255 or documented as
unchecked (Clay itself does not interpret them).

## 7. Clay::UI scroll_to does not stop momentum scrolling

**Where:** `lib/Clay/UI.pm` (`scroll_to`) / `set_scroll_position` in
`lib/Clay/XS.xs`

**What happens:** After a drag scroll (`enable_drag_scrolling`), Clay
keeps moving the container with momentum for several frames. A
`scroll_to` during that glide sets the position, but the remaining
momentum then moves the container away from it again in the next
frames. `examples/13-ui-scroll-floating.pl` waits until the glide has
stopped before it calls `scroll_to`.

**Expected:** a programmatic scroll cancels momentum, as a new wheel
event does in most toolkits; or the documentation of `scroll_to` and
`set_scroll_position` says that momentum continues.

## 8. Upstream Clay: floating element attached to an element declared later

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

## 9. Upstream Clay: some commands of a floating element carry zIndex 0

**Where:** `src/clay/clay.h`, render command emission (around lines
3510-3582)

**What happens:** Inside a floating element with `zIndex => 4`, the
`RECTANGLE`, `SCISSOR_START` and `OVERLAY_COLOR_*` commands carry
`zIndex` 4, but its `BORDER`, `SCISSOR_END` and the `betweenChildren`
`RECTANGLE` commands carry 0. Renderers that draw in array order (as
documented) are not affected; renderers that sort by `zIndex` are.

**Expected:** every command of a floating subtree carries its zIndex.

## 10. Upstream Clay: CLAY_TEXT_WRAP_NONE still breaks at newlines

**Where:** `src/clay/clay.h`, text measurement and wrapping

**What happens:** `wrapMode => CLAY_TEXT_WRAP_NONE` produces the same
lines as `CLAY_TEXT_WRAP_NEWLINES`: the text `"hi\nworld foo bar"`
becomes two `TEXT` commands. clay.h describes NONE as "disables
wrapping entirely".

**Expected:** one line, or a documented difference. The Manual
describes the actual behaviour.

## 11. Upstream Clay: TEXT boxes extend below their element when lineHeight is set

**Where:** `src/clay/clay.h`, text render commands (around lines
3651-3667)

**What happens:** With `lineHeight` greater than the measured height,
each line's bounding box is `lineHeight` tall **and** shifted down by
`(lineHeight - measured height) / 2`. The last line's box therefore
extends below the element: `fontSize => 10, lineHeight => 30` with two
lines gives an element 60 tall and line boxes at y 10..40 and 40..70.

**Expected:** boxes inside the element (either the shift or the
enlarged height, not both). Renderers should centre the glyphs in the
box and not rely on its bottom edge.

## 12. Percentages are not range-checked

**Where:** `src/marshal.c` (`read_sizing_axis`, percent),
`sizing_percent` in `lib/Clay/XS.xs`

**What happens:** `sizing_percent(-0.5)` in a 200 wide parent gives an
element -100 wide, silently. A value above 1 reaches the error handler
(`CLAY_ERROR_TYPE_PERCENTAGE_OVER_1`), and the element is still laid out
wider than its parent. Integer fields such as `padding` are range-checked
at the boundary; `percent` is not.

**Expected:** values outside 0..1 are rejected by the binding with a
`Clay::XS::StructError`, like other out-of-range values.

## 13. Upstream Clay: BORDER emitted for an invisible border colour

**What happens:** A `BORDER` command is produced whenever a border
width is above 0, even if `border.color` has alpha 0 (the
`betweenChildren` rectangles do check alpha). Harmless for most
renderers; noted for completeness.

## 14. Error messages say "a ARRAY reference"

**Where:** `src/marshal.c` line 83 (`describe_value`)

**What happens:** `check_struct('Clay_ClipElementConfig', { vertical => [] })`
croaks `... expected a plain boolean value, got a ARRAY reference`.

**Expected:** "an ARRAY reference" (the article is built as `"a %s"`).

## 15. Sizing groups stop wrapping text: a Grid column cannot shrink to fit

**Where:** `patches/0001-clay-sizing-groups.patch`, in the generated
`src/clay/clay.h`: `Clay__EqualizeSizingGroups` (around line 3078; it
raises `minDimensions` to the group size near line 3106) and
`Clay__PropagateSizesUp` (around line 3153; it raises `newMin`)

**What happens:** Every member of a sizing group gets the group's
largest *unwrapped* width as its minimum. Clay's compression can then
never make a member narrower, so text in it never wraps. A
`Clay::UI::Grid` whose column holds long wrapping text (cell width
`sizing_grow()` or `sizing_fit()`) becomes wider than its parent, even
with a single row. The same two cells in a plain row box wrap
correctly.

**Repro:** a box with `sizing_fixed(300)` holds a Grid (width
`sizing_grow()`) with one row: a `Clay::UI::Grid::Cell` with
`sizing_grow()` holding a 40-word `CLAY_TEXT_WRAP_WORDS` text, and a
cell with the text `1,234.00`. With a measure function of 5 units per
character: the text cell is 995 x 10 and the grid 1035 wide. As
children of a plain left-to-right box: 260 x 40 (wrapped).

**Workaround:** give the wrapping column a maximum
(`sizing_fit(0, 200)` or `sizing_grow(0, 200)`) or a fixed width;
`examples/16-invoice-pdf.pl` measures the other columns and fixes the
description column's width.

**Expected:** grouped members compress together down to the largest
member's minimum (its longest word), as ungrouped siblings do.

## 16. Clicking a disabled button inside a pressable container clicks the container

**Where:** `lib/Clay/UI/Interaction.pm` line 144 (disabled Pressables
are filtered out before the press target is chosen)

**What happens:** A disabled Pressable is removed from the candidates
before Clay::UI picks the topmost Pressable under the pointer. When a
disabled button sits inside a Pressable card, pressing and releasing
over the button gives the **card** `OnPress` and `OnRelease`: a click on
a disabled button activates its container.

**Repro:** a Pressable card containing a Pressable button with
`disabled => 1`; `$ui->interaction->update(over => [$card, $button], down => 1)`
then the same with `down => 0`. The card receives OnPress and OnRelease.

**Expected:** probably nothing is pressed (the disabled button absorbs
the click, as in HTML), unless passing the click through is intended;
the current behaviour is documented in Clay::UI::Interaction.

## 17. Calling Clay_UpdateScrollContainers twice between frames forgets every scroll position

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

## 18. lib/Clay/XS.xs header comment claims every public function is bound

**Where:** `lib/Clay/XS.xs` lines 4-6

**What happens:** The comment says every public Clay v0.14 function
except `Clay_CreateArenaWithCapacityAndMemory` is exposed.
`Clay_RenderCommandArray_Get` is not bound either (Clay_EndLayout
returns a Perl array instead). The Clay::XS POD names both.

**Expected:** the comment names both exceptions.

## 19. Count getters need a context, the setters do not

**Where:** `lib/Clay/XS.xs`, the `CLAY_PERL_WRAPPERS` rows of
`Clay_GetMaxElementCount` and `Clay_GetMaxMeasureTextCacheWordCount`

**What happens:** Without a current context, `Clay_SetMaxElementCount`
and `Clay_SetMaxMeasureTextCacheWordCount` change the process-wide
defaults used by the next `Clay_Initialize`, but the getters croak
without a context, so the defaults just set cannot be read back.

**Expected:** the getters also work without a context (returning the
process-wide defaults), or the asymmetry is intended and stays
documented.

## 20. HasStates accepts any value as a state name

**Where:** `lib/Clay/UI/Role/Style/HasStates.pm` lines 21-28
(`add_state`, `remove_state`, `toggle_state`)

**What happens:** `add_state(undef)` stores `''` and warns
"Use of uninitialized value"; `add_state([])` stores `'ARRAY(0x...)'`.
Every other Clay::UI setter validates its value and dies on bad input.

**Expected:** die for anything but a non-empty plain string.

## 21. HasStates `states` in scalar context counts only derived states

**Where:** `lib/Clay/UI/Role/Style/HasStates.pm` lines 64-66

**What happens:** `my $n = $widget->states` with two user states and no
derived state gives 0: the return list is built with the comma
operator, so scalar context yields its last element count. The POD says
"use list context only".

**Expected:** the total number of active states, or a croak in scalar
context.

## 22. Predicates of get_children_with / remove_children_with receive text widgets

**Where:** `lib/Clay/UI/Role/Core/Element.pm` line 98,
`lib/Clay/UI/Role/Core/Container.pm` line 32

**What happens:** Text children are passed to the predicate, but text
widgets have no `id` method, so the natural
`$box->remove_children_with(sub { $_->id =~ /^tmp-/ })` dies with
`Can't locate object method "id" via package ...` as soon as the box
has a text child.

**Expected:** either text widgets get an `id` method returning undef,
or the documentation keeps showing a guard (`$_->can('id')`), as the
POD of both methods does.

## 23. Inconsistent error message endings

**Where:** `lib/Clay/UI/Grid.pm` lines 257, 360, 367, 444, 447;
`lib/Clay/UI/Role/Core/Element.pm` lines 49-59; `lib/Clay/UI/_keys.pm`
line 57

**What happens:** These `die` messages have no trailing newline, so
Perl appends ` at lib/Clay/UI/Grid.pm line N.`, pointing into the
library instead of the caller (for example
`Clay::UI: child is not a widget (got non-ref) at lib/Clay/UI/Role/Core/Element.pm line 49.`).
The validation errors of `Clay::UI::_validate` end in `"\n"` and carry
no location.

**Expected:** one style; ideally `croak`-like messages that name the
caller's line.

## 24. add_child() without arguments bumps the revision

**Where:** `lib/Clay/UI/Role/Core/Container.pm` line 15

**What happens:** `$box->add_child()` changes nothing but bumps the
revision, so a renderer that skips unchanged frames draws one frame
too many. Minor.

**Expected:** no bump when nothing was added.

## 25. A dying prepare_layout silently drops the other pending preparations

**Where:** `lib/Clay/UI/Role/Core/Preparable.pm` lines 25-31
(`_prepare_pending`)

**What happens:** Each round removes every due widget from the queue
first and then calls `prepare_layout` on them one after another. When
one of them dies, the widgets after it in that round are neither
prepared nor queued again: they stay out of date until something calls
`request_prepare` on them again. `render` rethrows the first error, so
the caller sees the failure of one widget but not that others were
skipped.

**Repro:** two Preparable widgets A and B in one UI, A's `prepare_layout`
dies; after `render` dies, `$b->is_prepare_pending` is 0 and B was never
prepared, also not by the next `render`.

**Expected:** the remaining preparations of the round still run (as the
remaining events do after a listener error), or the skipped widgets stay
queued.

## 26. Upstream Clay: children of a culled clip container are drawn unclipped

**Where:** `src/clay/clay.h`, render command emission (scissor commands
are emitted behind the clip container's own offscreen test, around lines
3644-3647)

**What happens:** Culling tests every element on its own. When a clip
container lies completely outside the viewport, Clay leaves out its
`SCISSOR_START` / `SCISSOR_END`, but a child that reaches into the
viewport is still emitted, now without a clip region around it, so it
is drawn in full.

**Repro:** a 100 wide clip container floated to `offset => { x => -150, y => 0 }`
holding a 300 wide child: the frame contains one `RECTANGLE` at x -150
and no scissor commands.

**Expected:** the child is clipped (or culled together with its
container).

## 27. Running transitions do not bump the Clay::UI revision

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

## 28. set_focused_widget with a non-widget warns before it dies

**Where:** `lib/Clay/UI/Interaction.pm` lines 327-336

**What happens:** With a widget focused,
`$ui->interaction->set_focused_widget(5)` first warns
`Use of uninitialized value in numeric eq (==) at lib/Clay/UI/Interaction.pm line 327`
and only then dies with the documented "target must be a blessed
widget": `is_focused` calls `refaddr` on the argument before it is
validated.

**Expected:** the documented die, without the warning (validate first).

## 29. Upstream Clay: an exit right after an enter transition starts from the wrong state

**Where:** `src/clay/clay.h` around lines 5193-5196 (exit start) and the
IDLE reset around line 5395

**What happens:** When an exit transition starts, Clay sets only
`targetState` (from `setFinalState`); `initialState` keeps the value the
previous transition started from and is only refreshed in a frame
without a running transition. An element removed in the frame right
after its enter transition ended therefore exits from its *enter* start
state instead of its current look (for a fade-in, it is invisible for
the whole exit).

**Repro:** in `examples/10-xs-transitions.pl`, remove the chips one frame
earlier (change `from => 31` to `from => 30`): `chip-play` is not drawn
at all while it exits. The example leaves one quiet frame to avoid this.

**Expected:** an exit starts from the element's current state.
