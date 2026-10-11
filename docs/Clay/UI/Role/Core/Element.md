# NAME

Clay::UI::Role::Core::Element - base role of every Clay::UI element widget

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::XS qw(sizing_fixed);
use Clay::UI;
use Clay::UI::Role::Core::Container;
use Clay::UI::Role::Layout::HasLayout;
use Clay::UI::Role::Style::HasBackground;

class My::Panel :strict(params)
        :does(Clay::UI::Role::Core::Container)
        :does(Clay::UI::Role::Layout::HasLayout)
        :does(Clay::UI::Role::Style::HasBackground)
{}

my $root = My::Panel->new(
        id     => 'root',
        layout => {
                sizing => { width => sizing_fixed(200), height => sizing_fixed(100) },
        },
        background_color => [255, 0, 0, 255],
);
$root->add_child(My::Panel->new(background_color => [0, 0, 255, 255]));

# The declaration the layout pass sends to Clay for this widget:
my $config = $root->to_config;
# { layout => { sizing => ... }, background_color => [255, 0, 0, 255] }

my $ui       = Clay::UI->new(width => 800, height => 600, root => $root);
my $commands = $ui->render;
```

# DESCRIPTION

`Clay::UI::Role::Core::Element` is the Object::Pad role every element
widget composes, directly or through another role. An element widget
becomes one Clay element (a box) in each frame. Text widgets are the
other kind of widget; they compose [Clay::UI::Role::Core::TextNode](TextNode.md)
instead.

The role provides:

- an optional `id` (["id"](#id)) and the id Clay::UI derives for widgets
without one (["resolve\_id"](#resolve_id));
- the list of children (["children"](#children)) and of internal children
(["internal\_children"](#internal_children)), with read access only;
- `to_config` (["to\_config"](#to_config)), which builds the widget's declaration
from the `contribute_*` methods of its roles (see
["EXTENDING THE DECLARATION"](#extending-the-declaration));
- `mark_changed` (["mark\_changed"](#mark_changed)) for widget classes that keep state of
their own.

It also composes [Clay::UI::Role::Layout::HasSizingGroup](../Layout/HasSizingGroup.md) (the
`width_group` and `height_group` attributes),
[Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md) (`parent`, `root`, `ui`,
`contains`, `tree_changed`) and
[Clay::UI::Role::Events::Listener](../Events/Listener.md) (`on`).

Element has no public method that changes the children. Widgets that
hold any children their user gives them compose
[Clay::UI::Role::Core::Container](Container.md), which adds `add_child` and the
removal methods. Widgets that decide their children themselves (such as
[Clay::UI::Grid](../../Grid.md)) compose Element alone and use the internal
child-list methods. The constructor never takes children: a widget
starts empty.

Two terms used below:

- declaration

    The hash of settings Clay receives for one element: `layout`,
    `background_color`, `border`, `floating` and so on (see
    [Clay::XS::Structs](../../../XS/Structs.md)). Clay::UI widgets build it with snake\_case keys;
    the layout pass converts the keys to Clay's camelCase.

- layout pass

    The part of ["render" in Clay::UI](../../../UI.md#render) that declares the widget tree to Clay:
    for every widget it calls `to_config` (or `text_config` for a text
    widget), opens the Clay element, configures it and walks the children.

# CONSTRUCTOR PARAMETERS

## id

```perl
my $panel = My::Panel->new(id => 'sidebar');
my $name  = $panel->id;    # 'sidebar', or undef
```

The element id of the widget: a non-empty string, used as the Clay
element id (`Clay_GetElementId($id)` gives the same numeric id the
layout pass uses). Optional; without it the layout pass derives an id
from the widget's position (see ["resolve\_id"](#resolve_id)).

The `id` reader is read-only: an id is set at construction and never
changes.

An undef `id` means "no id". The constructor dies with
`Clay::UI: 'id' must be a non-empty string` for a reference or an empty
string, and with `Clay::UI: 'id' must not start with 'anon:'` for an id
starting with `anon:`, which is reserved for derived ids.

Two widgets with the same id in one frame are a Clay error; with the
default `error_handler` of [Clay::UI](../../../UI.md) the `render` dies.

## width\_group

The width sizing group; see
["width\_group" in Clay::UI::Role::Layout::HasSizingGroup](../Layout/HasSizingGroup.md#width_group).

## height\_group

The height sizing group; see
["height\_group" in Clay::UI::Role::Layout::HasSizingGroup](../Layout/HasSizingGroup.md#height_group).

# METHODS

## children

```perl
my $kids = $widget->children;    # arrayref, a new one on every call
```

Returns a new arrayref holding the direct children, in order. Changing
that array does not change the widget. Internal children (see
["add\_internal\_children"](#add_internal_children)) are not included.

## child\_count

```perl
my $count = $widget->child_count;
```

Returns the number of direct children, without copying them. Internal
children are not counted.

## child\_at

```perl
my $first = $widget->child_at(0);
```

Returns the direct child at `$index` (0 is the first), without copying
the children, or undef for an index past the last child. Internal
children are not included. Dies with
`Clay::UI: child_at takes an index, got ...` for anything but a
non-negative integer in plain decimal digits (`-1`, `1.5`, `'01'`,
undef and references die).

## get\_children\_with

```perl
my @foos = $root->get_children_with(sub { ($_->id // '') =~ /^foo_/ });
my @bars = $root->get_children_with(sub ($child) { $child->isa('My::Bar') });
```

Returns the direct children for which `$predicate->($child)` is
true, as a list (in scalar context: how many). `$_` is set to the
child as well, so both calling styles work. Does not look at
grandchildren or internal children. Text widgets are passed too; their
`id` is undef. Dies with
`Clay::UI: get_children_with takes a code reference, got ...` for
anything else.

## has\_child

```perl
$panel->add_child($footer) unless $panel->has_child($footer);
```

Returns 1 when the widget is one of the direct children (the very
object, compared by identity), 0 otherwise: for a widget attached
elsewhere, for a grandchild and for an internal child (see
["add\_internal\_children"](#add_internal_children)). Dies with
`Clay::UI: has_child takes a widget, got ...` for anything but a
widget, an id included.

## internal\_children

```perl
my $helpers = $widget->internal_children;
```

Returns a new arrayref holding the internal children, in order.

## layout\_children

```perl
my $laid_out = $widget->layout_children;
```

Returns a new arrayref holding the children followed by the internal
children: everything a frame lays out directly below this widget. The
layout pass, the focus order of [Clay::UI::Interaction](../../Interaction.md) and the
registry that maps render commands back to widgets read this list.
Widget users want ["children"](#children).

## descendants

```perl
my @below = $widget->descendants;
```

Returns every widget below this one, not the widget itself, as a list
in layout pre-order: each entry of ["layout\_children"](#layout_children) followed by its
own subtree. Internal children and the widgets below them are
included, so this is the order in which a frame declares the subtree
and the default focus order walks it. Element widgets and text
widgets are listed alike. To ask whether one widget is below another,
use ["contains" in Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md#contains), which walks up
instead.

## add\_internal\_children

```perl
$self->add_internal_children($scrollbar);
```

For widget classes: attaches widgets that the class needs in the
laid-out tree but that are not its user's content, for example a
floating scrollbar over a scroll container or a popup. Internal
children are:

- validated and given this widget as `parent`, like children (see
["ATTACHING CHILDREN"](#attaching-children); the same errors apply);
- laid out after the children, and part of the UI (`ui`, events,
focus order) like any child;
- invisible to the widget's user: `children`, `get_children_with` and
the mutators of [Clay::UI::Role::Core::Container](Container.md) never show or remove
them.

Bumps the revision ([Clay::UI::Revision](../../Revision.md)) and returns the widget.

## remove\_internal\_children

```perl
$self->remove_internal_children($scrollbar);
```

Detaches the given internal children the way removed children are
detached (their `parent` becomes undef, hover, press and focus inside
them are released, see ["ATTACHING CHILDREN"](#attaching-children)). Widgets that are not
internal children of this widget are ignored. Bumps the revision when
something was removed. Returns the widget. Dies, changing nothing, with
`Clay::UI: remove_internal_children takes widgets, got ...` for
anything but widgets.

## to\_config

```perl
my $config = $widget->to_config;
```

Builds and returns the widget's declaration: a new hashref with
snake\_case keys. It calls every `contribute_*` method of the widget's
class once, as `$self->$name(\%config)`, so each one adds its part
(see ["EXTENDING THE DECLARATION"](#extending-the-declaration)). A widget with nothing to declare
returns `{}`.

The hashref is new on every call, and so are the parts the roles of
this distribution write (`layout`, `border`, ...), but the values
inside them may be the widget's own copies. Treat the result as
read-only; copy what you want to change. The layout pass works on a
camelCase copy of it.

Do not override `to_config`. Object::Pad roles have no `SUPER`, so an
override silently drops every `contribute_*` method; add a
`contribute_*` method instead.

## resolve\_id

```perl
my $id = $widget->resolve_id($base, \@indices);
```

Returns the string the layout pass hashes with `Clay_GetElementId` for
this widget: the user's `id` when it has one, otherwise an anonymous
id derived from the widget's position:

```perl
'anon:' . length($base) . ":$base/" . join('/', @indices)
```

`$base` is the id of the nearest ancestor with an id (`''` when there
is none) and `@indices` the positions in `layout_children` on the way
down from that ancestor. For example:

```text
root without an id                    anon:0:/
its third child                       anon:0:/2
child 1 of the widget 'list'          anon:4:list/1
child 0 of that child                 anon:4:list/1/0
```

The length prefix keeps anonymous ids apart from each other (`a/b` as
an id cannot be confused with an index path), and the reserved `anon:`
prefix keeps them apart from user ids.

An anonymous id changes when the widget moves: inserting a sibling
before it, or before one of its anonymous ancestors, gives it a new id.
Give an `id` to widgets that need the same Clay element id from frame
to frame: scroll containers ([Clay::UI::Role::Layout::HasScroll](../Layout/HasScroll.md)
requires one), elements with Clay transitions, and elements you look up
with [Clay::XS](../../../XS.md) functions such as `Clay_GetElementData`.

The layout pass supplies the arguments; calling `resolve_id` yourself
is only useful in tests.

## mark\_changed

```perl
$widget->mark_changed;
```

Bumps the revision ([Clay::UI::Revision](../../Revision.md)) and returns the widget. The
accessors of this distribution's roles bump it themselves, and so does
every change to the children. A widget class that keeps state of its
own, which its `contribute_*` methods turn into the declaration, calls
`mark_changed` from its setters, so that a renderer that skips
unchanged frames draws the next one.

# EXTENDING THE DECLARATION

`to_config` knows nothing about layout, colours or borders. It finds
every method of the widget's class whose name starts with
`contribute_` - from the class, its superclasses and every composed
role - and calls each one with the declaration hash under
construction. Each method writes one part of the declaration. This is
how [Clay::UI::Role::Layout::HasLayout](../Layout/HasLayout.md) adds `layout`,
[Clay::UI::Role::Style::HasBackground](../Style/HasBackground.md) adds `background_color`, and
so on.

A widget class adds a declaration part Clay::UI has no role for by
defining a `contribute_<name>` method. This class adds Clay's
`aspectRatio` (see ["aspectRatio" in Clay::XS::Structs](../../../XS/Structs.md#aspectratio)):

```perl
use v5.22;
use Object::Pad;
use Clay::XS qw(sizing_fixed);
use Clay::UI;
use Clay::UI::Box;
use Scalar::Util ();

class My::Picture :strict(params) :does(Clay::UI::Box) {
        field $aspect_ratio :param = 1;

        # The constructor and the setter check the value the same way.
        sub checked_ratio {
                my ($ratio) = @_;
                die "My::Picture: aspect_ratio must be a positive number\n"
                        unless Scalar::Util::looks_like_number($ratio) && $ratio > 0;
                return $ratio;
        }

        ADJUST {
                checked_ratio($aspect_ratio);
        }

        method aspect_ratio (@new) {
                return $aspect_ratio unless @new;
                $aspect_ratio = checked_ratio($new[0]);
                $self->mark_changed;    # the declaration changes
                return $aspect_ratio;
        }

        # Adds the aspectRatio part to the declaration.
        method contribute_aspect_ratio ($config) {
                $config->{aspect_ratio} = { aspect_ratio => $aspect_ratio };
                return;
        }
}

my $picture = My::Picture->new(
        layout           => { sizing => { width => sizing_fixed(200) } },
        background_color => [90, 90, 90, 255],
        aspect_ratio     => 2,
);
my $ui = Clay::UI->new(width => 800, height => 600, root => $picture);
my $commands = $ui->render;    # the rectangle is 200 x 100

$picture->aspect_ratio(4);
$commands = $ui->render;       # now 200 x 50
```

The rules for `contribute_*` methods:

- Each is called once per `to_config` with the declaration hashref; the
return value is ignored. The methods run in alphabetical order of their
names (`contribute_background` before `contribute_layout`).
- Write keys in snake\_case, the spelling every stored slice and reader
uses (an attribute set with camelCase keys reads back in snake\_case).
camelCase works too, since the layout pass converts every key, but do
not use both spellings of one key: merged slices then collide.
- A part that another method may also write must be merged, not
replaced. [Clay::UI::Role::Layout::HasLayout](../Layout/HasLayout.md) merges the user's
`layout` over what is already there; defaults go under what is already
there, as [Clay::UI::Grid](../../Grid.md) does for its `layout`:

    ```perl
    method contribute_my_defaults ($config) {
            $config->{layout} = { child_gap => 4, %{ $config->{layout} // {} } };
            return;
    }
    ```

- Do not set a value that another `contribute_*` method of the class
also sets and that cannot be merged, for example a `contribute_state_colour` that sets
`background_color` in a class that also has the `background_color`
attribute ([Clay::UI::Role::Style::HasBackground](../Style/HasBackground.md)): the result then
depends on the order of the method names. To set the background by
state ([Clay::UI::Role::Style::HasStates](../Style/HasStates.md)), either leave the
`background_color` attribute unset, or compose the roles without
HasBackground instead of [Clay::UI::Box](../../Box.md) (as the `Settings::Toggle`
class in `examples/12-ui-interaction.pl` does).
- Write fresh hashes and arrays into the declaration; do not hand out a
container the widget keeps changing.
- Do not set `user_data`: the layout pass sets it to find the widget
again, and `render` dies with `Clay::UI: widget ... set user_data in its config`.
- A setter that changes what a `contribute_*` method writes calls
["mark\_changed"](#mark_changed).
- Clay::XS checks the declaration only when the element is configured,
and ignores unknown keys there: a misspelled key in a
`contribute_*` method is silently dropped. Values of the wrong shape
make `render` die. Validate in the constructor and the setters
(`check_struct` of [Clay::XS](../../../XS.md) checks a value against a Clay struct,
see ["CHECKING STRUCTS" in Clay::XS](../../../XS.md#checking-structs)).
- The methods run for every widget in every frame; keep them cheap.

Method names must be unique: Object::Pad dies when two composed roles
provide the same `contribute_*` method, or when a class defines one
that a role it composes already provides
(`Method 'contribute_layout' clashes with the one provided by role ...`).
The roles of this distribution use these names:

- `contribute_background` ([Clay::UI::Role::Style::HasBackground](../Style/HasBackground.md))
- `contribute_border` ([Clay::UI::Role::Style::HasBorder](../Style/HasBorder.md))
- `contribute_clip` ([Clay::UI::Role::Layout::HasScroll](../Layout/HasScroll.md))
- `contribute_corner_radius` ([Clay::UI::Role::Style::HasCornerRadius](../Style/HasCornerRadius.md))
- `contribute_floating` ([Clay::UI::Role::Layout::HasFloating](../Layout/HasFloating.md))
- `contribute_grid_defaults` ([Clay::UI::Grid](../../Grid.md))
- `contribute_layout` ([Clay::UI::Role::Layout::HasLayout](../Layout/HasLayout.md))
- `contribute_sizing_group` ([Clay::UI::Role::Layout::HasSizingGroup](../Layout/HasSizingGroup.md),
part of every element widget)

A subclass may override a `contribute_*` method of its superclass;
only the override runs.

The list of `contribute_*` methods is looked up once per class and
kept, because Object::Pad classes do not change once compiled.

# ATTACHING CHILDREN

Every change to the children - through
[Clay::UI::Role::Core::Container](Container.md), [Clay::UI::Grid](../../Grid.md) or
["add\_internal\_children"](#add_internal_children) - checks all new children before anything
changes, so a call that dies leaves the widget as it was. It dies when
a new child:

- is not a widget: `Clay::UI: child is not a widget (got ...)`. A widget
is a blessed object composing `Clay::UI::Role::Core::Element` or
[Clay::UI::Role::Core::TextNode](TextNode.md);
- appears twice in the call: `Clay::UI: the same widget (...) is attached twice in one call`;
- is the widget itself or one of its ancestors:
`Clay::UI: cannot attach a widget to itself or to one of its descendants`;
- is the root of a [Clay::UI](../../../UI.md):
`Clay::UI: widget ... is the root of a Clay::UI and cannot become a child`;
- still has a parent, even if it is this widget:
`Clay::UI: widget ... is still attached to a parent; remove it first`
(see ["ATTACHING AND REMOVING" in Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md#attaching-and-removing)).

Every change bumps the revision ([Clay::UI::Revision](../../Revision.md)). Widgets that
decide their children themselves may also reorder them
(["reorder\_rows" in Clay::UI::Grid](../../Grid.md#reorder_rows)); reordering detaches nothing.

Once a change is complete, every widget of each added or removed
subtree gets a call of its
[tree\_changed](../Layout/HasParent.md#tree_changed) hook,
the subtree's own widget first, then the others in ["descendants"](#descendants)
order. Every hook runs; the change method then dies with the first
error.

A removed child is detached: its `parent` becomes undef and its
subtree is no longer part of the UI until it is attached again. Hover,
press and focus inside the subtree are released first: a hovered
widget gets `OnHoverStopped`, the focused widget gets `OnBlur` (see
[Clay::UI::Interaction](../../Interaction.md)). A listener of those events that dies does
not stop the removal: the call completes (the `tree_changed` hooks
included) and then dies with the listener's error.

# SEE ALSO

[Clay::UI](../../../UI.md), [Clay::UI::Role::Core::Container](Container.md),
[Clay::UI::Role::Core::TextNode](TextNode.md), [Clay::UI::Box](../../Box.md),
[Clay::UI::Revision](../../Revision.md), [Clay::XS::Structs](../../../XS/Structs.md), [Clay::Manual](../../../Manual.md).
