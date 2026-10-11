# NAME

Clay::UI::Box - styled container widget role for Clay::UI

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::XS qw(sizing_fixed sizing_grow padding_all CLAY_TOP_TO_BOTTOM);
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;

class My::Box   :strict(params) :does(Clay::UI::Box) {}
class My::Label :strict(params) :does(Clay::UI::Text) {}

my $sidebar = My::Box->new(
        id               => 'sidebar',
        layout           => {
                sizing           => { width => sizing_fixed(200), height => sizing_grow() },
                padding          => padding_all(8),
                child_gap        => 4,
                layout_direction => CLAY_TOP_TO_BOTTOM,
        },
        background_color => [40, 50, 60, 255],
        corner_radius    => 6,
        border_color     => [80, 80, 80, 255],
        border_width     => 1,
);
$sidebar->add_child(map { My::Label->new(text => $_) } qw(Home Search Settings));

my $ui = Clay::UI->new(width => 800, height => 600, root => $sidebar);
my $commands = $ui->render;

$sidebar->background_color([60, 70, 80, 255]);    # shown from the next render on
```

# DESCRIPTION

`Clay::UI::Box` is the general-purpose container widget: an element
that holds any children and has every layout and style attribute -
sizing, padding and child placement, background colour, border, corner
radius and floating. Most widget classes start from it.

Like every widget in Clay::UI it is a role, so that you can combine it
with other roles in a class of your own. Compose it in a class (as
`My::Box` above) to get a widget you can construct; add interaction
roles such as [Clay::UI::Role::Interaction::Pressable](Role/Interaction/Pressable.md) to make the
box react to the pointer.

All attributes are constructor parameters and read/write accessors, so
a box's layout and style can change at any time; the change shows at
the next `render`. Values are checked when they are set (at
construction or by the accessor) and a bad value dies there, naming
the attribute. The box keeps its own copy of every value and every
read returns a new copy, so changing a hash or array after passing it
in, or one an accessor returned, does not change the box. Every write
bumps the revision ([Clay::UI::Revision](Revision.md)); reads never do.

Declare consumer classes `:strict(params)`, so that a misspelled
constructor parameter dies instead of being ignored:

```perl
class My::Box :strict(params) :does(Clay::UI::Box) {}
```

# AT A GLANCE

Everything a Box has, with the role that documents it.

## Constructor parameters and attributes

- [id](Role/Core/Element.md#id)

    Element id, set at construction only (read-only reader).

- [layout](Role/Layout/HasLayout.md#layout)

    Sizing, padding, child gap, child alignment, layout direction, line
    gap and line sizing.

- [background\_color](Role/Style/HasBackground.md#background_color)

    Fill colour.

- [border\_color](Role/Style/HasBorder.md#border_color)

    Border colour.

- [border\_width](Role/Style/HasBorder.md#border_width)

    Border widths: one number or per side.

- [corner\_radius](Role/Style/HasCornerRadius.md#corner_radius)

    Corner radius: one number or per corner.

- [floating](Role/Layout/HasFloating.md#floating)

    Take the box out of the layout and attach it to another element.

- [width\_group](Role/Layout/HasSizingGroup.md#width_group)

    Share the width with other elements of the same group.

- [height\_group](Role/Layout/HasSizingGroup.md#height_group)

    Share the height with other elements of the same group.

## Children

- [add\_child](Role/Core/Container.md#add_child)

    Append children.

- [remove\_child](Role/Core/Container.md#remove_child)

    Remove the given children.

- [remove\_child\_with\_id](Role/Core/Container.md#remove_child_with_id)

    Remove children by id.

- [remove\_children\_with](Role/Core/Container.md#remove_children_with)

    Remove children matching a test.

- [clear\_children](Role/Core/Container.md#clear_children)

    Remove all children.

- [children](Role/Core/Element.md#children)

    The children, as a new arrayref.

- [get\_children\_with](Role/Core/Element.md#get_children_with)

    The children matching a test.

- [has\_child](Role/Core/Element.md#has_child)

    Whether a widget is a child.

- [add\_internal\_children](Role/Core/Element.md#add_internal_children), [remove\_internal\_children](Role/Core/Element.md#remove_internal_children), [internal\_children](Role/Core/Element.md#internal_children), [layout\_children](Role/Core/Element.md#layout_children)

    Helpers a widget class lays out next to its user's children.

- [descendants](Role/Core/Element.md#descendants)

    Every widget below this one, in layout pre-order.

## Tree

- [parent](Role/Layout/HasParent.md#parent)

    The widget this one is attached to.

- [root](Role/Layout/HasParent.md#root)

    The topmost widget above this one.

- [ui](Role/Layout/HasParent.md#ui)

    The [Clay::UI](../UI.md) this widget is part of.

- [contains](Role/Layout/HasParent.md#contains)

    Whether a widget is this one or below it.

- [tree\_changed](Role/Layout/HasParent.md#tree_changed)

    The hook a subclass overrides to react when the widget joins or
    leaves a tree.

## Events

- [on](Role/Events/Listener.md#on)

    Register a listener for an event name.

- [handlers\_for](Role/Events/Listener.md#handlers_for)

    The listeners registered for an event name.

- [fire\_event](Role/Events/Emitter.md#fire_event)

    Fire an event at this box; it bubbles up through the parents.

## Declaration and extension

- [to\_config](Role/Core/Element.md#to_config)

    The declaration (the hash of settings Clay receives for the element).

- [resolve\_id](Role/Core/Element.md#resolve_id)

    The id the layout pass uses for the box.

- [mark\_changed](Role/Core/Element.md#mark_changed)

    Bump the revision from a setter of your own.

- `contribute_layout`, `contribute_background`, `contribute_border`, `contribute_corner_radius`, `contribute_floating`, `contribute_sizing_group`

    The methods that add each part to the declaration; see
    ["EXTENDING THE DECLARATION" in Clay::UI::Role::Core::Element](Role/Core/Element.md#extending-the-declaration).

# COMPOSED ROLES

`Clay::UI::Box` composes:

- [Clay::UI::Role::Core::Container](Role/Core/Container.md) (children), which composes
[Clay::UI::Role::Core::Element](Role/Core/Element.md), [Clay::UI::Role::Layout::HasSizingGroup](Role/Layout/HasSizingGroup.md),
[Clay::UI::Role::Layout::HasParent](Role/Layout/HasParent.md) and [Clay::UI::Role::Events::Listener](Role/Events/Listener.md);
- [Clay::UI::Role::Layout::HasLayout](Role/Layout/HasLayout.md);
- [Clay::UI::Role::Style::HasBackground](Role/Style/HasBackground.md);
- [Clay::UI::Role::Style::HasBorder](Role/Style/HasBorder.md);
- [Clay::UI::Role::Style::HasCornerRadius](Role/Style/HasCornerRadius.md);
- [Clay::UI::Role::Layout::HasFloating](Role/Layout/HasFloating.md);
- [Clay::UI::Role::Events::Emitter](Role/Events/Emitter.md).

A Box does not scroll. For a styled scroll container, compose
[Clay::UI::Role::Layout::HasScroll](Role/Layout/HasScroll.md) in the same class (it then needs
an `id`):

```perl
class My::ScrollBox :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Layout::HasScroll) {}
```

A Box does not react to the pointer by
itself: add [Clay::UI::Role::Interaction::Hoverable](Role/Interaction/Hoverable.md),
[Clay::UI::Role::Interaction::Pressable](Role/Interaction/Pressable.md) or
[Clay::UI::Role::Interaction::Focusable](Role/Interaction/Focusable.md).

# SEE ALSO

[Clay::UI](../UI.md), [Clay::UI::Text](Text.md), [Clay::UI::Grid](Grid.md), [Clay::Manual](../Manual.md),
[Clay::Cookbook](../Cookbook.md), [Clay::XS::Structs](../XS/Structs.md).
