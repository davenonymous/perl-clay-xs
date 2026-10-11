# NAME

Clay::UI::\_keys - internal snake\_case and camelCase key translator

# DESCRIPTION

Pure helper used by the [Clay::UI](../UI.md) high-level layer. Widgets store
Clay values with `snake_case` keys whatever spelling the caller used
(`snake_keys`, run where attributes are set), and the layout pass
rewrites them to the `camelCase` field names the underlying
[Clay::XS](../XS.md) binding expects (`camelize_keys`).

This module is internal. The API is not part of the public contract.

# FUNCTIONS

## camelize\_string($key)

Returns the camelCase form of a snake\_case string. Keys containing no
underscore are returned unchanged.

## snake\_string($key)

Returns the snake\_case form of a camelCase string, the inverse of
`camelize_string` for keys Clay uses (`childGap` becomes `child_gap`).
Used by `snake_keys` and to report Clay paths in the spelling widgets
store.

## camelize\_keys($node)

Recurses through hashes and arrays, returning a new structure in which
every hash key has been camelized. Blessed references, coderefs, and
scalars pass through untouched. Throws if two source keys would collide
after camelization (for example, both `backgroundColor` and
`background_color` in the same hash).

## snake\_keys($node, $where)

The mirror of `camelize_keys`: returns a new structure in which every
hash key is in snake\_case (`childGap` becomes `child_gap`), with the
same traversal rules. Throws if two source keys would collide after the
conversion; the message names `$where` (optional, for example the
attribute name) and the path below it.
