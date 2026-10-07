# Releasing skills_lint

One workflow, `.github/workflows/release.yaml`, publishes the package to
pub.dev and the `skills_lint` executables as a GitHub Release. Pushing a tag
doesn't start a release.

## Release a version

1. In a pull request, set `version` in `packages/skills_lint/pubspec.yaml` to
   the version to release, without `-wip`, and give `CHANGELOG.md` a
   `## <version>` section.
2. After it merges, open **Actions > Release > Run workflow**, pick `main`,
   check **release**, and run it. Or run:

   ```bash
   gh workflow run release.yaml -R google/skills_lint.dart --ref main -f release=true
   ```

The run on `main` first checks that `pubspec.yaml` and `CHANGELOG.md` are
ready to publish. Beyond what pub.dev and Homebrew require, it enforces this
repository's release standards
([`release_info.dart`](release/lib/src/release_info.dart),
[`release_notes.dart`](release/lib/src/release_notes.dart)):

- The version is a release version, not `-wip`.
- The version holds only letters, digits, `.`, `+` and `-`.
- `CHANGELOG.md` has a `## <version>` section with entries. They become the
  release notes.
- The run is on `main`.

It then resolves the dependencies once, tests the release scripts, builds each
[target](#targets) with those dependencies and runs
`dart pub publish --dry-run`. Then it:

1. Creates the tag `skills_lint-v<version>` at the commit it built.
2. Creates a draft GitHub Release for the tag with:
   - `skills_lint-<target>.tar.gz` for each target. Each archive holds the
     executable and a `LICENSE` file with the notices for everything compiled
     into it.
   - `SHA256SUMS`, the checksums that `install.sh` checks.
   - `install.sh`, which installs this version unless `VERSION` is set.
   - `pubspec.lock`, the [dependency versions](#dependencies) of the build.
   - Build provenance attestations for all of these files. To check that a
     run of `release.yaml` on `main` built a file, run:

     ```bash
     gh attestation verify <file> -R google/skills_lint.dart \
       --signer-workflow google/skills_lint.dart/.github/workflows/release.yaml \
       --source-ref refs/heads/main
     ```

3. Starts `release.yaml` again on the tag.

The run on the tag:

1. Checks that the draft holds `install.sh` and every file that `SHA256SUMS`
   lists, unchanged, and that each file passes the attestation check above.
2. Waits for a [reviewer to approve](#approve-the-pubdev-deployment) the
   `pub` job's deployment to the `pub.dev` environment, then publishes the
   package to pub.dev, unless pub.dev has the version.
3. Checks the attestations of the draft's files again, then publishes the
   draft release.

pub.dev accepts a publish only from a workflow run on a tag that matches
`skills_lint-v{{version}}`, so publishing needs the second run. The comment on
the `pub` job in `release.yaml` lists the pub.dev and repository settings
that the run depends on.

If the `pub.dev` environment is ever re-created, re-add its required reviewer
and its `skills_lint-v*` tag rule. GitHub re-creates a deleted environment
without them, and pub.dev checks only the name. The run on `main` fails
until the environment has them.

A version with a suffix, such as `1.0.0-dev.1`, is released as a prerelease.
The README's
install command downloads from `releases/latest`, and
[the latest release](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
is the most recent release that is not a prerelease or a draft.

### Approve the pub.dev deployment

The run on the tag pauses at the `pub` job until a required reviewer of the
`pub.dev` environment approves it under **Review deployments** on the run's
page in the Actions tab. Approve it only if the run builds a commit on `main`
that a merged pull request reviewed. Check the commit of the run, not the tag:
the tag can move after the run starts. `<run-id>` is the number after `/runs/` in
the run's URL.

```bash
sha="$(gh run view <run-id> -R google/skills_lint.dart --json headSha --jq .headSha)"
git fetch origin main
git merge-base --is-ancestor "$sha" origin/main && echo "on main"
gh pr list -R google/skills_lint.dart --state merged --search "$sha"
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

- **The run on `main` fails.** Fix the cause and run it again. It reuses the
  tag if the tag points at the same commit. If `main` moved on, delete the
  tag first with `git push --delete origin skills_lint-v<version>`.
  The run stops if the version has a release, even a draft, because a run on
  the tag may be waiting to publish that draft. If the failed run created the
  draft but didn't start the run on the tag, start that run as below instead.
  To build the draft again, check that no run on the tag is queued, waiting or
  in progress, then delete the draft:

  ```bash
  gh run list -R google/skills_lint.dart --workflow release.yaml --branch skills_lint-v<version>
  gh release delete skills_lint-v<version> -R google/skills_lint.dart
  ```

- **The run on the tag fails.** Fix the cause, then run the workflow on the
  tag with **release** checked:
  `gh workflow run release.yaml -R google/skills_lint.dart --ref skills_lint-v<version> -f release=true`.
  If pub.dev has the version already, the run skips it and publishes the
  draft.
- **To abandon a release** before pub.dev has it, delete the draft and the
  tag with
  `gh release delete skills_lint-v<version> --cleanup-tag -R google/skills_lint.dart`.
- **pub.dev has the version, but there is no GitHub release.** This happens
  if the draft was deleted while the run on the tag waited for approval. Find
  the commit that pub.dev got: it is the `headSha` of the run on the tag whose
  `pub` job succeeded.

  ```bash
  gh run list -R google/skills_lint.dart --workflow release.yaml --branch skills_lint-v<version> \
    --json databaseId,headSha,conclusion
  ```

  If that commit is still the head of `main`, run the release on `main`
  again. Its run on the tag skips pub.dev, which has the version, and
  publishes the GitHub release. Otherwise don't build executables for the
  version from another commit, because they would not match the package on
  pub.dev. Keep the tag at that commit and release the next version, with a
  `CHANGELOG.md` entry that says the skipped version has no executables.

The workflow creates the release as a draft, attaches the files, then
publishes it, which is the order that
[immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
need.

## Targets

`releaseTargets` in
[`release/lib/src/archive.dart`](release/lib/src/archive.dart) is the one
list of targets, with the runner that builds each. `dart compile exe` builds
for the machine it runs on, so each target builds on a runner of its own
platform. The rest follows from that list:

- `prepare` prints the `build` job's matrix from it.
- `release package --target` accepts only its targets.
- `install.sh` finds the archive for the machine in the release's
  `SHA256SUMS`, and names the release's platforms when there is none.

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
| `package` | Compiles the executable for this machine, runs it, checks that `--version` prints the `pubspec.yaml` version, packages it with its license notices, checks the archive and writes its `.sha256` file. |
| `checksums` | Checks each `.sha256` file in a directory and merges them into `SHA256SUMS`. |
| `install-script` | Writes `install.sh` with the `pubspec.yaml` version as the version it installs by default. |
| `licenses` | Writes the license notices for the executable. |

When the workflow moves to a new Dart SDK, check the Dart runtime licenses
described in
[`release/dart_runtime_licenses/README.md`](release/dart_runtime_licenses/README.md),
and the macOS minimum above.

## Dependencies

The repository has no checked-in `pubspec.lock`. In a dry run and in the run
on `main`, the `prepare` job resolves the workspace's dependencies once with
`dart pub get` and passes the resulting `pubspec.lock` to the other jobs. The
run on the tag passes on the `pubspec.lock` from the draft release instead.
Each job runs `dart pub get --enforce-lockfile`, which fails if a package's
content hash differs from the lockfile, so every job and every executable in a
release uses the same dependency versions.

The release ships that `pubspec.lock` as an attested asset. To rebuild a
release with its dependency versions, check out its tag, download its
`pubspec.lock` to the repository root and run
`dart pub get --enforce-lockfile`.

## Dry run

A dry run tests the release scripts, builds every archive, writes
`SHA256SUMS` and `install.sh`, runs `dart pub publish --dry-run`, and uploads
the files as the `release-assets` workflow artifact. It creates no tag, no
release and no pub.dev version.

Pull requests that change `release.yaml`, `release/`, `install.sh` or
`packages/skills_lint/pubspec.yaml` run a dry run. To run one by hand, run the
workflow on any branch with **release** unchecked:

```bash
gh workflow run release.yaml -R google/skills_lint.dart --ref <branch>
```
