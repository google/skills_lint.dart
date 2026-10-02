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
  final int start = lines.indexWhere((line) => line.trimRight() == heading);
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

/// Returns the release notes for the changelog [section].
///
/// The notes of a [dryRun] release start with a warning not to publish it.
String releaseNotes(String section, {required bool dryRun}) {
  final warning = dryRun
      ? "> [!WARNING]\n> Dry run from a manual workflow run. Delete this draft; don't publish it.\n\n"
      : '';
  return '$warning$section\n';
}
