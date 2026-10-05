// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Checks that CI tests the lowest Dart SDK that the pubspecs allow.
///
/// The `sdk_lower_bound` job in `.github/workflows/skills_lint_workflow.yaml`
/// runs analyze and the tests on one pinned SDK version. That version is
/// written in the workflow by hand. If it drifts from the `environment.sdk`
/// lower bound, the job tests a version that users can't be on, or misses the
/// one they can. A lower bound that no dependency can resolve at, such as a
/// dev dependency that needs a newer SDK, then goes unnoticed.
///
/// Every first-party pubspec (the root workspace pubspec and each workspace
/// member) must declare the same lower bound, so the one job covers them all.
/// Change this rule if a workspace member needs its own SDK lower bound; that
/// member then needs its own CI job.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'src/repo_paths.dart';

const String _jobName = 'sdk_lower_bound';

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

  test('CI $_jobName job runs on the pubspec SDK lower bound', () {
    final String rootBound = _lowerBound('pubspec.yaml');
    expect(
      _workflowLowerBoundSdk(),
      rootBound,
      reason:
          'The setup-dart `sdk:` value of the $_jobName job in '
          '.github/workflows/skills_lint_workflow.yaml must equal the '
          'environment.sdk lower bound in pubspec.yaml ($rootBound). When you '
          'change the lower bound, update both, and every first-party pubspec.',
    );
  });
}

/// Returns the workspace members listed in the root pubspec, as paths
/// relative to the repository root.
List<String> _workspaceMembers() {
  final YamlMap pubspec = _loadYamlMap('pubspec.yaml');
  return [for (final Object? member in pubspec['workspace'] as YamlList) member! as String];
}

/// Returns the lower bound of the `environment.sdk` constraint in the pubspec
/// at [relativePath], for example `3.12.0` for `^3.12.0` or `>=3.12.0 <4.0.0`.
String _lowerBound(String relativePath) {
  final YamlMap pubspec = _loadYamlMap(relativePath);
  final constraint = (pubspec['environment'] as YamlMap)['sdk'].toString();
  final RegExpMatch? match = RegExp(r'^(?:\^|>=)\s*(\S+)').firstMatch(constraint);
  expect(
    match,
    isNotNull,
    reason: '$relativePath: environment.sdk `$constraint` has no lower bound.',
  );
  return match!.group(1)!;
}

/// Returns the `sdk:` input of the setup-dart step in the [_jobName] job.
String _workflowLowerBoundSdk() {
  final YamlMap workflow = _loadYamlMap(
    p.join('.github', 'workflows', 'skills_lint_workflow.yaml'),
  );
  final job = (workflow['jobs'] as YamlMap)[_jobName] as YamlMap?;
  expect(job, isNotNull, reason: 'The CI workflow has no $_jobName job.');
  final List<String> sdks = [
    for (final Object? step in job!['steps'] as YamlList)
      if (step is YamlMap && (step['uses'] as String? ?? '').startsWith('dart-lang/setup-dart@'))
        (step['with'] as YamlMap)['sdk'].toString(),
  ];
  expect(sdks, hasLength(1), reason: 'The $_jobName job must set up Dart exactly once.');
  return sdks.single;
}

YamlMap _loadYamlMap(String relativePath) =>
    loadYaml(File(p.join(repoRoot, relativePath)).readAsStringSync()) as YamlMap;
