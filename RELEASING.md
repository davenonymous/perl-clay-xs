# Releasing Clay-UI to CPAN

The `Clay-UI` dist ships both `Clay::XS` and `Clay::UI`. It uses plain
`ExtUtils::MakeMaker` plus
[`cpan-upload`](https://metacpan.org/pod/cpan-upload) (from
`CPAN::Uploader`). No Dist::Zilla, no Minilla, no surprises.

## One-time setup

```sh
cpanm CPAN::Uploader
```

`cpan-upload` reads your PAUSE credentials from `~/.pause`:

```text
user     YOURPAUSEID
password your-pause-password
```

Keep it private (`chmod 600 ~/.pause`). `make release` refuses to run
without it.

`make release` also reads the CI result of the release commit with the
GitHub CLI, so install [`gh`](https://cli.github.com/) and log in once
with `gh auth login`.

## Per-release checklist

1. Make sure the working tree is clean and on `master`:

   ```sh
   git status
   git pull --ff-only
   ```

2. Bump `$VERSION` in `lib/Clay/UI.pm` and `lib/Clay/XS.pm` (see
   "Notes on dependencies").

3. Bring the figures and their URLs up to date and commit what changed:

   ```sh
   make images
   ```

   `tools/make-images` lays out every figure in `images/` with Clay and
   draws it with Imager, runs the examples that write a PNG or a PDF,
   and fails when the POD shows a file it does not render, or does not
   show one that it renders. `make release` refuses to run while
   `make images-check` finds anything out of date. CI does not run
   `make images-check`: it compares the figures pixel by pixel, and the
   glyphs depend on the FreeType and DejaVu Sans of the machine.

   The POD shows the figures with
   `<img src="https://raw.githubusercontent.com/davenonymous/perl-clay-xs/vVERSION/images/NAME.png">`,
   because MetaCPAN shows images with relative paths as gray
   placeholders; the PDF is linked through its
   `https://github.com/davenonymous/perl-clay-xs/blob/vVERSION/images/`
   URL. `make images` sets `vVERSION` to the tag of the current
   `$Clay::UI::VERSION`, so each release on MetaCPAN shows its own
   figures once its tag is pushed (step 7). Keep `images/` in
   `MANIFEST`: the POD names the files in the dist for readers without
   HTML (`Figure: images/NAME.png in the distribution.`).

4. Sanity-build from a clean slate:

   ```sh
   make distclean 2>/dev/null || true
   perl Makefile.PL
   make
   make test
   ```

5. Commit the release, push it and wait for CI to pass on that commit.
   `make release` refuses to run on a dirty tree, so this has to happen
   first anyway:

   ```sh
   git commit -am "Release v$(perl -Ilib -MClay::UI -e 'print $Clay::UI::VERSION')"
   git push
   gh run watch --exit-status \
       "$(gh run list --workflow ci.yml --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId --jq '.[0].databaseId')"
   ```

   If `gh run list` finds no run yet, wait a few seconds: GitHub
   creates it shortly after the push. Upload only when every job is
   green, on every Perl and on Linux, macOS and Windows; `make release`
   refuses to upload otherwise. If one fails, fix the cause, commit,
   push and watch again.

6. Cut and upload the release:

   ```sh
   make release
   ```

   The `release` target:

   - Runs `make disttest` (builds the dist directory, configures it,
     and runs its tests - this is what catches missing `MANIFEST`
     entries before they reach CPAN).
   - Runs `make dist` to build the tarball (`disttest` alone does not
     create one) and refuses to upload if it is missing or contains
     build artefacts.
   - Refuses to proceed if the git working tree is dirty.
   - Refuses to proceed if a tag `v$(VERSION)` already exists.
   - Refuses to proceed unless the GitHub CI run of `HEAD` has passed
     (`make ci-check`, which needs an authenticated `gh`).
   - Refuses to proceed if a figure or an image URL is out of date
     (`make images-check`).
   - Runs `cpan-upload` on the freshly built tarball.

7. Tag and push:

   ```sh
   git tag -a "v$(perl -Ilib -MClay::UI -e 'print $Clay::UI::VERSION')" \
          -m "Release v$(perl -Ilib -MClay::UI -e 'print $Clay::UI::VERSION')"
   git push --follow-tags
   ```

   The tag must be annotated (`-a`): `git push --follow-tags` only
   pushes annotated tags, so a lightweight tag would silently stay
   local.

8. Wait ~1 hour, then verify on
   [MetaCPAN](https://metacpan.org/dist/Clay-UI).

## Recovery

- **Upload failed mid-way.** `cpan-upload` is idempotent against PAUSE
  re-uploads of the *same* tarball; just run `make release` again.
- **Uploaded a broken release.** You have 72 hours to delete it from
  PAUSE via the web UI (`https://pause.perl.org/` -> "Delete
  Files"). After that it's permanent in the BackPAN archive. Either
  way, **never reuse a version number** - bump and re-release.
- **Forgot to bump `$VERSION`.** The `release` target's "tag already
  exists" guard will catch this on the second run, but the tarball
  will already exist locally. Delete it (`rm Clay-UI-*.tar.gz`), bump
  the version, and start over.

## Notes on dependencies

- `lib/Clay/UI.pm` holds the dist version (`VERSION_FROM` in
  `Makefile.PL`), and the XS object is built with it. `lib/Clay/XS.pm`
  must carry the same `$VERSION`: `XSLoader::load` refuses to load an
  object built for another version. The other modules under `lib/`
  keep their own versions.
- `Makefile.PL` is the only place the dependencies are declared; there
  is no `cpanfile`.
- `make images` needs Imager with PNG and FreeType support,
  fontconfig's `fc-match` to find DejaVu Sans, and PDF::Builder for
  `examples/16-invoice-pdf.pl`. None of them is a prerequisite of the
  dist.
- Term::Fabulous depends on `Clay::UI` and installs it from GitHub
  until it is on CPAN. Release this dist first.
