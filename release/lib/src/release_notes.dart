// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Builds GitHub release notes from `CHANGELOG.md`.
library;

import 'line_endings.dart';
import 'release_exception.dart';
import 'release_info.dart';

/// The release notes for [info]: the entries of the `CHANGELOG.md` section of
/// its version.
///
/// A dry run of a `-wip` version accepts a section with no entries, because
/// the `-wip` section starts empty after a release. Its notes then say so. A
/// stage run never publishes them: it refuses a `-wip` version.
///
/// Throws a [ReleaseException] if [changelog] has no heading for the version,
/// or if the section has no entries and the run is not a dry run of a `-wip`
/// version.
String releaseNotes(String changelog, ReleaseInfo info) {
  final String version = info.version;
  final String section = changelogSection(changelog, version);
  if (section.isNotEmpty) {
    return section;
  }
  final bool mayBeEmpty = switch (info.mode) {
    ReleaseMode.dryRun => isWipVersion(version),
    ReleaseMode.stage => false,
  };
  if (!mayBeEmpty) {
    throw ReleaseException('The "## $version" section of CHANGELOG.md has no entries.');
  }
  return 'Dry run of $version: the "## $version" section of CHANGELOG.md has no entries yet.';
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
    throw ReleaseException('CHANGELOG.md has no "## $version" heading.');
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
    lines.indexWhere((line) => line.trimRight() == '## $version');
