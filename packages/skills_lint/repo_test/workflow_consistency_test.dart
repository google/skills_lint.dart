// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/package_directories.dart';
import 'src/repo_paths.dart';

const int _maxCognitiveComplexityThreshold = 20;

/// Directories with Dart files that the cognitive complexity check skips.
const Set<String> _unscannedDirectories = {
  // Vendored skill repositories: code we don't maintain.
  'third_party',
  // Eval inputs, including deliberately bad code that the evals expect a
  // reviewer to flag.
  'packages/skills_lint/evals/test_data',
  '.agents/skills/run-evals/resources/test_data',
};

/// One or more whitespace characters, the separator between the words of a
/// command line.
///
/// Splitting `dart test  --coverage=coverage test` on it gives `dart`,
/// `test`, `--coverage=coverage` and `test`.
final RegExp _whitespace = RegExp(r'\s+');

/// Returns the entries of [testDirectories] that a `dart test` [command]
/// selects. A command with no path argument selects `test`, package:test's
/// default path.
///
/// For example, `dart test --coverage=coverage` selects `{test}` and
/// `dart test repo_test` selects `{repo_test}`.
Set<String> _categoriesSelectedBy(String command) {
  // The first two words are `dart test`.
  final Iterable<String> arguments = command.split(_whitespace).skip(2);
  final paths = <String>{};
  for (final argument in arguments) {
    final bool isFlag = argument.startsWith('-');
    if (!isFlag) {
      paths.add(p.url.normalize(argument));
    }
  }
  return paths.isEmpty ? {'test'} : paths;
}

void main() {
  group('CI workflow consistency', () {
    test('CI workflow cognitive complexity fail-threshold does not exceed 20', () {
      final RegExpMatch match = _parseCognitiveComplexityInvocation();
      final int threshold = int.parse(match.group(1)!);
      expect(threshold, lessThanOrEqualTo(_maxCognitiveComplexityThreshold));

      final List<String> targets = match.group(2)!.trim().split(_whitespace);
      expect(
        targets,
        containsAll([
          'packages/skills_lint/bin',
          'packages/skills_lint/lib',
          'packages/skills_lint/test',
          'packages/skills_lint/repo_test',
          'packages/skills_lint/compiled_test',
          'packages/skills_lint/example',
          'packages/skills_lint/skills',
          'packages/skills_lint/benchmark',
          '.agents/skills',
        ]),
      );
    });

    test('CI cognitive complexity check scans every Dart file in the repository', () {
      final List<String> targets = _parseCognitiveComplexityInvocation()
          .group(2)!
          .trim()
          .split(_whitespace);
      final List<String> unscanned = [
        for (final String file in _dartFiles(Directory(repoRoot), repoRoot))
          if (![
            ...targets,
            ..._unscannedDirectories,
          ].any((String target) => file.startsWith('$target/')))
            file,
      ];
      expect(
        unscanned,
        isEmpty,
        reason:
            'These Dart files are outside every path that the cognitive_complexity step in '
            '.github/workflows/skills_lint_workflow.yaml scans. Add their directory to that '
            'command and to .agents/skills/definition-of-done/SKILL.md:\n  ${unscanned.join('\n  ')}',
      );
    });

    test('CI runs each test directory as its own step', () {
      final List<String> invocations = _dartTestInvocations();
      final List<String> unselected = [
        for (final String command in invocations)
          if (_categoriesSelectedBy(command).length != 1 ||
              !testDirectories.contains(_categoriesSelectedBy(command).single))
            command,
      ];
      expect(
        unselected,
        isEmpty,
        reason:
            'Each `dart test` step in the CI workflow must run exactly one of '
            '${testDirectories.join(', ')}, so a failure names its kind.',
      );
      for (final String category in testDirectories) {
        expect(
          invocations.where((command) => _categoriesSelectedBy(command).contains(category)),
          isNotEmpty,
          reason: 'The CI workflow must run the tests in $category/.',
        );
      }
      expect(
        invocations.where((command) => command.contains('--coverage')).map(_categoriesSelectedBy),
        everyElement(equals({'test'})),
        reason: 'Coverage must come from test/ only (`dart test --coverage=...`).',
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

/// The `cognitive_complexity` command in the CI workflow, such as:
///
/// ```yaml
///         run: dart run cognitive_complexity --fail-threshold 20 packages/skills_lint/bin .agents/skills
/// ```
///
/// Group 1 is the `--fail-threshold` value (`20`) and group 2 is the rest of
/// the line, the space-separated paths that it scans.
final RegExp _cognitiveComplexityCommand = RegExp(
  r'dart\s+run\s+cognitive_complexity\s+--fail-threshold\s+(\d+)\s+([^\r\n]+)',
);

/// A `run:` step of the CI workflow that runs `dart test`, such as either of:
///
/// ```yaml
///         run: dart test repo_test
///       - run: dart test --coverage=coverage
/// ```
///
/// Group 1 is the command, from `dart test` to the end of the line.
final RegExp _dartTestRunStep = RegExp(
  r'^\s*(?:-\s+)?run:\s*(dart\s+test\b[^\r\n]*)',
  multiLine: true,
);

/// Returns the [_cognitiveComplexityCommand] match in the CI workflow.
RegExpMatch _parseCognitiveComplexityInvocation() {
  final File workflowFile = _getWorkflowFile();
  expect(workflowFile.existsSync(), isTrue, reason: 'CI workflow file missing');
  final String content = workflowFile.readAsStringSync();
  final RegExpMatch? match = _cognitiveComplexityCommand.firstMatch(content);
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
    for (final RegExpMatch match in _dartTestRunStep.allMatches(content)) match.group(1)!.trim(),
  ];
}

/// Hidden directories under the repository root that hold source files.
const Set<String> _hiddenSourceDirectories = {'.agents', '.github'};

/// Returns the paths, relative to [root] and with `/` separators, of the Dart
/// files under [dir].
///
/// Skips `build` directories and hidden directories, such as `.dart_tool`
/// and `.git`, apart from [_hiddenSourceDirectories].
Iterable<String> _dartFiles(Directory dir, String root) sync* {
  for (final FileSystemEntity entity in dir.listSync(followLinks: false)) {
    final String name = p.basename(entity.path);
    if (entity is Directory) {
      final bool hidden = name.startsWith('.') && !_hiddenSourceDirectories.contains(name);
      if (!hidden && name != 'build') {
        yield* _dartFiles(entity, root);
      }
    } else if (entity is File && name.endsWith('.dart')) {
      yield p.split(p.relative(entity.path, from: root)).join('/');
    }
  }
}

File _getWorkflowFile() =>
    File(p.join(repoRoot, '.github', 'workflows', 'skills_lint_workflow.yaml'));
