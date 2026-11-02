// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Builds GitHub release notes from `CHANGELOG.md`.
library;

import 'line_endings.dart';
import 'release_exception.dart';
import 'release_info.dart';

/// The release notes for [info], from its version's `CHANGELOG.md` section.
///
/// In a dry run of a `-wip` version, an empty section gives a sentence that
/// says so. Throws a [ReleaseException] for any other empty section, or if
/// the heading is missing.
String releaseNotes(String changelog, ReleaseInfo info) {
  final String version = info.version;
  final String section = changelogSection(changelog, version);
  if (section.isNotEmpty) {
    return section;
  }
  // The -wip section starts empty after a release, and no run releases a
  // -wip version.
  final bool mayBeEmpty = switch (info.mode) {
    ReleaseMode.dryRun => isWipVersion(version),
    ReleaseMode.stage => false,
  };
  if (!mayBeEmpty) {
    throw ReleaseException('The "${_heading(version)}" section of CHANGELOG.md has no entries.');
  }
  return 'Dry run of $version: the "${_heading(version)}" section of CHANGELOG.md has no '
      'entries yet.';
}

/// Extracts the entries under the `## <version>` heading of [changelog], up to
/// the next `## ` heading, without surrounding blank lines.
///
/// Is empty if the section has no entries. Throws a [ReleaseException] if
/// there is no such heading.
String changelogSection(String changelog, String version) {
  final List<String> lines = changelog.normalizeLineTerminators().split('\n');
  final int start = _headingIndex(lines, version);
  if (start == -1) {
    throw ReleaseException('CHANGELOG.md has no "${_heading(version)}" heading.');
  }
  final int next = lines.indexWhere((line) => line.startsWith('## '), start + 1);
  return lines.sublist(start + 1, next == -1 ? lines.length : next).join('\n').trim();
}

/// Whether [changelog] has the `## <version>` heading that
/// [changelogSection] reads.
bool hasChangelogHeading(String changelog, String version) =>
    _headingIndex(changelog.split('\n'), version) != -1;

// trimRight also drops the \r of a CRLF line ending.
int _headingIndex(List<String> lines, String version) =>
    lines.indexWhere((line) => line.trimRight() == _heading(version));

/// The `CHANGELOG.md` heading of the section for [version].
String _heading(String version) => '## $version';
