// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_lint/src/config_problem_report.dart';
import 'package:skills_lint/src/models/config_problem.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  final String cwd = p.normalize(p.absolute(Directory.current.path));
  final String config = p.join(cwd, 'skills_lint.yaml');
  final String other = p.join(cwd, 'nested', 'lint.yaml');

  ConfigProblem at(String file, int line, String message) =>
      ConfigProblem(message, location: (file: file, line: line, column: 3));

  group('configProblemReport', () {
    test('lists each problem once under a header for its file', () {
      final String report = configProblemReport([
        at(config, 2, 'unknown key "a".'),
        at(config, 10, 'unknown key "b".'),
      ], ignored: false);

      expect(configProblemsIn(report), [
        (
          level: ConfigProblemLevel.error,
          file: 'skills_lint.yaml',
          line: 2,
          column: 3,
          message: 'unknown key "a".',
        ),
        (
          level: ConfigProblemLevel.error,
          file: 'skills_lint.yaml',
          line: 10,
          column: 3,
          message: 'unknown key "b".',
        ),
      ]);
      expect(report, startsWith('skills_lint.yaml has 2 configuration errors:'));
      expect('Configuration error'.allMatches(report), isEmpty);
    });

    test('ends with the count, the file and the next step when skills_lint did not run', () {
      final String report = configProblemReport([at(config, 2, 'x.')], ignored: false);

      expect(
        report.split('\n').last,
        'skills_lint did not run. Fix this error in skills_lint.yaml and run again.',
      );
    });

    test('reports warnings and says skills_lint ran when the entries are ignored', () {
      final String report = configProblemReport([
        at(config, 2, 'x.'),
        at(config, 3, 'y.'),
      ], ignored: true);

      expect(configProblemsIn(report).map((p) => p.level).toSet(), {ConfigProblemLevel.warning});
      expect(report.split('\n').last, contains('skills_lint ran without these 2 entries'));
    });

    test('groups problems from several files and leaves the file out of the footer', () {
      final String report = configProblemReport([
        at(config, 2, 'x.'),
        at(other, 4, 'y.'),
      ], ignored: false);

      expect(configProblemsIn(report).map((p) => p.file), [
        'skills_lint.yaml',
        p.join('nested', 'lint.yaml'),
      ]);
      expect(report.split('\n').last, 'skills_lint did not run. Fix these 2 errors and run again.');
    });

    test('lists a problem without a location under a header without a file', () {
      final String report = configProblemReport([
        const ConfigProblem('Failed to parse x: boom'),
      ], ignored: false);

      expect(
        report.split('\n'),
        containsAllInOrder(['1 configuration error:', '  Failed to parse x: boom']),
      );
      expect(report.split('\n').last, 'skills_lint did not run. Fix this error and run again.');
    });
  });
}
