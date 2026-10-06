# Clay-UI

Perl bindings for the Clay C layout library: `Clay::XS` exposes Clay with
its C names, and `Clay::UI` builds a widget layer on top of it.

## Language

### Marshalling

**Struct schema**:
The per-struct table in `Clay::XS` that lists a Clay struct's fields, their
C kinds, ranges and nested schemas. It is the single source of truth for which
hash keys a Clay struct accepts, which values are valid and which keys a
returned struct has.
_Avoid_: key table, field list, marshal keys

**Parse mode**:
Turning a Perl hash into a Clay struct for an actual Clay call. It is lenient
about unknown keys, because it runs for every element in every frame.
_Avoid_: unmarshal, convert

**Check mode**:
Validating a Perl hash against a struct schema without building anything for
Clay. It is strict about unknown keys and array lengths. It is public
(`check_struct`), and Clay::UI uses it to validate attributes where they are set.
_Avoid_: dry run, validate-only marshal

**Write mode**:
Turning a Clay struct into a Perl hash through its struct schema, with the
keys parse mode reads. Every struct Clay::XS returns or passes to a callback
that has a schema is written this way.
_Avoid_: serialize, to_sv mirror

**Struct error**:
The exception object (`Clay::XS::StructError`) that both parse mode and check
mode croak. It carries the field path, the expected value, the value received
and an optional hint, and it stringifies to the C-style message.
_Avoid_: marshal error, validation error

### Layout

**Wrap container**:
An element with `layoutDirection` `CLAY_LEFT_TO_RIGHT_WRAP`. It places its
children left to right and starts a new line whenever the next child does
not fit the remaining inner width.
_Avoid_: flow box, flex-wrap container

**Line**:
A run of a wrap container's children placed side by side. The X sizing
pass decides where lines start; `lineSizing` decides whether lines share
the container's leftover height (`GROW`) or keep their tallest child's
height (`FIT`).
_Avoid_: row (reserved for Clay::UI::Grid rows)

**Stack container**:
An element with `layoutDirection` `CLAY_BACK_TO_FRONT`. It places all its
children on top of each other, each aligned on its own by
`childAlignment`, and draws later children over earlier ones.
_Avoid_: z-stack, overlay (reserved for `overlayColor`)

**Grid cell**:
A widget composing the marker role `Clay::UI::Role::Layout::GridCell`.
`Clay::UI::Grid` stamps its column `width_group` and row `height_group`
on it directly, so its box, background and border cover the equalized
column width and row height. Any other widget is wrapped in an unstyled
`Clay::UI::Grid::Cell` first.
_Avoid_: wrapper (the Cell the Grid makes around other widgets)

**Spanning row**:
A Grid row holding one cell as wide as the whole grid, such as a group
heading. It belongs to no column: it widens none, and the columns do not
size it. It gets a row `height_group` like any row.
_Avoid_: colspan, full-width row

**Shared columns**:
Grids linked with `share_columns_with`: column N of all of them is one
Clay column (one `width_group`). They draw their ids from one id space,
so their rows never share a height.
_Avoid_: linked grids, column sync

**Shared grid width**:
The common `width_group` grids with shared columns get, so each is as
wide as the widest of them, also one with only spanning rows or none.
_Avoid_: grid width group (the mechanism, not the term)

### Binding

**Held error**:
The first exception a Perl callback raised while Clay was running, kept on
the context until a wrapper rethrows it once Clay has returned. Later ones
are only counted. Nothing takes it while a callback is still running.
_Avoid_: pending error, deferred error, stashed error

**Wrapper guard**:
The per-XSUB descriptor and the checks it drives: which context the wrapper
needs, whether it mutates Clay (forbidden inside callbacks) or only queries,
whether it needs an open frame or element, and when it rethrows a held error.
_Avoid_: REQUIRE_CONTEXT, guard flags

### Interaction

**Interaction tracker**:
The per-UI object (`$ui->interaction`) that owns hover, armed, pressed and
focus state. It turns the widgets under the pointer, the pointer's down flag
and scroll changes into state changes, moves focus on request (walking the
live tree, not the frame registry) and fires the matching events. `render`
feeds it real pointer input; callers may feed it synthetic input.
_Avoid_: pointer state machine, %_tracked

**Armed**:
A Pressable that a press started over and that no release has ended yet.
Only an armed widget can receive OnRelease.
_Avoid_: pending press

**Derived state**:
The state names `hovered`, `pressed`, `focused` and `disabled`. HasStates
answers them live from the interaction tracker and from Disableable, and
they are read-only. All other state names are user states.
_Avoid_: auto-synced state, mirrored state

**Disabled widget**:
A widget composing `Disableable` whose `disabled` flag is set. It cannot
take the focus (its `can_focus` reads 0 while its users' wish is kept),
the tracker never arms or presses it, and it loses focus, arming and press
at once when it becomes disabled.
_Avoid_: inactive, greyed out (a look, not the state)

**Focus eligibility**:
What `can_focus` reads: the widget's users want it focusable (the
`can_focus` argument or the last write), its class accepts the focus
(`accepts_focus`, overridden by subclasses) and it is not disabled. The
tracker's `can_take_focus` adds that the widget belongs to the UI.
_Avoid_: focusable flag (the flag is only the users' wish)

**Focus scope**:
A subtree of the UI that a focus query is limited to, given as
`within => $widget` to the tracker's `focusables`, `default_next_focus` and
`default_previous_focus`: the widget and everything below it in layout
pre-order, internal children included. Stepping wraps around inside it.
_Avoid_: focus trap (what a modal dialog builds from it), focus group

### Frames

**Frame module**:
The part of `Clay::XS` that owns a context's frame state (complete,
declaring, abandoned), its open/close bookkeeping and the count of completed
frames, and decides from them how long text copies, interned element ids
and hover callbacks are kept. The frame and element functions only call it.
_Avoid_: frame manager, lifecycle code

**Frame registry**:
What one frame laid out (`Clay::UI::_FrameRegistry`): widgets by render-command
userData and by Clay element id, walk order, and the scroll containers with the
element ids they were declared under. The walk builds a new one, and it replaces
the previous one only when the frame completes. It also turns its scroll
containers' position changes into tracker input.
_Avoid_: pending registries, id map

**Preparation**:
The call of `prepare_layout` on a widget composing
`Clay::UI::Role::Core::Preparable` that asked for it with
`request_prepare`. `render` prepares the requesting widgets of its UI
after the frame's events and before the layout pass, once however many
requests came before, and again while preparations request more (at
most 100 rounds).
_Avoid_: deferred rebuild, invalidation

**Laid-out revision**:
`$ui->laid_out_revision`: the `Clay::UI::Revision` value at which the
last `render` started its layout pass, after events and preparations.
Every change up to it is in that frame, so a renderer remembers it as
the revision it drew.
_Avoid_: drawn revision (the renderer's copy of it)

**Scroll container**:
A widget composing HasScroll. Only scroll containers get Clay's scroll offset
injected while they are walked, and only they receive OnScroll. A widget that
writes a `clip` slice without HasScroll is clipped but does not scroll.
_Avoid_: clip element, scrollable

**Tree change**:
A change of a widget's place in a tree: the top of its subtree got a
parent, lost it, or became the root of a Clay::UI. Clay::UI announces it
to every widget of the subtree through the `tree_changed` hook, after the
change is complete. Reordering children is not a tree change.
_Avoid_: reparenting, attach event, membership change

**Internal child**:
A widget a widget class attaches below itself with `add_internal_children`
because it needs it in the laid-out tree (a floating scrollbar over a scroll
container), as opposed to the children its user adds. `children`,
`has_child` and the Container mutators never show or remove it; `layout_children` lists children
and internal children, and every tree walk reads that.
_Avoid_: hidden child, private child, helper widget (the role it plays, not the term)
