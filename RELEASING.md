# Releasing skills_lint

One workflow, `.github/workflows/release.yaml`, publishes the package to
pub.dev and the `skills_lint` executables as a GitHub Release. Pushing a tag
doesn't start a release.

## Release a version

1. In a pull request, set `version` in `packages/skills_lint/pubspec.yaml` to
   the version to release, without `-wip`, and give `CHANGELOG.md` a
   `## <version>` section. [Refresh the lockfile](#lockfile) in the same pull
   request.
2. After it merges, open **Actions > Release > Run workflow**, pick `main`,
   check **release**, and run it. Or run:

   ```bash
   gh workflow run release.yaml -R google/skills_lint.dart --ref main -f release=true
   ```

The run on `main` checks the version and `CHANGELOG.md`, tests the release
scripts, builds each [target](#targets) and runs `dart pub publish --dry-run`.
It refuses a `-wip` version, and runs only on `main`. Then it:

1. Creates the tag `skills_lint-v<version>` at the commit it built.
2. Creates a draft GitHub Release for the tag with:
   - `skills_lint-<target>.tar.gz` for each target. Each archive holds the
     executable and a `LICENSE` file with the notices for everything compiled
     into it.
   - `SHA256SUMS`, the checksums that `install.sh` checks.
   - `install.sh`, which installs this version unless `VERSION` is set.
   - Build provenance attestations for all of these files. Users check them
     with `gh attestation verify <file> -R google/skills_lint.dart`.
3. Starts `release.yaml` again on the tag.

The run on the tag:

1. Checks that the draft holds `install.sh` and every archive that
   `SHA256SUMS` lists, unchanged.
2. Waits for a [reviewer to approve](#approve-the-pubdev-deployment) the
   `pub` job's deployment to the `pub.dev` environment, then publishes the
   package to pub.dev, unless pub.dev has the version.
3. Publishes the draft release.

pub.dev accepts a publish only from a workflow run on a tag that matches
`skills_lint-v{{version}}`, so publishing needs the second run. The settings
that this depends on:

- The [pub.dev admin page](https://pub.dev/packages/skills_lint/admin)
  enables publishing from `workflow_dispatch` events and disables it from
  `push` events, so a pushed tag can't publish. **Require GitHub Actions
  environment** is checked, with **Environment** set to `pub.dev`.
- The repository has a GitHub Actions environment named `pub.dev` with a
  deployment rule that allows only tags matching `skills_lint-v*`, and a
  required reviewer. Administrators can bypass the reviewer. The `pub` job,
  which runs `dart pub publish`, is the only job in that environment.

The release notes are the version's `CHANGELOG.md` section. A version with a
suffix, such as `1.0.0-dev.1`, is released as a prerelease. The README's
install command downloads from `releases/latest`, and
[the latest release](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
is the most recent release that is not a prerelease or a draft.

### Approve the pub.dev deployment

The run on the tag pauses at the `pub` job until a required reviewer of the
`pub.dev` environment approves it under **Review deployments** on the run's
page in the Actions tab. Approve it only if the tag points at a commit on
`main` that a merged pull request reviewed:

```bash
git fetch origin main --tags
git merge-base --is-ancestor 'skills_lint-v<version>^{commit}' origin/main && echo "on main"
gh pr list -R google/skills_lint.dart --state merged --search "$(git rev-parse 'skills_lint-v<version>^{commit}')"
```

The `merge-base` line must print `on main`, and `gh pr list` must list the
pull request that merged the commit. Otherwise reject the deployment and
[abandon the release](#order-and-recovery).

No ruleset requires CI to pass before a pull request merges or before a
commit is released, and the release workflow's own jobs test only `release/`
and build the executables. Until
[#94](https://github.com/google/skills_lint.dart/issues/94) is fixed, also
check that the pull request's checks passed before approving:
`gh pr checks <number> -R google/skills_lint.dart`, with the number that
`gh pr list` printed.

### Order and recovery

pub.dev comes before the GitHub release, because
[a version published to pub.dev can't be removed](https://dart.dev/tools/pub/publishing#remember-publishing-is-forever)
and its OIDC setup is the step most likely to fail. The tag is public from
the run on `main` on, but the release stays a draft, which only maintainers
see, until the last job.

- **The run on `main` fails.** Fix the cause and run it again. It deletes a
  draft left by the failed run and reuses the tag if the tag points at the
  same commit. If `main` moved on, delete the tag first with
  `git push --delete origin skills_lint-v<version>`.
- **The run on the tag fails.** Fix the cause, then run the workflow on the
  tag with **release** checked:
  `gh workflow run release.yaml -R google/skills_lint.dart --ref skills_lint-v<version> -f release=true`.
  If pub.dev has the version already, the run skips it and publishes the
  draft.
- **To abandon a release** before pub.dev has it, delete the draft and the
  tag with
  `gh release delete skills_lint-v<version> --cleanup-tag -R google/skills_lint.dart`.

The workflow creates the release as a draft, attaches the files, then
publishes it, which is the order that
[immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
need.

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
| `prepare` | Works out whether the run is a dry run, creates the release, or publishes it; checks the version; prints the result as `name=value` lines for `$GITHUB_OUTPUT`; and writes the release notes. |
| `package` | Compiles the executable for this machine, runs it, packages it with its license notices, checks the archive and writes its `.sha256` file. |
| `checksums` | Checks each `.sha256` file in a directory and merges them into `SHA256SUMS`. |
| `install-script` | Writes `install.sh` with the `pubspec.yaml` version as the version it installs by default. |
| `licenses` | Writes the license notices for the executable. |

When the workflow moves to a new Dart SDK, check the Dart runtime licenses
described in
[`release/dart_runtime_licenses/README.md`](release/dart_runtime_licenses/README.md),
and the macOS minimum above.

## Lockfile

Release jobs get their dependencies from `release/workspace_pubspec.lock`, a
lockfile for the whole workspace. They copy it to `pubspec.lock` at the
repository root and run `dart pub get --enforce-lockfile`, which fails if the
lockfile doesn't satisfy every `pubspec.yaml` or a package's content hash
differs from the lockfile. The root `pubspec.lock` is not checked in, so other
CI jobs resolve the newest versions.

Refresh the lockfile before each release, and when a `pubspec.yaml` change
makes the release jobs fail. From the repository root:

```bash
dart pub upgrade
cp pubspec.lock release/workspace_pubspec.lock
```

Pull requests that change a `pubspec.yaml` or `release/` run the release jobs
with `--enforce-lockfile`, so a lockfile that no longer satisfies a
`pubspec.yaml` fails the pull request that causes it.

## Dry run

A dry run tests the release scripts, builds every archive, writes
`SHA256SUMS` and `install.sh`, runs `dart pub publish --dry-run`, and uploads
the files as the `release-assets` workflow artifact. It creates no tag, no
release and no pub.dev version.

Pull requests that change `release.yaml`, `release/`, `install.sh` or a
`pubspec.yaml` run a dry run. To run one by hand, run the workflow on any
branch with **release** unchecked:

```bash
gh workflow run release.yaml -R google/skills_lint.dart --ref <branch>
```
