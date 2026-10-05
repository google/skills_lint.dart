// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Checks that CI tests the lowest Dart SDK that any first-party pubspec
/// allows. GitHub Actions can't read that version from a pubspec.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'src/repo_paths.dart';

void main() {
  // A pubspec whose lower bound is above the tested SDK already fails
  // `dart pub get` in that CI entry, so only the lowest bound needs checking.
  test('CI tests the lowest SDK that a first-party pubspec allows', () {
    final List<String> pubspecs = [
      'pubspec.yaml',
      for (final String member in _pubspec('pubspec.yaml').workspace ?? const <String>[])
        '$member/pubspec.yaml',
    ];
    final Map<String, Version> bounds = {
      for (final String path in pubspecs) path: _lowerBound(path),
    };
    final Version lowest = bounds.values.reduce((Version a, Version b) => a < b ? a : b);
    expect(
      _testedSdk(),
      lowest.toString(),
      reason:
          'The `downgrade: true` entry of the analyze_and_test matrix in '
          '.github/workflows/skills_lint_workflow.yaml must set `sdk` to the '
          'lowest environment.sdk lower bound of the first-party pubspecs:\n'
          '  ${bounds.entries.map((e) => '${e.key}: ${e.value}').join('\n  ')}',
    );
  });
}

Version _lowerBound(String relativePath) {
  final VersionConstraint? constraint = _pubspec(relativePath).environment['sdk'];
  final Version? min = constraint is VersionRange ? constraint.min : null;
  expect(min, isNotNull, reason: '$relativePath: environment.sdk has no lower bound.');
  return min!;
}

Pubspec _pubspec(String relativePath) =>
    Pubspec.parse(File(p.join(repoRoot, relativePath)).readAsStringSync());

/// Returns the `sdk` of the `downgrade: true` entry in the analyze_and_test
/// matrix.
String _testedSdk() {
  final workflow =
      loadYaml(
            File(
              p.join(repoRoot, '.github', 'workflows', 'skills_lint_workflow.yaml'),
            ).readAsStringSync(),
          )
          as YamlMap;
  final job = (workflow['jobs'] as YamlMap)['analyze_and_test'] as YamlMap;
  final matrix = (job['strategy'] as YamlMap)['matrix'] as YamlMap;
  final List<String> sdks = [
    for (final Object? entry in matrix['include'] as YamlList? ?? YamlList())
      if (entry is YamlMap && entry['downgrade'] == true) entry['sdk'].toString(),
  ];
  expect(sdks, hasLength(1), reason: 'Expected exactly one `downgrade: true` matrix entry.');
  return sdks.single;
}
