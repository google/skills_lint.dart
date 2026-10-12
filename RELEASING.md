# Releasing skills_lint

## How to release

1. Merge a pull request that sets `version` in
   `packages/skills_lint/pubspec.yaml` to the version to release, without
   `-wip`, and adds a `## <version>` section to `CHANGELOG.md`.
2. Run **Actions > Build and tag a release** on `main` with that version, or
   `gh workflow run release_build_and_tag.yaml -R google/skills_lint.dart --ref main -f version=<version>`.
   It checks and builds everything, tags `skills_lint-v<version>`, creates a
   draft release and starts **Publish a tagged release** on the tag.
3. In that run, approve **Publish 1 of 2: package to pub.dev** once the
   run's name shows your version. pub.dev, then the GitHub release, are
   published.
4. Follow the link in the **Homebrew** job's summary to open the formula's
   pull request, and merge it once its `Homebrew` check passes.

| If this fails | Do this |
|---|---|
| **Plan**, a **Check** or a **Build** job | Fix it on `main`, then run the build workflow again. For a flaky failure, **Re-run failed jobs**. |
| **Stage** | Do what the error says, then **Re-run failed jobs**. |
| **Verify**, or **Publish 2 of 2** before publishing | Re-run the job once. If it fails again, delete the draft (`gh release delete skills_lint-v<version> -R google/skills_lint.dart`) and re-run **Stage**. The new publish run needs approval again, and skips pub.dev if it has the version. |
| **Publish 1 of 2** | Fix what the error names, then **Re-run failed jobs**. To give up on the version, delete the draft and release the next one. |
| **Publish 2 of 2** after publishing | Re-run the job once. If it fails again, stop: delete the release, tell the maintainers, and release the next version. |
| **Homebrew** | **Re-run failed jobs**. |
| The formula pull request's `Homebrew` check | In `release/`, run `dart run bin/release.dart homebrew-formula --version <version> --sha256sums <the release's SHA256SUMS>` on the branch and push. This happens when the template changed on `main` after the tag. |

## What can be undone

| Step | Undo |
|---|---|
| Tag | Only an admin can move or delete it. |
| Draft release | Delete it at any time. Only people with push access see it. |
| pub.dev | [Never deleted or uploaded again](https://dart.dev/tools/pub/publishing#remember-publishing-is-forever); [retractable](https://dart.dev/tools/pub/publishing#retract-a-package-version) for 7 days. |
| GitHub release | [Immutable](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases). It can be deleted, but its tag can't be used again. |
| Homebrew pull request | Revert it. |

pub.dev goes first because it fails most often, and until it succeeds only
the tag is public.

## Expectations

- The tag exists only if every check in the build workflow passed at its
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
  `gh attestation verify <file> -R google/skills_lint.dart --signer-workflow google/skills_lint.dart/.github/workflows/release_build_and_tag.yaml --source-ref refs/heads/main`.

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
repo tests fail when the formula isn't what the template gives. Require the
`Homebrew` status check on `main` (ruleset 21051370). Don't rename the tap
`google/skills-lint` or the formula `skills_lint`: published READMEs use them.
