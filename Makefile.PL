use v5.22;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use ExtUtils::MakeMaker 7.12;
use Config;

# -----------------------------------------------------------------------------
# Compile flags.
#
# Clay requires C99 (or C++20, but we use C). We force the standard and
# enable a strict warning baseline (GCC/Clang flags). Users who hit a
# portability issue can override CCFLAGS on the command line
# (perl Makefile.PL CCFLAGS=...) or through PERL_MM_OPT.
# -----------------------------------------------------------------------------

my @ccflags = qw( -std=c99 -Wall -Wextra -Wno-unused-parameter );

# Clay's vendored header probes for SIMD support itself. If a user
# environment lacks the relevant intrinsics, they can run:
#   PERL_CLAY_DISABLE_SIMD=1 perl Makefile.PL
if ($ENV{PERL_CLAY_DISABLE_SIMD}) {
    push @ccflags, '-DCLAY_DISABLE_SIMD';
}

my $ccflags = join(' ', @ccflags);

# -----------------------------------------------------------------------------
# Clay patches.
#
# The pristine upstream Clay header lives in src/clay/clay.h.orig (tracked in
# git). The build copy at src/clay/clay.h is regenerated each time the pristine
# header or a patch changes; the patches apply in this order, each on top of
# the previous ones. The patched header is written to a temporary file and
# moved into place only when every patch succeeds, so a failed patch never
# leaves an up-to-date-looking, unpatched src/clay/clay.h behind.
# src/clay/clay.h is gitignored so the working tree stays clean after a build.
# -----------------------------------------------------------------------------

my @clay_patches = qw(
    patches/0001-clay-sizing-groups.patch
    patches/0002-clay-flow-layout.patch
    patches/0003-clay-back-to-front.patch
    patches/0004-clay-upstream-fixes.patch
);

WriteMakefile(
    NAME           => 'Clay::UI',
    VERSION_FROM   => 'lib/Clay/UI.pm',
    ABSTRACT_FROM  => 'lib/Clay/UI.pm',

    # The dist is Clay-UI, but the single XS module loads as Clay::XS
    # (see lib/Clay/XS.pm). XSMULTI places lib/Clay/XS.xs at the canonical
    # blib/arch/auto/Clay/XS/XS.so where XSLoader::load(__PACKAGE__) finds it.
    XSMULTI        => 1,
    XSBUILD        => {
        xs => {
            'lib/Clay/XS' => {
                OBJECT => 'lib/Clay/XS$(OBJ_EXT) '
                        . 'src/clay_impl$(OBJ_EXT) '
                        . 'src/clay_perl_context$(OBJ_EXT) '
                        . 'src/marshal$(OBJ_EXT) '
                        . 'src/callbacks$(OBJ_EXT)',
                INC    => '-I. -Isrc',
            },
        },
    },
    AUTHOR         => 'Dave',
    LICENSE        => 'zlib',
    MIN_PERL_VERSION => '5.022',

    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '7.12',
    },
    PREREQ_PM => {
        'Exporter'         => '5.57',
        'XSLoader'         => 0,
        'Object::Pad'      => '0.800',
        'Object::PadX::Enum' => '0.01',
    },
    TEST_REQUIRES => {
        'Test2::V0' => 0,
        'JSON::PP'  => 0,
    },

    C          => [ 'src/clay_impl.c',
                    'src/clay_perl_context.c',
                    'src/marshal.c',
                    'src/callbacks.c' ],
    H          => [ 'src/clay_perl.h',
                    'src/clay_impl_helpers.h',
                    'src/clay/clay.h.orig' ],

    CCFLAGS    => "$Config{ccflags} $ccflags",

    # Sanity: clean intermediate objects.
    clean      => { FILES => 'lib/Clay/XS.c lib/Clay/XS.o src/*.o src/clay/clay.h src/clay/clay.h.tmp*' },

    META_MERGE => {
        'meta-spec' => { version => 2 },
        # tools/make-images renders the figures in images/ that the
        # documentation shows; both are shipped but not installed.
        no_index    => { directory => [qw(tools images)] },
        resources   => {
            bugtracker => { web => 'https://github.com/dave/perl-clay-xs/issues' },
            repository => {
                type => 'git',
                url  => 'https://github.com/dave/perl-clay-xs.git',
                web  => 'https://github.com/dave/perl-clay-xs',
            },
        },
    },
);

# ExtUtils::MakeMaker's default `.c.o` suffix rule does not pass `-o $@`,
# so when a source file lives in a subdirectory the compiler still emits
# the .o into CWD instead of the matching subdirectory. Override the rule
# for our src/ tree so the object files land where O_FILES expects them.
# The rule for src/clay/clay.h is built from @clay_patches (see above).
sub MY::postamble {
    my $apply_patches = join '', map { "\tpatch src/clay/clay.h.tmp < $_\n" } @clay_patches;
    return "\nsrc/clay/clay.h : src/clay/clay.h.orig @clay_patches\n"
        . "\t\$(RM_F) src/clay/clay.h.tmp\n"
        . "\t\$(CP) src/clay/clay.h.orig src/clay/clay.h.tmp\n"
        . $apply_patches
        . "\t\$(MV) src/clay/clay.h.tmp src/clay/clay.h\n"
        . <<'POSTAMBLE';

src/clay_impl$(OBJ_EXT) : src/clay/clay.h
src/marshal$(OBJ_EXT) : src/clay/clay.h
src/callbacks$(OBJ_EXT) : src/clay/clay.h
src/clay_perl_context$(OBJ_EXT) : src/clay/clay.h
lib/Clay/XS$(OBJ_EXT) : src/clay/clay.h

src/%$(OBJ_EXT) : src/%.c
	$(CCCMD) $(CCCDLFLAGS) -I. -Isrc "-I$(PERL_INC)" $(PASTHRU_DEFINE) $(DEFINE) -o $@ $<

# --- Documentation figures -------------------------------------------
# Usage: make images         (after changing a figure or a pod reference)
#        make images-check   (fails when a figure or an image URL is stale)
#
# tools/make-images lays every figure in images/ out with the Clay::UI
# in blib/, draws it with Imager, runs the examples that write a PNG or
# a PDF, and points the image URLs in the pod to the tag of the current
# version on GitHub. It fails when the pod shows a file it does not
# render, or does not show one that it renders.

.PHONY: images images-check

images : pure_all
	$(FULLPERLRUN) -Mblib tools/make-images

images-check : pure_all
	$(FULLPERLRUN) -Mblib tools/make-images --check

POSTAMBLE
}
