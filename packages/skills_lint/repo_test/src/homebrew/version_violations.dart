// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_semver/pub_semver.dart';

import '../models/convention_violation.dart';
import 'formula_value.dart';
import 'homebrew_formula.dart';

/// Reports where the `version` of [formula] breaks the version rule.
///
/// The version is never a prerelease, because Homebrew installs it for every
/// user; a version with build metadata, such as `1.2.0+1`, is a release.
/// While the formula has placeholders, the version is [pubspecVersion]
/// without `-wip`, the release that the placeholders wait for. Once the
/// values are real, the version is a release: [changelog] has a
/// `## <version>` heading for it, and it is not newer than [pubspecVersion].
List<ConventionViolation> findVersionViolations(
  String path,
  HomebrewFormula formula, {
  required String pubspecVersion,
  required String changelog,
}) {
  final FormulaValue? version = formula.version;
  if (version == null) {
    return [ConventionViolation(path, missingStatementLine, 'has no version')];
  }
  final String? problem = _versionProblem(
    version.value,
    formulaHasPlaceholders: formula.hasPlaceholders,
    pubspec: Version.parse(pubspecVersion),
    changelog: changelog,
  );
  if (problem == null) {
    return [];
  }
  return [ConventionViolation(path, version.line, problem)];
}

String? _versionProblem(
  String value, {
  required bool formulaHasPlaceholders,
  required Version pubspec,
  required String changelog,
}) {
  final Version version;
  try {
    version = Version.parse(value);
  } on FormatException {
    return 'version "$value" is not a semantic version';
  }
  if (version.isPreRelease) {
    return 'version "$value" is a prerelease; Homebrew installs releases only';
  }
  if (formulaHasPlaceholders) {
    final String pendingRelease = '$pubspec'.replaceFirst('-wip', '');
    if (value == pendingRelease) {
      return null;
    }
    return 'placeholder version "$value" must be $pendingRelease, the pubspec version $pubspec '
        'without -wip';
  }
  final bool changelogHasHeading = changelog
      .split('\n')
      .any((String line) => line.trim() == '## $value');
  if (!changelogHasHeading) {
    return 'version "$value" has no "## $value" heading in the CHANGELOG, so it is not a release';
  }
  if (version > pubspec) {
    return 'version "$value" is newer than the pubspec version $pubspec';
  }
  return null;
}
