---
name: release-dart-package
description: Prepares and publishes a new version of a Dart package to pub.dev, from the version bump to the GitHub release. Use when asked to cut, tag or publish a release.
license: Apache-2.0
compatibility: Needs the Dart SDK, git and the GitHub CLI, with publish rights on pub.dev.
allowed-tools: Bash Read Write
metadata:
  internal: true
---

# Release a Dart package

Use this skill to publish a new version of a package to pub.dev. A release
has four parts: choose the version, update the changelog, publish, and tag.
Do them in that order, and stop at the first problem.

Read [checklist.md](references/checklist.md) before you start. It is the
short version of this skill, for when you have done a release before.

## Choose the version

The package follows semantic versioning. Read
[versioning.md](references/versioning.md) for the details. In short:

- A breaking change to the public API, the CLI flags, or the config file
  format needs a major version, or a minor version while the package is
  below 1.0.0.
- A new feature that doesn't break anything needs a minor version, or a
  patch version below 1.0.0.
- A fix that doesn't change the API needs a patch version.

When you're not sure whether a change breaks users, treat it as breaking.

```bash
git log --oneline "v$(scripts/check-version.sh --current)..HEAD"
```

Read every commit since the last tag. Sort them into breaking changes, new
features and fixes. That list becomes the changelog entry.

## Update the changelog

1. Open `CHANGELOG.md`. The top section is usually named `X.Y.Z-wip`.
2. Rename it to the version you chose. Remove `-wip`.
3. Check each entry against [changelog-guide.md](references/changelog-guide.md):
   entries are for users, start with a verb, and name the flag or API.
4. Move entries that no user would notice out of the changelog.
5. Set the same version in `pubspec.yaml`.

Run the version check. It fails if `pubspec.yaml`, `CHANGELOG.md` and the
version constant in the code don't agree.

```bash
scripts/check-version.sh
```

## Run the checks

Run every check that CI runs, from a clean checkout of the release commit:

```bash
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Then do a dry run of the publish. It lists every file that will be
uploaded. Look for files that shouldn't be there, such as local config,
build output or large test data.

```bash
scripts/publish-dry-run.sh
```

If the dry run warns about anything, fix it before you publish. A version
on pub.dev can't be changed or deleted, only retracted.

## Publish

1. Send the version bump and changelog as a pull request, and wait for
   review and green CI.
2. Merge it.
3. From the merge commit on `main`, run `dart pub publish`.
4. Check the package page on pub.dev. The new version, the changelog and
   the score can take a few minutes to show.

## Tag and release

Tag the merge commit, and push the tag:

```bash
version="$(scripts/check-version.sh --current)"
git tag -a "v$version" -m "v$version"
git push origin "v$version"
gh release create "v$version" --title "v$version" --notes-from-tag
```

Paste the changelog section into the release notes.

## After the release

- Add a new `X.Y.Z-wip` section at the top of the changelog, with the next
  patch version, and a matching version in `pubspec.yaml`.
- Tell the downstream repositories that use the package that a new version
  is out, and link to the changelog.
- If something went wrong, write it down in the checklist so the next
  release avoids it.

## If something goes wrong

- **The publish failed.** Read the error, fix it on a new branch, and start
  again from "Run the checks". The version wasn't used, so you can keep it.
- **The published version is broken.** Retract it on pub.dev, fix the
  problem, and release a new patch version. Don't reuse the version number.
- **The tag points at the wrong commit.** Delete the tag locally and on
  GitHub, then tag the right commit. Do this only before anyone has used the
  tag.
