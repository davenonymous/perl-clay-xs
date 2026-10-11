# NAME

Clay::UI::Role::Core::Stateful - require an explicit id on a Clay::UI widget

# SYNOPSIS

```perl
use v5.22;
use Object::Pad;
use Clay::UI::Role::Core::Stateful;

class My::Tracked :strict(params) :does(Clay::UI::Role::Core::Stateful) {}

my $panel = My::Tracked->new(id => 'main-panel');    # ok
eval { My::Tracked->new } or warn $@;               # dies: no id
```

# DESCRIPTION

`Clay::UI::Role::Core::Stateful` extends
[Clay::UI::Role::Core::Element](Element.md) and makes the `id` constructor
parameter mandatory. Compose it for widgets whose Clay element needs
the same id in every frame because Clay keeps state for it between
frames. [Clay::UI::Role::Layout::HasScroll](../Layout/HasScroll.md) composes it: Clay stores a
scroll container's scroll position under its element id. Without an
`id` a widget gets an id derived from its position (see
["resolve\_id" in Clay::UI::Role::Core::Element](Element.md#resolve_id)), which changes when the
widget moves.

Hover, press and focus do not need an id: [Clay::UI::Interaction](../../Interaction.md)
tracks widgets by reference.

The role adds no methods. The constructor dies with
`Clay::UI::Role::Core::Stateful: widget 'My::Tracked' requires an explicit 'id'`
when `id` is missing or undef.

# SEE ALSO

["id" in Clay::UI::Role::Core::Element](Element.md#id),
[Clay::UI::Role::Layout::HasScroll](../Layout/HasScroll.md).
