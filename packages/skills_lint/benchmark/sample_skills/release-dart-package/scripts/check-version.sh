#!/usr/bin/env bash
# Checks that pubspec.yaml and the top CHANGELOG.md section name the same
# version. With --current, prints the version from pubspec.yaml.
set -euo pipefail

pubspec_version="$(sed -n 's/^version: *//p' pubspec.yaml)"
if [ "${1:-}" = "--current" ]; then
  echo "$pubspec_version"
  exit 0
fi

changelog_version="$(sed -n 's/^## *//p' CHANGELOG.md | head -n 1)"
if [ "$pubspec_version" != "$changelog_version" ]; then
  echo "pubspec.yaml has $pubspec_version but CHANGELOG.md has $changelog_version" >&2
  exit 1
fi
echo "Version $pubspec_version is consistent."
