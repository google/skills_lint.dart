// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Builds GitHub release notes from `CHANGELOG.md`.
library;

import 'release_exception.dart';

/// Returns the entries under the `## <version>` heading of [changelog], up to
/// the next `## ` heading, without surrounding blank lines.
///
/// Throws a [ReleaseException] if there is no such heading or it has no
/// entries.
String changelogSection(String changelog, String version) {
  final heading = '## $version';
  final List<String> lines = changelog.replaceAll('\r\n', '\n').split('\n');
  final int start = _headingIndex(lines, version);
  if (start == -1) {
    throw ReleaseException('CHANGELOG.md has no "$heading" heading.');
  }
  final int next = lines.indexWhere((line) => line.startsWith('## '), start + 1);
  final String section = lines.sublist(start + 1, next == -1 ? lines.length : next).join('\n');
  final String trimmed = section.trim();
  if (trimmed.isEmpty) {
    throw ReleaseException('The "$heading" section of CHANGELOG.md has no entries.');
  }
  return trimmed;
}

/// Whether [changelog] has the `## <version>` heading that
/// [changelogSection] reads.
bool hasChangelogHeading(String changelog, String version) =>
    _headingIndex(changelog.split('\n'), version) != -1;

// trimRight also drops the \r of a CRLF line ending.
int _headingIndex(List<String> lines, String version) =>
    lines.indexWhere((line) => line.trimRight() == '## $version');
