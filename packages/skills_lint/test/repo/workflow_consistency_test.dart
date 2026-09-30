// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['repo'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/repo_paths.dart';

const int _maxCognitiveComplexityThreshold = 20;

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

    test('CI runs product tests and repo checks as separate steps', () {
      final List<String> invocations = _dartTestInvocations();
      final List<String> untagged = [
        for (final String command in invocations)
          if (!command.contains('-x repo') && !command.contains('-t repo')) command,
      ];
      expect(
        untagged,
        isEmpty,
        reason:
            'Each `dart test` step in the CI workflow must select product tests '
            '(`-x repo`) or repo checks (`-t repo`), so a failure names its kind.',
      );
      expect(
        invocations.where((command) => command.contains('-t repo')),
        isNotEmpty,
        reason: 'The CI workflow must run the repo checks with `dart test -t repo`.',
      );
      expect(
        invocations.where((command) => command.contains('--coverage')),
        everyElement(contains('-x repo')),
        reason: 'Coverage must come from product tests only (`dart test -x repo --coverage=...`).',
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
