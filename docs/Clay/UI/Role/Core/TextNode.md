# NAME

Clay::UI::Role::Core::TextNode - base role of every Clay::UI text widget

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::UI;
use Clay::UI::Role::Core::TextNode;

# A text widget of your own: a counter that renders its value.
class My::Counter :strict(params) :does(Clay::UI::Role::Core::TextNode) {
        field $count :param = 0;

        method increment () {
                $count++;
                $self->mark_changed;
                return $self;
        }

        method text () { return "Count: $count" }

        method text_config () {
                return { font_size => 20, text_color => [255, 255, 255, 255] };
        }
}

my $counter  = My::Counter->new;
my $ui       = Clay::UI->new(width => 400, height => 300, root => $counter);
$counter->increment;
my $commands = $ui->render;
```

# DESCRIPTION

`Clay::UI::Role::Core::TextNode` is the role every text widget
composes. A text widget becomes one Clay text element: a leaf that
shows a string and cannot have children. [Clay::UI::Text](../../Text.md) is the
ready-made text widget role; compose TextNode directly only to compute
the text or its settings yourself.

For a text widget the layout pass (the part of ["render" in Clay::UI](../../../UI.md#render) that
declares the tree to Clay) calls `text` and `text_config` and passes
both to `Clay__OpenTextElement`, instead of the open / configure /
close calls it makes for element widgets.

TextNode also composes [Clay::UI::Role::Layout::HasParent](../Layout/HasParent.md) (`parent`,
`root`, `ui`, `contains`, `tree_changed`) and
[Clay::UI::Role::Events::Listener](../Events/Listener.md) (`on`). A text widget has no
`id`, no children and no sizing groups.

# REQUIRED METHODS

## text

```perl
method text () { return 'Hello' }
```

Returns the string to show: a defined Perl string of characters.

## text\_config

```perl
method text_config () { return { font_size => 16, text_color => [0, 0, 0, 255] } }
```

Returns the text settings as a hashref: the fields of
["Clay\_TextElementConfig" in Clay::XS::Structs](../../../XS/Structs.md#clay_textelementconfig), with snake\_case or
camelCase keys (`font_id`, `font_size`, `text_color`,
`letter_spacing`, `line_height`, `wrap_mode`, `text_alignment`).
The layout pass copies the hash; it must not contain `user_data`
(`render` dies, because the layout pass sets it to find the widget
again). The values are checked only when the text element is
declared: a value of the wrong shape makes `render` die, an unknown
key is ignored.

# METHODS

## id

```perl
my $id = $text->id;    # undef
```

Returns undef: text widgets have no id. The reader exists so that a
predicate reading ids (["get\_children\_with" in Clay::UI::Role::Core::Element](Element.md#get_children_with))
works on every child.

## mark\_changed

```perl
$widget->mark_changed;
```

Bumps the revision ([Clay::UI::Revision](../../Revision.md)) and returns the widget. The
accessors of [Clay::UI::Text](../../Text.md) bump it themselves; a text widget class
with state of its own calls `mark_changed` from its setters, so that a
renderer that skips unchanged frames draws the next one.

# SEE ALSO

[Clay::UI::Text](../../Text.md), [Clay::UI::Role::Core::Element](Element.md),
[Clay::UI::Revision](../../Revision.md).
