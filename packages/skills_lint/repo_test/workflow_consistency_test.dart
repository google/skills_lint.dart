// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/package_directories.dart';
import 'src/repo_paths.dart';

const int _maxCognitiveComplexityThreshold = 20;

/// The `--exclude` globs that the cognitive complexity check may pass.
const Set<String> _allowedExcludes = {
  // Vendored skill repositories: code we don't maintain.
  'third_party/**',
  // Eval inputs, including deliberately bad code that the evals expect a
  // reviewer to flag.
  '**/test_data/**',
};

/// Returns the entries of [testDirectories] that a `dart test` [command]
/// selects. A command with no path argument selects `test`, package:test's
/// default path.
Set<String> _categoriesSelectedBy(String command) {
  final Set<String> paths = {
    for (final String arg in command.split(RegExp(r'\s+')).skip(2))
      if (!arg.startsWith('-')) p.url.normalize(arg),
  };
  return paths.isEmpty ? {'test'} : paths;
}

void main() {
  group('CI workflow consistency', () {
    test('CI workflow cognitive complexity fail-threshold does not exceed 20', () {
      final int threshold = int.parse(_parseCognitiveComplexityInvocation().group(1)!);
      expect(threshold, lessThanOrEqualTo(_maxCognitiveComplexityThreshold));
    });

    test('CI cognitive complexity check scans the repository apart from allowed excludes', () {
      final (:List<String> paths, :List<String> excludes) = _cognitiveComplexityArguments(
        _parseCognitiveComplexityInvocation().group(2)!,
      );
      expect(paths, ['.'], reason: 'The check runs from the repository root and scans all of it.');
      expect(
        _allowedExcludes,
        containsAll(excludes),
        reason: 'Each --exclude glob must be in _allowedExcludes, with the reason it is skipped.',
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

/// Splits the [arguments] of a `cognitive_complexity` command after
/// `--fail-threshold <N>` into scanned paths and `--exclude` globs, without
/// shell quotes.
({List<String> paths, List<String> excludes}) _cognitiveComplexityArguments(String arguments) {
  final List<String> words = [
    for (final String word in arguments.trim().split(RegExp(r'\s+'))) word.replaceAll("'", ''),
  ];
  final List<String> paths = [];
  final List<String> excludes = [];
  for (var i = 0; i < words.length; i++) {
    if (words[i] == '--exclude' && i + 1 < words.length) {
      excludes.add(words[++i]);
    } else if (words[i].startsWith('--exclude=')) {
      excludes.add(words[i].substring('--exclude='.length));
    } else {
      paths.add(words[i]);
    }
  }
  return (paths: paths, excludes: excludes);
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
