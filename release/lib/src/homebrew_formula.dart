// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Updates the Homebrew formula in `Formula/skills_lint.rb` to a release.
///
/// RELEASING.md describes the release automation that runs this, and
/// `packages/skills_lint/repo_test/homebrew_formula_test.dart` checks the
/// formula that it writes.
library;

import 'checksums.dart';
import 'release_exception.dart';

/// The `version` line of the formula, with an optional trailing comment.
final RegExp _versionLine = RegExp(r'^(\s*)version "[^"]*"(\s*#.*)?$');

/// A `url` line of the formula that names a release archive, which group 1
/// captures.
final RegExp _archiveUrlLine = RegExp(r'^\s*url "[^"]*/(skills_lint-[a-z0-9-]+\.tar\.gz)"\s*$');

/// A `sha256` line, with an optional trailing comment.
final RegExp _sha256Line = RegExp(r'^(\s*)sha256 "[^"]*"(\s*#.*)?$');

final RegExp _releaseVersion = RegExp(r'^\d+\.\d+\.\d+$');

/// Returns [formula] with its `version` set to [version] and the `sha256`
/// after each archive `url` set to that archive's checksum in [checksums].
///
/// Each `url` names an archive, and the `sha256` line after it is that
/// archive's checksum; the formula test checks this pairing. The formula's
/// `PLACEHOLDER` comments, which the first release removes, go too: the
/// trailing comment of each line that this changes, and the header
/// paragraph that starts with `# PLACEHOLDER:`.
///
/// Throws a [ReleaseException] if [version] is not `<major>.<minor>.<patch>`,
/// the formula has no `version` or no archive `url`, a `url` has no `sha256`
/// line after it, [checksums] has no checksum for an archive, or a
/// `PLACEHOLDER` comment remains.
String updateFormula(
  String formula, {
  required String version,
  required Map<String, String> checksums,
}) {
  if (!_releaseVersion.hasMatch(version)) {
    throw ReleaseException(
      'Homebrew installs releases only, and $version is not <major>.<minor>.<patch>.',
    );
  }
  final List<String> lines = _withoutPlaceholderHeader(formula.split('\n'));
  var versions = 0;
  var archives = 0;
  for (var i = 0; i < lines.length; i++) {
    if (_versionLine.firstMatch(lines[i]) case final RegExpMatch match) {
      lines[i] = '${match.group(1)}version "$version"';
      versions++;
    } else if (_archiveUrlLine.firstMatch(lines[i]) case final RegExpMatch match) {
      lines[i + 1] = _sha256For(lines, i + 1, match.group(1)!, checksums);
      archives++;
    }
  }
  final int sha256s = lines.where(_sha256Line.hasMatch).length;
  if (versions != 1 || archives == 0 || sha256s != archives) {
    throw ReleaseException(
      'The formula has $versions version lines, $archives archive urls and $sha256s sha256 '
      'lines; expected one version line and at least one archive url, each followed by its '
      'sha256 line.',
    );
  }
  final String updated = lines.join('\n');
  if (updated.contains('PLACEHOLDER')) {
    throw ReleaseException(
      'The formula has a PLACEHOLDER comment that this command does not remove.',
    );
  }
  return updated;
}

String _sha256For(List<String> lines, int index, String archive, Map<String, String> checksums) {
  final RegExpMatch? line = index < lines.length ? _sha256Line.firstMatch(lines[index]) : null;
  if (line == null) {
    throw ReleaseException('The url of $archive is not followed by a sha256 line.');
  }
  final String? checksum = checksums[archive];
  if (checksum == null) {
    throw ReleaseException('$sha256SumsName has no checksum for $archive.');
  }
  return '${line.group(1)}sha256 "$checksum"';
}

/// Returns [lines] without the comment paragraph that starts with
/// `# PLACEHOLDER:`, and without the `#` line that separates it from the
/// comment above.
List<String> _withoutPlaceholderHeader(List<String> lines) {
  final int start = lines.indexWhere((line) => line.startsWith('# PLACEHOLDER:'));
  if (start == -1) {
    return lines;
  }
  var end = start;
  while (end < lines.length && lines[end].startsWith('#')) {
    end++;
  }
  final int from = start > 0 && lines[start - 1] == '#' ? start - 1 : start;
  return [...lines.sublist(0, from), ...lines.sublist(end)];
}
