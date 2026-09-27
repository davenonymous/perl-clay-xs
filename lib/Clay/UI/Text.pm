package Clay::UI::Text;

use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use Object::Pad 0.800;

use Clay::UI::_validate qw(optional required validate_text validate_number validate_color validate_enum);
use Clay::UI::Role::Core::TextNode;

our $VERSION = '0.01';

role Clay::UI::Text :does(Clay::UI::Role::Core::TextNode) {
	field $text :param = '';

	field $font_id         :param = 0;
	field $font_size       :param = 16;
	field $text_color      :param = [0, 0, 0, 255];
	field $letter_spacing  :param = 0;
	field $line_height     :param = 0;
	field $wrap_mode       :param = undef;
	field $text_alignment  :param = undef;

	ADJUST {
		$text           = required(\&validate_text,   text           => $text);
		$font_id        = required(\&validate_number, font_id        => $font_id);
		$font_size      = required(\&validate_number, font_size      => $font_size);
		$text_color     = required(\&validate_color,  text_color     => $text_color);
		$letter_spacing = required(\&validate_number, letter_spacing => $letter_spacing);
		$line_height    = required(\&validate_number, line_height    => $line_height);
		$wrap_mode      = optional(\&validate_enum,   wrap_mode      => $wrap_mode);
		$text_alignment = optional(\&validate_enum,   text_alignment => $text_alignment);
	}

	method text (@new) {
		return $text unless @new;
		return $text = required(\&validate_text, text => @new);
	}

	method font_id (@new) {
		return $font_id unless @new;
		return $font_id = required(\&validate_number, font_id => @new);
	}

	method font_size (@new) {
		return $font_size unless @new;
		return $font_size = required(\&validate_number, font_size => @new);
	}

	method text_color (@new) {
		return $text_color unless @new;
		return $text_color = required(\&validate_color, text_color => @new);
	}

	method letter_spacing (@new) {
		return $letter_spacing unless @new;
		return $letter_spacing = required(\&validate_number, letter_spacing => @new);
	}

	method line_height (@new) {
		return $line_height unless @new;
		return $line_height = required(\&validate_number, line_height => @new);
	}

	method wrap_mode (@new) {
		return $wrap_mode unless @new;
		return $wrap_mode = optional(\&validate_enum, wrap_mode => @new);
	}

	method text_alignment (@new) {
		return $text_alignment unless @new;
		return $text_alignment = optional(\&validate_enum, text_alignment => @new);
	}

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

Clay::UI::Text - text-leaf widget role for Clay::UI

=head1 SYNOPSIS

	use Object::Pad;
	use Clay::UI::Text;

	class My::Label :strict(params) :does(Clay::UI::Text) {}

	my $label = My::Label->new(
		text       => 'Hello, world!',
		font_size  => 18,
		text_color => [255, 255, 255, 255],
	);

=head1 DESCRIPTION

Text widgets are leaves: the walker calls Clay's
C<Clay__OpenTextElement> rather than the normal open / configure /
close trio, and text nodes cannot have children. C<Clay::UI::Text>
is a role that composes L<Clay::UI::Role::Core::TextNode> so the walker
can detect text nodes via C<DOES>. Consume it from a concrete class to
get an instantiable label widget.

The text-measurement callback installed via
C<Clay::XS::Clay_SetMeasureTextFunction> is responsible for
returning the rendered width / height for the C<font_id> + C<font_size>
combination.

=head1 PARAMETERS

=over 4

=item C<text> (default C<''>)

=item C<font_id> (default C<0>)

=item C<font_size> (default C<16>)

=item C<text_color> (default C<[0, 0, 0, 255]>)

=item C<letter_spacing> (default C<0>)

=item C<line_height> (default C<0>; Clay treats 0 as "use font_size")

=item C<wrap_mode>, C<text_alignment> (omitted from the config unless set)

=back

All keys are snake_case; the walker camelizes before handing them to
L<Clay::XS>.

Every parameter above is also a read/write accessor: call with no argument
to read, with one argument to write (e.g. C<< $label->text('new') >>,
C<< $label->font_size(20) >>). A write takes effect on the next C<render>.
Values are validated when set: C<text> must be a defined string, the
numeric parameters numbers, C<text_color> a colour, and C<wrap_mode> /
C<text_alignment> one of the C<CLAY_TEXT_WRAP_*> / C<CLAY_TEXT_ALIGN_*>
constants; anything else dies, naming the parameter. Text is characters
(any Unicode).

=cut
