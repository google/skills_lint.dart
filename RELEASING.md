# Releasing skills_lint

A release publishes the `skills_lint` package to pub.dev and the executables
as a GitHub release, then pushes a branch that updates the
[Homebrew formula](#homebrew-formula). Two workflows do it:

- **Build and tag a release**
  ([`release_build_and_tag.yaml`](.github/workflows/release_build_and_tag.yaml))
  runs every check, builds the assets, tags the release and creates a draft.
- **Publish a tagged release**
  ([`release_publish.yaml`](.github/workflows/release_publish.yaml)) runs on
  the tag. It checks that the draft is what the build made, then publishes.

## How to release

1. Merge a pull request that sets `version` in
   `packages/skills_lint/pubspec.yaml` to the version to release, without
   `-wip`, and adds a `## <version>` section to `CHANGELOG.md`.
2. Open **Actions > Build and tag a release > Run workflow**, pick `main`,
   enter that version and run it, or run
   `gh workflow run release_build_and_tag.yaml -R google/skills_lint.dart --ref main -f version=<version>`.
   It checks and builds everything, creates the tag `skills_lint-v<version>`
   and a draft release, and starts **Publish a tagged release**. Nothing that
   users install is public yet.
3. Open the publish run that the **Stage** job's summary links. When
   **Publish 1 of 2: package to pub.dev** asks for a review, check that the
   run's name has your version, then approve it. pub.dev, then the GitHub
   release, are published.
4. In the summary of the **Homebrew** job, follow the link to open the
   formula's pull request, and merge it once its `Homebrew` check passes.

If a job fails, its error says what to do:

| If this fails | Do this |
|---|---|
| **Plan**, a **Check** or a **Build** job | Fix the cause on `main` with a pull request, then run the build workflow again. Nothing was created. If the failure is flaky, **Re-run failed jobs**. |
| **Stage** | Do what the error says, then **Re-run failed jobs**. A re-run reuses the tag and the draft that it made. |
| **Verify** | Someone changed the draft. Delete it with `gh release delete skills_lint-v<version> -R google/skills_lint.dart`, then re-run the **Stage** job of the build run. |
| **Publish 1 of 2** | Fix what the error names, then **Re-run failed jobs**. To give up on the version, delete the draft and release the next version; the tag stays. |
| **Publish 2 of 2**, before publishing | Delete the draft, then re-run the **Stage** job of the build run. The new publish run skips pub.dev, which has the version. |
| **Publish 2 of 2**, after publishing | Stop. The published release differs from the build, or isn't immutable. Delete the release, tell the maintainers, and release the next version. |
| **Homebrew: push the formula update** | **Re-run failed jobs**. |
| The `Homebrew` check of the formula's pull request | In `release/`, run `dart run bin/release.dart homebrew-formula --version <version> --sha256sums <the release's SHA256SUMS>` on the branch, and push. |

## What can be undone

| Step | Who sees it | Undo |
|---|---|---|
| Tag | Everyone, but nothing installs from it | Only an admin can move or delete it. |
| Draft release | People with push access | Delete it at any time. |
| pub.dev | `dart pub` users, at once | [Never deleted or uploaded again](https://dart.dev/tools/pub/publishing#remember-publishing-is-forever). It can be [retracted](https://dart.dev/tools/pub/publishing#retract-a-package-version) for 7 days, which only stops new resolutions. |
| GitHub release | `install.sh` users, at once | [Immutable](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases): its assets and tag are locked. It can be deleted, but its tag can't be used again. |
| Homebrew pull request | `brew upgrade` users, once merged | Revert it. |

pub.dev comes first because it is the step most likely to fail, and until it
succeeds nothing but the tag is public.

## Expectations

- The build workflow creates the tag only after these pass at the commit it
  releases: the skills_lint CI workflow, the release tool's tests, the
  version and `CHANGELOG.md` rules in
  [`release_info.dart`](release/lib/src/release_info.dart) and
  [`release_notes.dart`](release/lib/src/release_notes.dart), a merged pull
  request that holds the commit, `dart pub publish --dry-run`, and
  `brew style` and `brew audit --strict` on the formula it renders.
- A version with a `-` suffix, such as `1.0.0-dev.1`, is a prerelease: it
  has no Homebrew formula and never becomes
  [the latest release](https://docs.github.com/en/rest/releases/releases#get-the-latest-release),
  which the README's install command downloads. A numeric build, such as
  `0.5.4+1`, is a release. The build workflow refuses any other build.
- A release has `skills_lint-<target>.tar.gz` for each [target](#targets),
  holding the executable and a `LICENSE` with the notices for everything
  compiled into it; `SHA256SUMS`; `install.sh`, which installs this version
  unless `VERSION` is set; the [`pubspec.lock`](#dependencies) of the build;
  and, unless it is a prerelease, the formula `skills_lint.rb`.
- The build workflow run of the tagged commit attests every asset. The
  publish workflow checks those attestations once, publishes only assets
  with the digests it checked, and fails if the published release isn't
  immutable. To check an asset yourself:

  ```bash
  gh attestation verify <file> -R google/skills_lint.dart \
    --signer-workflow google/skills_lint.dart/.github/workflows/release_build_and_tag.yaml \
    --source-ref refs/heads/main
  ```

- Jobs that run Dart code from pub have no write permission, apart from the
  pub.dev job's `id-token`.

## Targets

`releaseTargets` in
[`release/lib/src/archive.dart`](release/lib/src/archive.dart) is the one
list of targets, with the runner that builds each. `dart compile exe` builds
for the machine it runs on, so each target builds on a runner of its own
platform. The build matrix, `release package --target`, the formula and
`install.sh` all follow from that list.

The minimum macOS version, macOS 14, comes from the Dart SDK of the build
([sdk change 468883](https://dart-review.googlesource.com/c/sdk/+/468883)),
so a Dart upgrade can raise it. `release package` fails if the executable's
minimum differs from `macosMinimumVersion` in
[`release/lib/src/macho.dart`](release/lib/src/macho.dart), and its error
lists what to update.

There is no Windows executable yet; see
[issue #86](https://github.com/google/skills_lint.dart/issues/86).

## Homebrew formula

`release homebrew-formula` generates [`Formula/skills_lint.rb`](Formula/skills_lint.rb)
from [`release/templates/skills_lint.rb.tmpl`](release/templates/skills_lint.rb.tmpl).
Only the version and each target's `url` and `sha256` are generated.

- Until a release has executables, the checksums are placeholders, the version
  is the pending release, and `brew install` fails. After that, the formula
  names a released version and the checksums from its `SHA256SUMS`.
- The pull request that updates it comes from the tag's template, so if the
  template changed on `main` since the tag, regenerate the formula on the
  branch.
- The repo tests fail when the formula isn't what the template gives, and the
  `Homebrew` check fails when brew rejects the formula or can't install it.
- Require the `Homebrew` status check on `main` (ruleset 21051370).
- Published READMEs keep their install commands, so don't rename the tap
  `google/skills-lint` or the formula `skills_lint`.

## Dependencies

The repository has no checked-in `pubspec.lock`. The build workflow resolves
the dependencies once, and every job installs that `pubspec.lock` with
`dart pub get --enforce-lockfile`, which fails if a package's content hash
differs. The release ships it, and the pub.dev job publishes with it. To
rebuild a release, check out its tag, download its `pubspec.lock` to the
repository root and run `dart pub get --enforce-lockfile`.

## Release scripts

The workflow steps run the `release` command of the unpublished
`skills_lint_release` package in `release/`. To list its commands, run
`dart run bin/release.dart --help` there. When the workflows move to a new
Dart SDK, check the Dart runtime licenses described in
[`release/dart_runtime_licenses/README.md`](release/dart_runtime_licenses/README.md),
and the macOS minimum above.

A pull request that changes the release files runs a dry run of the build
workflow, which uploads the assets as the `release-assets` artifact and
creates nothing. To run one by hand, run the build workflow on any branch
without a version.
