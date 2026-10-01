package Clay::UI::_validate;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Scalar::Util qw(blessed looks_like_number);
use Exporter 'import';

use Clay::XS qw(check_struct);
use Clay::UI::_keys qw(camelize_keys snake_string);

our $VERSION   = '0.01';
our @EXPORT_OK = qw(
	optional
	required
	clay_struct
	clay_field
	validate_border_width
	validate_id
	validate_group_id
	validate_text
);

# User sizing-group ids stay below the range Clay::UI::Grid packs its own
# ids into (grid id << 20).
my $GROUP_ID_MAX = (1 << 20) - 1;

sub _fail ($name, $message) {
	die "Clay::UI: '$name' $message\n";
}

sub _is_number ($value) {
	return defined $value && !ref $value && looks_like_number($value)
		&& $value == $value && $value != 9**9**9 && $value != -9**9**9;
}

# Accessor helpers: apply $validator to the single value written to an
# attribute. optional() lets undef through (attribute unset); required()
# does not.
sub optional ($validator, $name, @value) {
	die "Clay::UI: '$name' takes one value\n" unless @value == 1;
	return undef unless defined $value[0];
	return $validator->($name, $value[0]);
}

sub required ($validator, $name, @value) {
	die "Clay::UI: '$name' takes one value\n" unless @value == 1;
	return $validator->($name, $value[0]);
}

# Validators for Clay values: check mode of Clay::XS (check_struct) does
# the checking, so the rules are exactly those Clay::XS applies when the
# value reaches Clay. clay_struct checks a whole struct, clay_field one
# field of it (named by its C name).
sub clay_struct ($type) {
	return sub ($name, $value) { _check($name, $type, $value) };
}

sub clay_field ($type, $field) {
	return sub ($name, $value) { _check($name, $type, $value, $field) };
}

# Runs check_struct on the camelized value and rethrows its error in
# Clay::UI's words: the attribute name plus the snake_case path inside it.
sub _check ($name, $type, $value, $field = undef) {
	_fail($name, 'must be defined') unless defined $value;
	my $input = defined $field ? { $field => $value } : camelize_keys($value);
	return $value if eval { check_struct($type, $input, $name); 1 };

	my $error = $@;
	die $error unless blessed $error && $error->isa('Clay::XS::StructError');

	my ($root, @inner) = @{ $error->path };
	shift @inner if defined $field;
	my $where = join '.', $root, map { snake_string($_) } @inner;

	if (my $unknown = $error->unknown_keys) {
		_fail($where, sprintf "has unknown key%s %s (known keys: %s)",
			@$unknown > 1 ? 's' : '',
			join(', ', map { "'" . snake_string($_) . "'" } @$unknown),
			join(', ', map { snake_string($_) } @{ $error->known_keys }));
	}
	my $message = 'expected ' . $error->expected . ', got ' . $error->got;
	$message .= ' (' . $error->hint . ')' if defined $error->hint;
	_fail($where, $message);
}

# A number applies to the four outer sides (Clay::UI::Role::Style::HasBorder
# expands it); anything else is a Clay_BorderWidth.
sub validate_border_width ($name, $value) {
	return _check($name, 'Clay_BorderWidth', $value, 'left') if defined $value && !ref $value;
	return _check($name, 'Clay_BorderWidth', $value);
}

sub validate_id ($name, $value) {
	_fail($name, 'must be a non-empty string')
		unless defined $value && !ref $value && length $value;
	_fail($name, "must not start with 'anon:' (reserved for the ids Clay::UI derives for widgets without one)")
		if index($value, 'anon:') == 0;
	return $value;
}

sub validate_group_id ($name, $value) {
	_fail($name, "must be an integer in 0..$GROUP_ID_MAX (larger ids are reserved for Clay::UI::Grid)")
		unless _is_number($value) && $value == int($value) && $value >= 0 && $value <= $GROUP_ID_MAX;
	return $value;
}

sub validate_text ($name, $value) {
	_fail($name, 'must be a defined string') unless defined $value && !ref $value;
	return $value;
}

1;

__END__

=head1 NAME

Clay::UI::_validate - internal attribute validation for Clay::UI widgets

=head1 DESCRIPTION

Functions the widget roles call from their constructors and accessors,
so a bad attribute dies where it is set instead of when the tree is
rendered. C<optional> and C<required> wrap a validator for the
one-argument write of an accessor (C<optional> accepts undef). Each
validator takes the attribute name (used in the message) and the value,
dies with C<< Clay::UI: '<name>' ... >> when the value is wrong, and
otherwise returns the value unchanged.

Clay values are checked by L<Clay::XS/CHECKING STRUCTS>:
C<clay_struct($type)> returns a validator for a whole struct (for
example C<Clay_LayoutConfig>), C<clay_field($type, $field)> one for a
single field of it (for example C<fontSize> of
C<Clay_TextElementConfig>). Keys may be snake_case or camelCase; errors
name the attribute and the snake_case path inside it, e.g.
C<Clay::UI: 'layout.padding.left' expected an integer in 0..65535, got
'-5'>, and list the known keys for an unknown one.

The other validators hold Clay::UI's own rules: element ids must not
start with C<anon:>, user sizing-group ids must stay below C<2**20> (the
range L<Clay::UI::Grid> reserves for its packed ids), text must be a
defined string, and C<border_width> may also be a single number.

This module is internal. The API is not part of the public contract.

=cut
