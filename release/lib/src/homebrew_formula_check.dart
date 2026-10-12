// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// What `release homebrew-formula --check` checks in the committed formula.
library;

import 'package:pub_semver/pub_semver.dart';

import 'homebrew_formula.dart';
import 'release_info.dart';
import 'release_notes.dart';

/// Why [formula] fails `release homebrew-formula --check`, or an empty list
/// if it passes.
///
/// It fails if it isn't what [template] gives for the formula's own version
/// and checksums, so changes belong in the template. Its version must also
/// suit [pubspecVersion] and [changelog]:
/// - While the checksums are placeholders, the version is [pubspecVersion]
///   without `-wip`, the release that the placeholders wait for.
/// - After that, the version has a heading in [changelog], and it is not
///   newer than [pubspecVersion].
///
/// [formula] and [template] have LF line endings.
List<String> formulaProblems(
  String formula, {
  required String template,
  required String pubspecVersion,
  required String changelog,
}) {
  final FormulaValues values = readFormula(formula);
  final List<String> problems = _versionProblems(values, pubspecVersion, changelog);
  if (renderFormula(template, values) != formula) {
    problems.add('it is not what the template gives');
  }
  return problems;
}

List<String> _versionProblems(FormulaValues values, String pubspecVersion, String changelog) {
  final String version = values.version;
  if (!isHomebrewVersion(version)) {
    return ['version "$version" is not a release that Homebrew can install'];
  }
  if (values.checksums == null) {
    final String pendingRelease = pubspecVersion.replaceFirst('-wip', '');
    if (version != pendingRelease) {
      return [
        'placeholder version "$version" must be $pendingRelease, the pubspec version without -wip',
      ];
    }
    return [];
  }
  final List<String> problems = [];
  if (!hasChangelogHeading(changelog, version)) {
    problems.add('version "$version" has no "## $version" heading in the CHANGELOG');
  }
  if (Version.parse(version) > Version.parse(pubspecVersion)) {
    problems.add('version "$version" is newer than the pubspec version $pubspecVersion');
  }
  return problems;
}
