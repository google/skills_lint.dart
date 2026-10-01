// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../src/repo_paths.dart';

const int _maxCognitiveComplexityThreshold = 20;

/// The test directories that CI runs, one step each. See "Where tests go" in
/// CONTRIBUTING.md.
const List<String> _testCategories = [
  'test/linter',
  'test/convention_checkers',
  'test/repo_conventions',
];

/// Returns the entries of [_testCategories] that [command] names as a path
/// argument.
Set<String> _categoriesNamedBy(String command) => {
  for (final String arg in command.split(RegExp(r'\s+')))
    for (final String category in _testCategories)
      if (arg == category || arg == '$category/') category,
};

void main() {
  group('CI workflow consistency', () {
    test('CI workflow cognitive complexity fail-threshold does not exceed 20', () {
      final RegExpMatch match = _parseCognitiveComplexityInvocation();
      final int threshold = int.parse(match.group(1)!);
      expect(threshold, lessThanOrEqualTo(_maxCognitiveComplexityThreshold));

      final List<String> targets = match.group(2)!.trim().split(RegExp(r'\s+'));
      expect(
        targets,
        containsAll([
          'packages/skills_lint/bin',
          'packages/skills_lint/lib',
          'packages/skills_lint/test',
          'packages/skills_lint/example',
          'packages/skills_lint/skills',
          '.agents/skills',
        ]),
      );
    });

    test('CI runs each test category as its own step', () {
      final List<String> invocations = _dartTestInvocations();
      final List<String> unselected = [
        for (final String command in invocations)
          if (_categoriesNamedBy(command).length != 1) command,
      ];
      expect(
        unselected,
        isEmpty,
        reason:
            'Each `dart test` step in the CI workflow must name exactly one of '
            '${_testCategories.join(', ')}, so a failure names its kind.',
      );
      for (final String category in _testCategories) {
        expect(
          invocations.where((command) => _categoriesNamedBy(command).contains(category)),
          isNotEmpty,
          reason: 'The CI workflow must run `dart test $category`.',
        );
      }
      expect(
        invocations.where((command) => command.contains('--coverage')),
        everyElement(contains('test/linter')),
        reason:
            'Coverage must come from linter tests only (`dart test test/linter --coverage=...`).',
      );
    });

    // CI selects tests by directory. A test file outside every category
    // directory would run under a plain `dart test` but in no CI step.
    test('every test file is in a category directory that CI runs', () {
      final List<String> orphans = [
        for (final File file in Directory(
          p.join(packageRoot, 'test'),
        ).listSync(recursive: true).whereType<File>())
          if (file.path.endsWith('_test.dart'))
            p.split(p.relative(file.path, from: packageRoot)).join('/'),
      ].where((path) => !_testCategories.any((dir) => path.startsWith('$dir/'))).toList()..sort();
      expect(
        orphans,
        isEmpty,
        reason:
            'Move each file into one of ${_testCategories.join(', ')}. See '
            '"Where tests go" in CONTRIBUTING.md.',
      );
    });

    test('documents quote the CI cognitive complexity command exactly', () {
      final String commandLine = _parseCognitiveComplexityInvocation().group(0)!.trim();
      final String text = File(
        p.join(repoRoot, '.agents', 'skills', 'definition-of-done', 'SKILL.md'),
      ).readAsStringSync();
      // The backticks pin both ends, so a document that drops or appends a
      // path root does not match.
      expect(
        text,
        contains('`$commandLine`'),
        reason:
            '.agents/skills/definition-of-done/SKILL.md describes the cognitive '
            'complexity gate but does not quote the command CI runs. Copy this '
            'line verbatim:\n  $commandLine',
      );
    });
  });
}

/// Returns the `dart run cognitive_complexity` invocation in the CI workflow.
///
/// Group 1 is the `--fail-threshold` value and group 2 is the list of scanned
/// paths.
RegExpMatch _parseCognitiveComplexityInvocation() {
  final File workflowFile = _getWorkflowFile();
  expect(workflowFile.existsSync(), isTrue, reason: 'CI workflow file missing');
  final String content = workflowFile.readAsStringSync();
  final regex = RegExp(
    r'dart\s+run\s+cognitive_complexity\s+--fail-threshold\s+(\d+)\s+([^\r\n]+)',
  );
  final RegExpMatch? match = regex.firstMatch(content);
  expect(
    match,
    isNotNull,
    reason: 'CI workflow must run cognitive_complexity with --fail-threshold <N>',
  );
  return match!;
}

/// Returns each `dart test` command that a `run:` step of the CI workflow runs.
List<String> _dartTestInvocations() {
  final String content = _getWorkflowFile().readAsStringSync();
  return [
    for (final RegExpMatch match in RegExp(
      r'^\s*(?:-\s+)?run:\s*(dart\s+test\b[^\r\n]*)',
      multiLine: true,
    ).allMatches(content))
      match.group(1)!.trim(),
  ];
}

File _getWorkflowFile() =>
    File(p.join(repoRoot, '.github', 'workflows', 'skills_lint_workflow.yaml'));
