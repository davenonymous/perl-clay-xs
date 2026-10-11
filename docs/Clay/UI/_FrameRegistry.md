# NAME

Clay::UI::\_FrameRegistry - what one Clay::UI frame laid out

# DESCRIPTION

[Clay::UI](../UI.md) builds one registry per frame while it walks the widget tree
and replaces the previous one only when the frame completes, so a failed
frame leaves the last good registry in place. It answers the questions
the next frame's pointer and scroll handling asks about the last layout:
which widget a render command's `userData` or a Clay element id
belongs to, where widgets came in the walk, which scroll containers were
declared under which element id, and how far they have scrolled since.

It also defines what a scroll container is: a widget composing
[Clay::UI::Role::Layout::HasScroll](Role/Layout/HasScroll.md). The walker injects Clay's scroll
offset only into scroll containers, and only they receive `OnScroll`.

Widget references are weak.

This module is internal. The API is not part of the public contract.

# METHODS

- `add_back_reference($widget)`

    Records `$widget`; returns the `userData` value for its render
    commands.

- `is_scroll_container($widget)`

    1 if `$widget` is a scroll container, else 0.

- `add_element($widget, $element_id)`

    Records an element widget in walk order under the element id hash from
    `Clay_GetElementId`; a scroll container is also listed by
    `scroll_containers`.

- `element_count`

    How many widgets `add_back_reference` recorded: the Clay layout
    elements the walk declared, element and text widgets alike.

- `widget_for($user_data)`, `widget_for_element($id)`

    The widget, or undef.

- `in_tree_order(@widgets)`

    `@widgets` sorted by walk position. Widgets the walk did not reach
    come last, in the depth-first pre-order of the tree they are in now;
    ties keep their original order.

- `scroll_containers`

    List of `[ $widget, $element_id ]` for the scroll containers that
    still exist, in walk order.

- `scroll_positions($ui)`

    Hashref `refaddr => [ $widget, $element_id, $position ]` for the
    scroll containers that still belong to `$ui` and that Clay knows,
    with their current scroll position. Needs `$ui`'s Clay context to be
    current.

- `scroll_changes($positions)`

    List of `[ $widget, $delta_x, $delta_y ]` for the containers of an
    earlier `scroll_positions` result that have moved since.
