package Clay::UI::_keys;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Scalar::Util qw(blessed reftype);
use Exporter 'import';

our $VERSION   = '0.01';
our @EXPORT_OK = qw(camelize_keys camelize_string);

sub camelize_string ($key) {
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

sub camelize_keys ($node) {
	return $node unless ref $node;
	return $node if blessed $node;

	my $type = reftype $node;

	if ($type eq 'HASH') {
		my %out;
		for my $key (keys %$node) {
			my $new_key = camelize_string($key);
			if ($new_key ne $key && exists $node->{$new_key}) {
				die "Clay::UI: key '$key' camelizes to '$new_key', which is already present in the same hash";
			}
			if (exists $out{$new_key}) {
				die "Clay::UI: key '$key' collides with another key that camelized to '$new_key'";
			}
			$out{$new_key} = camelize_keys($node->{$key});
		}
		return \%out;
	}

	if ($type eq 'ARRAY') {
		return [ map { camelize_keys($_) } @$node ];
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
L<Clay::Layout> binding receives the C-style field names it expects.

This module is internal. The API is not part of the public contract.

=head1 FUNCTIONS

=head2 camelize_string($key)

Returns the camelCase form of a snake_case string. Keys containing no
underscore are returned unchanged.

=head2 camelize_keys($node)

Recurses through hashes and arrays, returning a new structure in which
every hash key has been camelized. Blessed references, coderefs, and
scalars pass through untouched. Throws if two source keys would collide
after camelization (for example, both C<backgroundColor> and
C<background_color> in the same hash).

=cut
