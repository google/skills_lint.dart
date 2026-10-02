#!/usr/bin/env bash
# Runs `dart pub publish --dry-run` from a clean copy of HEAD, so local files
# that git ignores can't end up in the file list.
set -euo pipefail

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git archive HEAD | tar -x -C "$work"
cd "$work"
dart pub get
dart pub publish --dry-run
