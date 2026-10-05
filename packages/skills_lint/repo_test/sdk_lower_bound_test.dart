// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Checks that CI tests the lowest Dart SDK that the pubspecs allow.
///
/// The `analyze_and_test` job in `.github/workflows/skills_lint_workflow.yaml`
/// has one matrix entry with `downgrade: true`. It runs the checks on a pinned
/// SDK version with the lowest dependency versions that the pubspecs allow.
/// GitHub Actions can't read that version from a pubspec, so it is written in
/// the workflow by hand. If it drifts from the `environment.sdk` lower bound,
/// the entry tests a version that users can't be on, or misses the one they
/// can. A lower bound that no dependency can resolve at, such as a dev
/// dependency that needs a newer SDK, then goes unnoticed.
///
/// Every first-party pubspec (the root workspace pubspec and each workspace
/// member) must declare the same lower bound, so the one matrix entry covers
/// them all. Pub requires each workspace member to declare its own SDK
/// constraint. Change this rule if a workspace member needs its own SDK lower
/// bound; that member then needs its own matrix entry.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'src/repo_paths.dart';

const String _jobName = 'analyze_and_test';

void main() {
  test('first-party pubspecs share one SDK lower bound', () {
    final String rootBound = _lowerBound('pubspec.yaml');
    final List<String> mismatches = [
      for (final String member in _workspaceMembers())
        if (_lowerBound('$member/pubspec.yaml') != rootBound)
          '$member/pubspec.yaml: SDK lower bound is ${_lowerBound('$member/pubspec.yaml')}',
    ];
    expect(
      mismatches,
      isEmpty,
      reason:
          'Every first-party pubspec must declare the same environment.sdk '
          'lower bound as pubspec.yaml ($rootBound):\n  ${mismatches.join('\n  ')}',
    );
  });

  test('CI $_jobName downgrade entry runs on the pubspec SDK lower bound', () {
    final String rootBound = _lowerBound('pubspec.yaml');
    expect(
      _workflowLowerBoundSdk(),
      rootBound,
      reason:
          'The `sdk` value of the `downgrade: true` matrix entry of the $_jobName job in '
          '.github/workflows/skills_lint_workflow.yaml must equal the '
          'environment.sdk lower bound in pubspec.yaml ($rootBound). When you '
          'change the lower bound, update both, and every first-party pubspec.',
    );
  });
}

/// Returns the workspace members listed in the root pubspec, as paths
/// relative to the repository root.
List<String> _workspaceMembers() => _pubspec('pubspec.yaml').workspace ?? const [];

/// Returns the lower bound of the `environment.sdk` constraint in the pubspec
/// at [relativePath], for example `3.12.0` for `^3.12.0` or `>=3.12.0 <4.0.0`.
String _lowerBound(String relativePath) {
  final VersionConstraint? constraint = _pubspec(relativePath).environment['sdk'];
  final Version? min = constraint is VersionRange ? constraint.min : null;
  expect(
    min,
    isNotNull,
    reason: '$relativePath: environment.sdk `$constraint` has no lower bound.',
  );
  return min.toString();
}

Pubspec _pubspec(String relativePath) =>
    Pubspec.parse(File(p.join(repoRoot, relativePath)).readAsStringSync());

/// Returns the `sdk` value of the `downgrade: true` matrix entry of the
/// [_jobName] job.
String _workflowLowerBoundSdk() {
  final YamlMap workflow = _loadYamlMap(
    p.join('.github', 'workflows', 'skills_lint_workflow.yaml'),
  );
  final job = (workflow['jobs'] as YamlMap)[_jobName] as YamlMap;
  final matrix = (job['strategy'] as YamlMap)['matrix'] as YamlMap;
  final List<String> sdks = [
    for (final Object? entry in matrix['include'] as YamlList? ?? YamlList())
      if (entry is YamlMap && entry['downgrade'] == true) entry['sdk'].toString(),
  ];
  expect(
    sdks,
    hasLength(1),
    reason: 'The $_jobName matrix must include exactly one entry with `downgrade: true`.',
  );
  return sdks.single;
}

YamlMap _loadYamlMap(String relativePath) =>
    loadYaml(File(p.join(repoRoot, relativePath)).readAsStringSync()) as YamlMap;
