package Clay::UI::Text;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::Role::Core::TextNode;

our $VERSION = '0.01';

class Clay::UI::Text :does(Clay::UI::Role::Core::TextNode) {
	field $text :param :reader;

	field $font_id         :param :reader = 0;
	field $font_size       :param :reader = 16;
	field $text_color      :param :reader = [0, 0, 0, 255];
	field $letter_spacing  :param :reader = 0;
	field $line_height     :param :reader = 0;
	field $wrap_mode       :param :reader = undef;
	field $text_alignment  :param :reader = undef;

	method text_config {
		my %cfg = (
			font_id        => $font_id,
			font_size      => $font_size,
			text_color     => $text_color,
			letter_spacing => $letter_spacing,
			line_height    => $line_height,
		);
		$cfg{wrap_mode}      = $wrap_mode      if defined $wrap_mode;
		$cfg{text_alignment} = $text_alignment if defined $text_alignment;
		return \%cfg;
	}
}

1;

__END__

=head1 NAME

Clay::UI::Text - text-leaf widget for Clay::UI

=head1 SYNOPSIS

	use Clay::UI::Text;

	my $label = Clay::UI::Text->new(
		text       => 'Hello, world!',
		font_size  => 18,
		text_color => [255, 255, 255, 255],
	);

=head1 DESCRIPTION

Text widgets are leaves: the walker calls Clay's
C<Clay__OpenTextElement> rather than the normal open / configure /
close trio, and text nodes cannot have children. C<Clay::UI::Text>
consumes L<Clay::UI::Role::Core::TextNode> so the walker can detect text
nodes via C<DOES>.

The text-measurement callback installed via
C<Clay::XS::Clay_SetMeasureTextFunction> is responsible for
returning the rendered width / height for the C<font_id> + C<font_size>
combination.

=head1 PARAMETERS

=over 4

=item C<text> (required)

=item C<font_id> (default C<0>)

=item C<font_size> (default C<16>)

=item C<text_color> (default C<[0, 0, 0, 255]>)

=item C<letter_spacing> (default C<0>)

=item C<line_height> (default C<0>; Clay treats 0 as "use font_size")

=item C<wrap_mode>, C<text_alignment> (omitted from the config unless set)

=back

All keys are snake_case; the walker camelizes before handing them to
L<Clay::XS>.

=cut
