# NAME

Clay::UI::Role::Core::Preparable - let a widget rebuild its subtree right before the layout pass

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::UI;
use Clay::UI::Box;
use Clay::UI::Text;
use Clay::UI::Role::Core::Preparable;

class My::Label :strict(params) :does(Clay::UI::Text) {}

class My::List :strict(params)
        :does(Clay::UI::Box)
        :does(Clay::UI::Role::Core::Preparable)
{
        field @items;

        method add_item ($item) {
                push @items, $item;
                $self->request_prepare;    # cheap: the children are rebuilt once per frame
                return $self;
        }

        method prepare_layout () {
                $self->clear_children;
                $self->add_child(map { My::Label->new(text => $_) } @items);
                return;
        }
}

my $list = My::List->new(id => 'list');
my $ui   = Clay::UI->new(width => 400, height => 300, root => $list);
$list->add_item($_) for qw(apples pears plums);
my $commands = $ui->render;    # prepare_layout ran once, then the layout pass
```

# DESCRIPTION

A widget whose children follow from state of its own (a list of items,
the rows of a table) would have to rebuild them on every change of that
state. With `Clay::UI::Role::Core::Preparable` it asks to be prepared
instead and rebuilds them once, right before the next frame is laid
out, however many changes came before.

`request_prepare` puts the widget in a queue. ["render" in Clay::UI](../../../UI.md#render) calls
the `prepare_layout` method of every queued widget after the frame's
pointer events and before the layout pass (the part of `render` that
declares the tree to Clay), so changes the event listeners made are
included.

- Only widgets that belong to the rendering UI are prepared (their
`ui` is that UI). A widget that is not part of a UI yet stays queued
until a UI it belongs to renders. That is checked again right before
each preparation: a widget that an earlier preparation of the same
round detached (a list rebuilding its rows, say) is not prepared and
stays queued.
- Parents are prepared before their descendants: a round prepares the
queued widgets with fewer ancestors first, and widgets with as many
ancestors in the order they called `request_prepare`. A widget that
rebuilds its subtree therefore runs before the widgets inside it.
- A preparation may change anything (no Clay element is open while it
runs) and may request another preparation, of itself or of other
widgets. `render` keeps preparing until no request is left, and dies
after 100 rounds with
`Clay::UI: widgets kept requesting preparation; 100 rounds of prepare_layout did not settle`.
- The queue is shared by all UIs of the process and holds widgets
weakly: a widget freed while it is queued is forgotten (its entry goes
at the next `render` of any UI).

Compose this role together with a widget role
([Clay::UI::Role::Core::Element](Element.md), [Clay::UI::Box](../../Box.md), ...); it uses the
widget's `ui` method.

# METHODS

## prepare\_layout

```perl
method prepare_layout () { ... }
```

Required: the widget class implements it. It brings the widget (usually
its children) up to date. `render` calls it with no arguments and
ignores the return value. By the time it runs the widget is no longer
queued, so a `request_prepare` inside it queues it again.

If `prepare_layout` dies, the other widgets due in the same round are
still prepared, then `render` stops preparing: requests made during
that round stay queued for the next `render`. `render` still runs the
layout pass and then dies with the first error (or with an earlier
listener error of the same frame).

## request\_prepare

```perl
$widget->request_prepare;
```

Queues the widget for `prepare_layout` before the next layout pass of
its UI. Queuing a queued widget again changes nothing. Always bumps the
revision ([Clay::UI::Revision](../../Revision.md)), so a renderer that skips unchanged
frames draws the next one. Returns the widget.

## is\_prepare\_pending

```perl
if ($widget->is_prepare_pending) { ... }
```

Returns 1 while the widget is queued, 0 otherwise.

# SEE ALSO

["render" in Clay::UI](../../../UI.md#render), [Clay::UI::Revision](../../Revision.md), [Clay::Manual](../../../Manual.md).
