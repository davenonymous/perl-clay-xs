# Clay-UI

Perl bindings for the Clay C layout library: `Clay::XS` exposes Clay with
its C names, and `Clay::UI` builds a widget layer on top of it.

## Language

### Marshalling

**Struct schema**:
The per-struct table in `Clay::XS` that lists a Clay struct's fields, their
C kinds, ranges and nested schemas. It is the single source of truth for which
hash keys a Clay struct accepts and which values are valid.
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

**Struct error**:
The exception object (`Clay::XS::StructError`) that both parse mode and check
mode croak. It carries the field path, the expected value, the value received
and an optional hint, and it stringifies to the C-style message.
_Avoid_: marshal error, validation error

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
The state names `hovered`, `pressed` and `focused`. HasStates answers them
live from the interaction tracker, and they are read-only.
All other state names are user states.
_Avoid_: auto-synced state, mirrored state

### Frames

**Frame registry**:
What one frame laid out (`Clay::UI::_FrameRegistry`): widgets by render-command
userData and by Clay element id, walk order, and the scroll containers with the
element ids they were declared under. The walk builds a new one, and it replaces
the previous one only when the frame completes. It also turns its scroll
containers' position changes into tracker input.
_Avoid_: pending registries, id map

**Scroll container**:
A widget composing HasScroll. Only scroll containers get Clay's scroll offset
injected while they are walked, and only they receive OnScroll. A widget that
writes a `clip` slice without HasScroll is clipped but does not scroll.
_Avoid_: clip element, scrollable
