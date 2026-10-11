# NAME

Clay::UI::\_validate - internal attribute validation for Clay::UI widgets

# DESCRIPTION

Functions the widget roles call from their constructors and accessors,
so a bad attribute dies where it is set instead of when the tree is
rendered. `optional` and `required` wrap a validator for the
one-argument write of an accessor (`optional` accepts undef). Each
validator takes the attribute name (used in the message) and the value,
dies with `Clay::UI: '<name>' ...` when the value is wrong, and
otherwise returns the value: the Clay validators return a deep copy
(`copy_value`) with snake\_case keys (`snake_keys`), so a widget never
shares a hash or array with the caller that passed it and stores one
spelling of every key, and accessors return copies of what they hold.
Objects with overloading (value objects such as [Math::BigInt](https://metacpan.org/pod/Math%3A%3ABigInt)
numbers) are kept as they are.

Clay values are checked by ["CHECKING STRUCTS" in Clay::XS](../XS.md#checking-structs):
`clay_struct($type)` returns a validator for a whole struct (for
example `Clay_LayoutConfig`), `clay_field($type, $field)` one for a
single field of it (for example `fontSize` of
`Clay_TextElementConfig`). Keys may be snake\_case or camelCase and are
stored in snake\_case; both spellings of one key in a hash die. Errors
name the attribute and the snake\_case path inside it, e.g.
`Clay::UI: 'layout.padding.left' expected an integer in 0..65535, got '-5'`,
and list the known keys for an unknown one.

The other validators hold Clay::UI's own rules: element ids must not
start with `anon:`, user sizing-group ids must stay at or below
`USER_GROUP_ID_MAX` (`2**20 - 1`; [Clay::UI::Grid](Grid.md) packs its own ids
above it), text must be a defined string, and `border_width` may also
be a single number.

`is_finite_number` is true for a plain number that is neither NaN nor
infinite. `copy_value` deep-copies hashes and arrays (blessed ones
into plain data) and keeps scalars and objects with overloading as they
are.

This module is internal. The API is not part of the public contract.
