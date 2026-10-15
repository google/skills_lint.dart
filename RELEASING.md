# Releasing skills_lint

## How to release

1. Merge a pull request that sets the version to release, without `-wip`, in
   `packages/skills_lint/pubspec.yaml` and
   `packages/skills_lint/lib/src/version.dart`, and adds a `## <version>`
   section to `CHANGELOG.md`.
2. Run **Actions > Build and tag a release** on `main` with that version, or
   `gh workflow run release_build_and_tag.yaml -R google/skills_lint.dart --ref main -f version=<version>`.
   It checks and builds everything, tags `skills_lint-v<version>`, creates a
   draft release and starts **Publish a tagged release** on the tag.
3. In that run, approve **Publish 1 of 2: package to pub.dev** once the
   **Verify** job's summary shows your version, its build run and the pull
   request that merged it, and only after checking, outside the run, that
   the run's commit is on `main`. The workflow at the run's commit writes
   that summary, so a run on a tag that someone put on another commit can
   show anything. `<sha>` is the commit the run shows;
   `gh api repos/google/skills_lint.dart/compare/main...<sha> --jq .status`
   prints `identical` or `behind` when it is on `main`. pub.dev, then the
   GitHub release, are published.
4. Follow the link in the **Homebrew** job's summary to open the formula's
   pull request.

To try the build without releasing, run it on any branch without a version:
`gh workflow run release_build_and_tag.yaml -R google/skills_lint.dart --ref <branch>`.
Pull requests that change the release run this dry run too.

## After the release

- Merge the formula's pull request once all of its checks pass.
- Then merge a pull request that sets the next `-wip` version in
  `pubspec.yaml` and `version.dart`, adds a `## <version>-wip` section to
  `CHANGELOG.md`, and sets the released version in the `^<version>` and
  `VERSION="<version>"` lines of `packages/skills_lint/README.md`, which no
  test checks.
- Bumping before the formula's pull request merges fails the repo tests: the
  formula's placeholder version must be the pubspec version without `-wip`.

## One-time setup

- On [pub.dev's admin page](https://pub.dev/packages/skills_lint/admin),
  automated publishing from GitHub Actions is on for this repository, from
  `workflow_dispatch` runs only, with the tag pattern
  `skills_lint-v{{version}}` and the environment `pub.dev`.
- The repository's `pub.dev` environment has a required reviewer and allows
  only `skills_lint-v*` tags. The required reviewers are the people who can
  approve publishing. GitHub re-creates a deleted environment without these
  rules, and pub.dev checks only its name, so re-add them if it is ever
  re-created. Until then, the **Plan** job fails.
- Immutable releases are on in the repository settings. **Publish 2 of 2**
  fails otherwise.
- The `main` ruleset (21051370) requires the `Homebrew` status check, so a
  formula that brew rejects can't merge.

## If a job fails

- **Plan**, a **Check** or a **Build** job: fix the problem on `main`, then
  run the build workflow again. For a flaky failure, use **Re-run failed
  jobs**.
- **Check: skills_lint tests at this commit / pana_score**: the pana score is
  below 160. Raise it on `main` with a pull request, then run the build
  workflow again.
- **Stage**: do what the error says, then **Re-run failed jobs**.
- **Download**, **Verify**, or **Publish 2 of 2** before it publishes:
  re-run the job once. If it fails again, delete the draft
  (`gh release delete skills_lint-v<version> -R google/skills_lint.dart`)
  and re-run **Stage**. The new publish run needs approval again, and skips
  pub.dev if pub.dev has the version.
- **Publish 1 of 2**: fix what the error names, then **Re-run failed jobs**.
  To give up on the version, delete the draft and release the next version.
- **Publish 2 of 2** after it publishes: re-run the job once. If it fails
  again, stop. Delete the release, tell the maintainers, and release the
  next version.
- **Homebrew**: **Re-run failed jobs**. It reuses the formula branch that an
  earlier attempt pushed, and fails if that branch holds another formula.
- The skills_lint repo test `homebrew_formula_test.dart` of the formula pull
  request, with "it is not what the template gives": the template changed on
  `main` after the tag. In `release/`, run
  `dart run bin/release.dart homebrew-formula --version <version> --sha256sums <the release's SHA256SUMS>`
  on the branch and push.

## What can be undone

- The tag: only an admin can move or delete it.
- The draft release: only people with push access see it, and they can
  delete it at any time.
- The pub.dev version: it is
  [never deleted or uploaded again](https://dart.dev/tools/pub/publishing#remember-publishing-is-forever),
  and it can be
  [retracted](https://dart.dev/tools/pub/publishing#retract-a-package-version)
  for 7 days.
- The GitHub release:
  [immutable](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).
  It can be deleted, but its tag can't be used again.
- The Homebrew pull request: revert it.

pub.dev goes first because it fails most often, and until it succeeds only
the tag is public.

## Expectations

- The build workflow creates the tag only after every check passed at its
  commit. The version and `CHANGELOG.md` rules are in
  [`release_info.dart`](release/lib/src/release_info.dart) and
  [`release_notes.dart`](release/lib/src/release_notes.dart).
- A version with a `-` suffix is a prerelease: no formula, and never
  [the latest release](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
  that the README's installer downloads. `0.5.4+1` is a release.
- Assets: `skills_lint-<target>.tar.gz` (the executable and a `LICENSE` with
  the notices for everything compiled into it), `SHA256SUMS`, `install.sh`,
  the build's `pubspec.lock`, and `skills_lint.rb` unless it is a
  prerelease. To rebuild a release, check out its tag, put its
  `pubspec.lock` at the repository root and run
  `dart pub get --enforce-lockfile`.
- Every asset is attested by the build of the tagged commit. To check one:
  `gh attestation verify <file> -R google/skills_lint.dart --signer-workflow google/skills_lint.dart/.github/workflows/release_build_and_tag.yaml --source-ref refs/heads/main --source-digest "$(gh api repos/google/skills_lint.dart/commits/skills_lint-v<version> --jq .sha)"`.

## Targets

`releaseTargets` in [`archive.dart`](release/lib/src/archive.dart) is the one
list of targets; each builds on a runner of its own platform. The macOS
minimum, macOS 14, comes from the Dart SDK
([sdk change 468883](https://dart-review.googlesource.com/c/sdk/+/468883)),
and `release package` fails, saying what to update, if a Dart upgrade raises
it. After a Dart upgrade, also check
[`dart_runtime_licenses`](release/dart_runtime_licenses/README.md). There is
no Windows executable yet ([#86](https://github.com/google/skills_lint.dart/issues/86)).

## Homebrew formula

`release homebrew-formula` generates [`Formula/skills_lint.rb`](Formula/skills_lint.rb)
from [`skills_lint.rb.tmpl`](release/templates/skills_lint.rb.tmpl); only the
version and each target's `url` and `sha256` are generated. Until a release
has executables, the checksums are placeholders and `brew install` fails. The
repo tests fail when the formula isn't what the template gives. Don't rename the tap
`google/skills-lint` or the formula `skills_lint`: published READMEs use them.
