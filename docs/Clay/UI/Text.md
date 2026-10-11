# NAME

Clay::UI::Text - text widget role for Clay::UI

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::XS qw(CLAY_TEXT_WRAP_NONE CLAY_TEXT_ALIGN_CENTER);
use Clay::UI;
use Clay::UI::Text;

class My::Label :strict(params) :does(Clay::UI::Text) {}

my $label = My::Label->new(
        text           => 'Hello, world!',
        font_size      => 18,
        text_color     => [255, 255, 255, 255],
        wrap_mode      => CLAY_TEXT_WRAP_NONE,
        text_alignment => CLAY_TEXT_ALIGN_CENTER,
);
$label->text('Goodbye');    # shown from the next render on

my $ui = Clay::UI->new(width => 400, height => 100, root => $label);
my ($command) = @{ $ui->render };
# $command->{renderData}{stringContents} eq 'Goodbye'
```

# DESCRIPTION

`Clay::UI::Text` is the ready-made text widget. A text widget becomes
one Clay text element: a leaf that shows a string, wraps it to the
width its parent gives it and cannot have children. Like every widget
in Clay::UI it is a role; compose it in a class of your own (as
`My::Label` above) to get a widget you can construct.

It composes [Clay::UI::Role::Core::TextNode](Role/Core/TextNode.md), which provides
`parent`, `root`, `ui`, `contains`, `tree_changed`, `on` and
`mark_changed`. A text widget has no `id`, no children, no sizing
groups and no background; put it in a [Clay::UI::Box](Box.md) to style or size
it.

Clay measures text with the `measure_text` function of the
[Clay::UI](../UI.md) (see ["new" in Clay::UI](../UI.md#new)). The function receives the string and
the text settings below, and returns the width and height the renderer
will need for that text with that font; the default is a rough
monospace estimate.

Classes should be declared `:strict(params)`, so that a misspelled
constructor parameter dies instead of being ignored.

# ATTRIBUTES

Each attribute is a constructor parameter and a read/write accessor of
the same name: call it without an argument to read, with one argument to
write. A write bumps the revision ([Clay::UI::Revision](Revision.md)), takes effect
at the next `render` and returns the new value. Values are checked when
they are set, at construction or by the accessor; a bad value dies
naming the attribute, for example
`Clay::UI: 'font_size' expected an integer in 0..65535, got '1.5'`.
Calling an accessor with more than one argument dies with
`Clay::UI: 'text' takes one value`.

The settings are the fields of Clay's text configuration; see
["Clay\_TextElementConfig" in Clay::XS::Structs](../XS/Structs.md#clay_textelementconfig) for their exact meaning.

## text

```perl
$label->text('New caption');
```

The string to show: any defined, non-reference Perl string (characters,
so any Unicode text). Default `''`. Dies with
`Clay::UI: 'text' must be a defined string` otherwise.

## font\_id

```perl
$label->font_id(1);
```

Which font to use: an integer from 0 to 65535 that your
`measure_text` function and your renderer map to a font. Default
`0`.

## font\_size

```perl
$label->font_size(24);
```

The font size, an integer from 0 to 65535. Default `16`.

## text\_color

```perl
$label->text_color([255, 255, 255, 255]);
$label->text_color({ r => 255, g => 255, b => 255, a => 255 });
```

The text colour: `[$r, $g, $b, $a]` (exactly four numbers) or
`{ r, g, b, a }` (a channel left out is 0). Channels are finite
numbers, by convention 0 to 255. Default `[0, 0, 0, 255]` (opaque
black). Reading returns a new copy; writing stores a copy. Undef dies.

## letter\_spacing

```perl
$label->letter_spacing(1);
```

Extra space between characters, an integer from 0 to 65535. Default
`0`.

## line\_height

```perl
$label->line_height(20);
```

The height of one line, an integer from 0 to 65535. Default `0`,
which means: use the height `measure_text` returns. With a
`line_height` larger than that height, Clay moves each line's text box
down by half the difference, so the box of the last line reaches below
the element; renderers should centre the glyphs in the box.

## wrap\_mode

```perl
$label->wrap_mode(CLAY_TEXT_WRAP_NEWLINES);
$label->wrap_mode(undef);                      # Clay's default
```

How the text wraps: `CLAY_TEXT_WRAP_WORDS` (at spaces and newlines),
`CLAY_TEXT_WRAP_NEWLINES` (only at newlines) or `CLAY_TEXT_WRAP_NONE`
(meant to never wrap; see below). Default undef: the setting is left out and Clay uses
`CLAY_TEXT_WRAP_WORDS`.

In the Clay version this distribution ships, `CLAY_TEXT_WRAP_NONE`
behaves like `CLAY_TEXT_WRAP_NEWLINES`: it still breaks lines at
`"\n"`, although Clay describes it as disabling wrapping.

## text\_alignment

```perl
$label->text_alignment(CLAY_TEXT_ALIGN_RIGHT);
```

How wrapped lines are aligned inside the text element:
`CLAY_TEXT_ALIGN_LEFT`, `CLAY_TEXT_ALIGN_CENTER` or
`CLAY_TEXT_ALIGN_RIGHT`. Default undef: the setting is left out and
Clay uses `CLAY_TEXT_ALIGN_LEFT`. To place the whole text element
inside its parent, use the parent's `child_alignment` (see
["layout" in Clay::UI::Role::Layout::HasLayout](Role/Layout/HasLayout.md#layout)).

# METHODS

## text\_config

```perl
my $config = $label->text_config;
# { font_id => 0, font_size => 16, text_color => [0, 0, 0, 255],
#   letter_spacing => 0, line_height => 0 }
```

Returns the text settings the layout pass (the part of
["render" in Clay::UI](../UI.md#render) that declares the tree to Clay) passes to Clay: a
new hashref with the snake\_case keys above. `wrap_mode` and
`text_alignment` are included only when they are set. The
`text_color` inside is a new copy as well, so changing the result
changes nothing in the widget. This is the method
[Clay::UI::Role::Core::TextNode](Role/Core/TextNode.md) requires.

# SEE ALSO

[Clay::UI::Role::Core::TextNode](Role/Core/TextNode.md), ["new" in Clay::UI](../UI.md#new) (`measure_text`),
["Clay\_TextElementConfig" in Clay::XS::Structs](../XS/Structs.md#clay_textelementconfig), [Clay::UI::Box](Box.md).
