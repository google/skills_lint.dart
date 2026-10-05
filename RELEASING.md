# Releasing skills_lint

> [!CAUTION]
> Never push a tag to test a release. `.github/workflows/publish.yaml`
> publishes every tag that matches `skills_lint-v*`, including `-rc` tags, to
> pub.dev, and
> [a version published to pub.dev can't be removed](https://dart.dev/tools/pub/publishing#remember-publishing-is-forever).
> Test the release workflow with a [dry run](#dry-run) instead.

A release starts when a maintainer pushes the tag `skills_lint-v<version>`.
The version must match `version` in `packages/skills_lint/pubspec.yaml`, and
`CHANGELOG.md` must have a `## <version>` section. The tag starts two
workflows:

- `publish.yaml` publishes the package to pub.dev.
- `release.yaml` builds the `skills_lint` executable for each
  [target](#targets) and publishes a GitHub Release with:
  - `skills_lint-<target>.tar.gz` for each target. Each archive holds the
    executable and a `LICENSE` file with the notices for everything compiled
    into it.
  - `SHA256SUMS`, the checksums that `install.sh` checks.
  - `install.sh`.
  - Build provenance attestations for the archives. Users check them with
    `gh attestation verify <archive> -R google/skills_lint.dart`.

The release notes are the version's `CHANGELOG.md` section. The workflow
creates the release as a draft, attaches the files, then publishes it, which
is the order that
[immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
need. If the workflow fails after it creates the draft, delete the draft
before you run it again.

## Targets

| Target | Runner | Runs on |
| :--- | :--- | :--- |
| `macos-arm64` | `macos-latest` | macOS 14 or later, Apple silicon |
| `macos-x64` | `macos-15-intel` | macOS 14 or later, Intel |
| `linux-x64` | `ubuntu-latest` | Linux x64 |

The build matrix in `release.yaml`, `supportedTargets` in
`release/lib/src/archive.dart` and `SUPPORTED_TARGETS` in
`packages/skills_lint/scripts/install.sh` list the same targets.

`dart compile exe` builds for the machine it runs on, so each target builds on
its own runner.

The minimum macOS version comes from the Dart SDK used for the build: Dart
3.11 and later target macOS 14
([sdk change 468883](https://dart-review.googlesource.com/c/sdk/+/468883)),
so a Dart upgrade can raise it. It is the `minos` of the `LC_BUILD_VERSION`
load command in the built executable, which `vtool -show-build <executable>`
prints. `release package` fails if that value differs from
`macosMinimumVersion` in `release/lib/src/macho.dart`. When it changes, update
that constant, `MIN_MACOS_VERSION` in `install.sh`, the README and this file.

There is no Windows executable yet; see
[issue #86](https://github.com/google/skills_lint.dart/issues/86).

## Release scripts

The workflow steps run the `release` command of the `skills_lint_release`
package in `release/`. It is a workspace package that is never published, so
its dependencies stay out of `skills_lint`. Run it from `release/`:

```bash
dart run bin/release.dart --help
```

| Command | What it does |
| :--- | :--- |
| `package` | Compiles the executable for this machine, runs it, packages it with its license notices, checks the archive and writes its `.sha256` file. |
| `licenses` | Writes the license notices for the executable. |
| `checksums` | Checks each `.sha256` file in a directory and merges them into `SHA256SUMS`. |
| `prepare` | Checks the tag against the `pubspec.yaml` version, prints the release as `NAME=value` lines for `$GITHUB_ENV`, and writes the release notes. |

Pull requests that change `release.yaml`, `release/`, `install.sh` or a
`pubspec.yaml` run the release script tests and the build jobs, and upload the
archives as workflow artifacts. They don't create a release.

When the workflow moves to a new Dart SDK, check the Dart runtime licenses
described in
[`release/dart_runtime_licenses/README.md`](release/dart_runtime_licenses/README.md),
and the macOS minimum above.

## Dry run

To test the release workflow without releasing, run it by hand from the
Actions tab, or with:

```bash
gh workflow run release.yaml -R google/skills_lint.dart --ref <branch>
```

A dry run builds every archive and creates a draft release named for the
`pubspec.yaml` version, with the tag `dry-run-<version>-<run ID>`. A draft
doesn't create its tag, so a dry run never pushes a tag, and the workflow
never publishes a dry run. Check the draft's files, then delete it from the
releases page or with `gh release delete <tag> -R google/skills_lint.dart`.
Don't publish it.
