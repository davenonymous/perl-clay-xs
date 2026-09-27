package Clay::UI::_validate;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Scalar::Util qw(looks_like_number);
use Exporter 'import';

use Clay::UI::_keys qw(camelize_string);

our $VERSION   = '0.01';
our @EXPORT_OK = qw(
	optional
	required
	validate_color
	validate_corner_radius
	validate_border_width
	validate_layout
	validate_floating
	validate_vector2
	validate_id
	validate_group_id
	validate_text
	validate_number
	validate_enum
	validate_flag
);

# -----------------------------------------------------------------------------
# Known keys, mirroring exactly what src/marshal.c reads for each struct.
# Keys are listed in snake_case; the camelCase spelling is accepted too.
# -----------------------------------------------------------------------------

sub _key_set (@snake) {
	return { map { ($_ => $_, camelize_string($_) => $_) } @snake };
}

my %KEYS = (
	layout          => _key_set(qw(sizing padding child_gap child_alignment layout_direction)),
	sizing          => _key_set(qw(width height)),
	sizing_axis     => _key_set(qw(type min max percent)),
	padding         => _key_set(qw(left right top bottom)),
	child_alignment => _key_set(qw(x y)),
	color           => _key_set(qw(r g b a)),
	corner_radius   => _key_set(qw(top_left top_right bottom_left bottom_right)),
	border_width    => _key_set(qw(left right top bottom between_children)),
	vector2         => _key_set(qw(x y)),
	dimensions      => _key_set(qw(width height)),
	floating        => _key_set(qw(offset expand parent_id z_index attach_points pointer_capture_mode attach_to clip_to)),
	attach_points   => _key_set(qw(element parent)),
);

# Largest value of each Clay enum the widgets expose.
my %ENUM_MAX = (
	layout_direction     => 1,    # CLAY_TOP_TO_BOTTOM
	child_alignment      => 2,    # CLAY_ALIGN_*_CENTER
	sizing_type          => 3,    # CLAY__SIZING_TYPE_FIXED
	attach_point         => 8,    # CLAY_ATTACH_POINT_RIGHT_BOTTOM
	pointer_capture_mode => 1,    # CLAY_POINTER_CAPTURE_MODE_PASSTHROUGH
	attach_to            => 3,    # CLAY_ATTACH_TO_ROOT
	clip_to              => 1,    # CLAY_CLIP_TO_ATTACHED_PARENT
	wrap_mode            => 2,    # CLAY_TEXT_WRAP_NONE
	text_alignment       => 2,    # CLAY_TEXT_ALIGN_RIGHT
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

# Checks that $hash only uses keys of the named table. Returns the hash.
sub _known_keys ($name, $hash, $table) {
	my @unknown = sort grep { !exists $KEYS{$table}{$_} } keys %$hash;
	_fail($name, "has unknown key" . (@unknown > 1 ? 's ' : ' ') . join(', ', map { "'$_'" } @unknown))
		if @unknown;
	return $hash;
}

sub _is_hash ($value) { ref $value eq 'HASH' }

# Numeric fields of a hash (or array) must be numbers.
sub _numeric_fields ($name, $hash) {
	for my $key (sort keys %$hash) {
		next unless defined $hash->{$key};
		_fail("$name.$key", 'must be a finite number') unless _is_number($hash->{$key});
	}
	return;
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

sub validate_number ($name, $value) {
	_fail($name, 'must be a finite number') unless _is_number($value);
	return $value;
}

sub validate_enum ($name, $value, $kind = $name) {
	my $max = $ENUM_MAX{$kind} // die "Clay::UI::_validate: unknown enum kind '$kind'";
	_fail($name, "must be one of the Clay constants 0..$max")
		unless _is_number($value) && $value == int($value) && $value >= 0 && $value <= $max;
	return $value;
}

sub validate_flag ($name, $value) {
	_fail($name, 'must be a plain boolean value') if ref $value;
	return $value;
}

sub validate_color ($name, $value) {
	my $shape = 'must be a colour: [r, g, b, a] or { r => ..., g => ..., b => ..., a => ... }';
	if (ref $value eq 'ARRAY') {
		_fail($name, $shape) unless @$value == 4;
		for my $index (0 .. 3) {
			_fail("$name\[$index\]", 'must be a finite number') unless _is_number($value->[$index]);
		}
		return $value;
	}
	_fail($name, $shape) unless _is_hash($value);
	_known_keys($name, $value, 'color');
	_numeric_fields($name, $value);
	return $value;
}

sub validate_corner_radius ($name, $value) {
	return validate_number($name, $value) unless ref $value;
	_fail($name, 'must be a number or a hashref with top_left, top_right, bottom_left, bottom_right')
		unless _is_hash($value);
	_known_keys($name, $value, 'corner_radius');
	_numeric_fields($name, $value);
	return $value;
}

sub validate_border_width ($name, $value) {
	return validate_number($name, $value) unless ref $value;
	_fail($name, 'must be a number or a hashref with left, right, top, bottom, between_children')
		unless _is_hash($value);
	_known_keys($name, $value, 'border_width');
	_numeric_fields($name, $value);
	return $value;
}

sub validate_vector2 ($name, $value) {
	return _pair($name, $value, 'vector2', 'x', 'y');
}

sub _pair ($name, $value, $table, @fields) {
	if (ref $value eq 'ARRAY') {
		_fail($name, "must be [" . join(', ', @fields) . "] or a hashref with " . join(', ', @fields))
			unless @$value == 2;
		for my $index (0, 1) {
			_fail("$name\[$index\]", 'must be a finite number') unless _is_number($value->[$index]);
		}
		return $value;
	}
	_fail($name, "must be [" . join(', ', @fields) . "] or a hashref with " . join(', ', @fields))
		unless _is_hash($value);
	_known_keys($name, $value, $table);
	_numeric_fields($name, $value);
	return $value;
}

sub _sizing_axis ($name, $axis) {
	_fail($name, 'must be a sizing hashref (use sizing_fit, sizing_grow, sizing_fixed or sizing_percent)')
		unless _is_hash($axis);
	_known_keys($name, $axis, 'sizing_axis');
	validate_enum("$name.type", $axis->{type}, 'sizing_type') if defined $axis->{type};
	for my $key (grep { defined $axis->{$_} } qw(min percent)) {
		validate_number("$name.$key", $axis->{$key});
	}
	if (defined $axis->{max}) {
		my $max = $axis->{max};
		_fail("$name.max", 'must be a number or +Inf')
			unless defined $max && !ref $max && looks_like_number($max) && $max == $max && $max != -9**9**9;
	}
	return;
}

sub validate_layout ($name, $value) {
	_fail($name, 'must be a hashref') unless _is_hash($value);
	_known_keys($name, $value, 'layout');
	for my $key (keys %$value) {
		my $field = $value->{$key};
		next unless defined $field;
		my $canonical = $KEYS{layout}{$key};
		my $path = "$name.$key";
		if ($canonical eq 'sizing') {
			_fail($path, 'must be a hashref with width and/or height') unless _is_hash($field);
			_known_keys($path, $field, 'sizing');
			for my $axis (grep { defined $field->{$_} } sort keys %$field) {
				_sizing_axis("$path.$axis", $field->{$axis});
			}
		} elsif ($canonical eq 'padding') {
			_fail($path, 'must be a hashref with left, right, top, bottom (padding_all(N) builds one)')
				unless _is_hash($field);
			_known_keys($path, $field, 'padding');
			_numeric_fields($path, $field);
		} elsif ($canonical eq 'child_alignment') {
			_fail($path, 'must be a hashref with x and/or y') unless _is_hash($field);
			_known_keys($path, $field, 'child_alignment');
			validate_enum("$path.$_", $field->{$_}, 'child_alignment') for grep { defined $field->{$_} } keys %$field;
		} elsif ($canonical eq 'layout_direction') {
			validate_enum($path, $field, 'layout_direction');
		} else {
			validate_number($path, $field);
		}
	}
	return $value;
}

sub validate_floating ($name, $value) {
	_fail($name, 'must be a hashref') unless _is_hash($value);
	_known_keys($name, $value, 'floating');
	for my $key (keys %$value) {
		my $field = $value->{$key};
		next unless defined $field;
		my $canonical = $KEYS{floating}{$key};
		my $path = "$name.$key";
		if ($canonical eq 'offset') {
			validate_vector2($path, $field);
		} elsif ($canonical eq 'expand') {
			_pair($path, $field, 'dimensions', 'width', 'height');
		} elsif ($canonical eq 'parent_id') {
			next if _is_hash($field) && _is_number($field->{id});
			_fail($path, 'must be an element id number or an element-id hash from Clay_GetElementId')
				unless _is_number($field);
		} elsif ($canonical eq 'attach_points') {
			_fail($path, 'must be a hashref with element and/or parent') unless _is_hash($field);
			_known_keys($path, $field, 'attach_points');
			validate_enum("$path.$_", $field->{$_}, 'attach_point') for grep { defined $field->{$_} } keys %$field;
		} elsif ($canonical eq 'z_index') {
			validate_number($path, $field);
		} else {
			validate_enum($path, $field, $canonical);
		}
	}
	return $value;
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

Pure functions the widget roles call from their constructors and
accessors, so a wrong-typed attribute dies where it is set instead of
when the tree is rendered. C<optional> and C<required> wrap a validator
for the one-argument write of an accessor (C<optional> accepts undef). Each function takes the attribute name (used
in the message) and the value, dies with
C<< Clay::UI: '<name>' ... >> when the value has the wrong shape or uses
a key Clay::XS does not read, and otherwise returns the value unchanged.

The known-key tables mirror exactly the fields F<src/marshal.c> reads,
in snake_case or camelCase. Numeric ranges (for example padding above
65535) are left to Clay::XS; the only range checked here is Clay::UI's
own: user sizing-group ids must stay below C<2**20>, the range
L<Clay::UI::Grid> reserves for its packed ids.

This module is internal. The API is not part of the public contract.

=cut
