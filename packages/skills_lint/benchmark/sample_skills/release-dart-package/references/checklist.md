# Release checklist

- [ ] Read every commit since the last tag.
- [ ] Choose the version (see versioning.md).
- [ ] Rename the `-wip` changelog section to the version.
- [ ] Check each changelog entry against changelog-guide.md.
- [ ] Set the same version in `pubspec.yaml`.
- [ ] Run `scripts/check-version.sh`.
- [ ] Run format, analyze and test from a clean checkout.
- [ ] Run `scripts/publish-dry-run.sh` and read the file list.
- [ ] Send the pull request and wait for review and green CI.
- [ ] Merge, then run `dart pub publish` from the merge commit.
- [ ] Check the package page on pub.dev.
- [ ] Tag the merge commit and push the tag.
- [ ] Create the GitHub release with the changelog section.
- [ ] Add the next `-wip` section and version.
- [ ] Tell downstream repositories.

## Lessons from past releases

- Run the dry run from a clean checkout. A local `.env` file was nearly
  uploaded once.
- Wait for CI on the merge commit, not only on the pull request. A merge
  with a newer `main` can break the build.
- Write the changelog for users. "Refactor the validator" tells a user
  nothing. "`--fix` no longer rewrites unchanged files" does.
