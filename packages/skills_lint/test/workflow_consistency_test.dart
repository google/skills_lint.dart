// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const int _maxCognitiveComplexityThreshold = 20;

/// Documents that state the cognitive complexity gate, relative to the
/// repository root. Each must quote the command CI runs verbatim.
const List<String> _documentsQuotingCognitiveComplexityCommand = <String>[
  'AGENTS.md',
  '.agents/skills/definition-of-done/SKILL.md',
];

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

    test('documents quote the CI cognitive complexity command exactly', () {
      final String commandLine = _parseCognitiveComplexityInvocation().group(0)!.trim();
      final String repoRoot = _getWorkflowFile().parent.parent.parent.path;
      for (final String doc in _documentsQuotingCognitiveComplexityCommand) {
        final String text = File(p.join(repoRoot, doc)).readAsStringSync();
        // The backticks pin both ends, so a document that drops or appends a
        // path root does not match.
        expect(
          text,
          contains('`$commandLine`'),
          reason:
              '$doc describes the cognitive complexity gate but does not quote '
              'the command CI runs. Copy this line verbatim:\n  $commandLine',
        );
      }
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

File _getWorkflowFile() {
  Directory dir = Directory.current;
  while (dir.path != '/' && dir.path.isNotEmpty) {
    final workflowFile = File(
      p.join(dir.path, '.github', 'workflows', 'skills_lint_workflow.yaml'),
    );
    if (workflowFile.existsSync()) {
      return workflowFile;
    }
    dir = dir.parent;
  }
  return File(p.normalize(p.absolute('../../.github/workflows/skills_lint_workflow.yaml')));
}
