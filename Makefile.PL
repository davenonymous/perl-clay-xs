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
# enable a strict warning baseline; users who hit a portability issue on
# an exotic platform can override CCFLAGS in the environment.
# -----------------------------------------------------------------------------

my @ccflags = qw( -std=c99 -Wall -Wextra -Wno-unused-parameter );

# Clay's vendored header probes for SIMD support itself. If a user
# environment lacks the relevant intrinsics, they can run:
#   PERL_CLAY_DISABLE_SIMD=1 perl Makefile.PL
if ($ENV{PERL_CLAY_DISABLE_SIMD}) {
    push @ccflags, '-DCLAY_DISABLE_SIMD';
}

my $ccflags = join(' ', @ccflags);

WriteMakefile(
    NAME           => 'Clay::Layout',
    VERSION_FROM   => 'lib/Clay/Layout.pm',
    ABSTRACT_FROM  => 'lib/Clay/Layout.pm',
    AUTHOR         => 'Dave',
    LICENSE        => 'zlib',
    MIN_PERL_VERSION => '5.022',

    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '7.12',
    },
    PREREQ_PM => {
        'Exporter'    => '5.57',
        'XSLoader'    => 0,
        'Object::Pad' => '0.800',
    },
    TEST_REQUIRES => {
        'Test2::V0' => 0,
        'JSON::PP'  => 0,
    },

    # XS configuration.
    XS         => { 'Layout.xs' => 'Layout.c' },
    C          => [ 'Layout.c',
                    'src/clay_impl.c',
                    'src/clay_perl_context.c',
                    'src/marshal.c',
                    'src/callbacks.c' ],
    H          => [ 'src/clay_perl.h',
                    'src/clay/clay.h.orig' ],
    OBJECT     => '$(O_FILES)',

    INC        => '-I. -Isrc',
    CCFLAGS    => "$Config{ccflags} $ccflags",

    # Sanity: clean intermediate objects.
    clean      => { FILES => 'Layout.c Layout.o src/*.o src/clay/clay.h src/clay/.patched' },

    META_MERGE => {
        'meta-spec' => { version => 2 },
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
sub MY::postamble {
    return <<'POSTAMBLE';

# The pristine upstream Clay header lives in src/clay/clay.h.orig (tracked in
# git). The build copy at src/clay/clay.h is regenerated each time the pristine
# or any patch file changes: copy from .orig, then apply patches/*.patch in
# order. Both src/clay/clay.h and the .patched sentinel are gitignored so the
# working tree stays clean after a build.
src/clay/clay.h : src/clay/clay.h.orig patches/0001-clay-sizing-groups.patch
	cp src/clay/clay.h.orig src/clay/clay.h
	patch -p1 < patches/0001-clay-sizing-groups.patch
	@touch src/clay/.patched

src/clay_impl$(OBJ_EXT) : src/clay/clay.h
src/marshal$(OBJ_EXT) : src/clay/clay.h
src/callbacks$(OBJ_EXT) : src/clay/clay.h
src/clay_perl_context$(OBJ_EXT) : src/clay/clay.h
Layout$(OBJ_EXT) : src/clay/clay.h

src/%$(OBJ_EXT) : src/%.c
	$(CCCMD) $(CCCDLFLAGS) "-I$(PERL_INC)" $(PASTHRU_DEFINE) $(DEFINE) -o $@ $<

POSTAMBLE
}
