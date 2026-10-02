package Clay::UI::_keys;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Scalar::Util qw(blessed reftype);
use Exporter 'import';

our $VERSION   = '0.01';
our @EXPORT_OK = qw(camelize_keys camelize_string snake_string);

# The walker camelizes every widget's config every frame, and the keys
# come from a small closed set (Clay's field names), so conversions are
# cached. The cache stops growing at a fixed size, so arbitrary keys (from
# a bad attribute value, say) cannot make it grow without bound.
my %camelized;
my $CAMELIZED_CACHE_MAX = 4096;

sub camelize_string ($key) {
	my $cached = $camelized{$key};
	return $cached if defined $cached;
	my $camel = _camelize($key);
	$camelized{$key} = $camel if keys %camelized < $CAMELIZED_CACHE_MAX;
	return $camel;
}

sub _camelize ($key) {
	return $key unless $key =~ /_/;
	my @parts = split /_/, $key, -1;
	my $head  = shift @parts;
	for my $part (@parts) {
		next unless length $part;
		my $first = substr($part, 0, 1);
		substr($part, 0, 1) = uc $first if $first =~ /[a-z]/;
	}
	return join '', $head, @parts;
}

sub snake_string ($key) {
	return $key =~ s/([A-Z])/_\l$1/gr;
}

sub camelize_keys ($node) {
	return $node unless ref $node;
	return $node if blessed $node;

	my $type = reftype $node;

	# Leaves are copied inline: this runs for every widget every frame.
	if ($type eq 'HASH') {
		my %out;
		for my $key (keys %$node) {
			my $new_key = $camelized{$key} // camelize_string($key);
			if ($new_key ne $key && exists $node->{$new_key}) {
				die "Clay::UI: key '$key' camelizes to '$new_key', which is already present in the same hash";
			}
			if (exists $out{$new_key}) {
				die "Clay::UI: key '$key' collides with another key that camelized to '$new_key'";
			}
			my $value = $node->{$key};
			$out{$new_key} = ref $value ? camelize_keys($value) : $value;
		}
		return \%out;
	}

	if ($type eq 'ARRAY') {
		return [ map { ref $_ ? camelize_keys($_) : $_ } @$node ];
	}

	return $node;
}

1;

__END__

=head1 NAME

Clay::UI::_keys - internal snake_case to camelCase translator

=head1 DESCRIPTION

Pure helper used by the L<Clay::UI> high-level layer. Recursively rewrites
hash keys from C<snake_case> to C<camelCase> so user-facing widget
declarations can use Perl-idiomatic naming while the underlying
L<Clay::XS> binding receives the C-style field names it expects.

This module is internal. The API is not part of the public contract.

=head1 FUNCTIONS

=head2 camelize_string($key)

Returns the camelCase form of a snake_case string. Keys containing no
underscore are returned unchanged.

=head2 snake_string($key)

Returns the snake_case form of a camelCase string, the inverse of
C<camelize_string> for keys Clay uses (C<childGap> becomes C<child_gap>).
Used to report Clay paths in the spelling Clay::UI users write.

=head2 camelize_keys($node)

Recurses through hashes and arrays, returning a new structure in which
every hash key has been camelized. Blessed references, coderefs, and
scalars pass through untouched. Throws if two source keys would collide
after camelization (for example, both C<backgroundColor> and
C<background_color> in the same hash).

=cut
