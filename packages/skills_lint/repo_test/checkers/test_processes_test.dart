// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/models/convention_violation.dart';
import '../src/models/source.dart';
import '../src/test_processes.dart';

/// Runs [findDartTestProcesses] over small inline snippets, which pins which
/// `TestProcess.start` calls it reports independently of the package's tests.
///
/// The repo-wide scan in `dart_test_process_convention_test.dart` relies on
/// this: a test that starts the Dart VM itself skips the compiled binary, so
/// the detector must catch each way of naming the VM and leave every other
/// executable alone.
void main() {
  group('findDartTestProcesses', () {
    test("reports TestProcess.start that can run 'dart' or Platform.resolvedExecutable", () {
      final source = Source.snippet('''
Future<void> run() async {
  await TestProcess.start('dart', ['bin/skills_lint.dart']);
  await TestProcess.start("dart", const []);
  await TestProcess.start(Platform.resolvedExecutable, ['bin/skills_lint.dart']);
  await tp.TestProcess.start('dart', const []);
  await TestProcess.start(compiled ?? 'dart', const []);
  await TestProcess.start(compiled != null ? compiled : ('dart'), const []);
}
''', path: 'test/snippet_test.dart');
      final List<ConventionViolation> violations = findDartTestProcesses(source);
      expect(_lines(violations), [2, 3, 4, 5, 6, 7]);
      expect(
        violations.map((v) => v.problem),
        everyElement(endsWith('starts the Dart VM instead of calling startCli')),
      );
      expect(violations.first.problem, startsWith("TestProcess.start('dart', …)"));
    });

    test('ignores other executables, other methods, and other classes', () {
      final source = Source.snippet(r'''
Future<void> run() async {
  await TestProcess.start('bash', [script]);
  await TestProcess.start(hookFile.path, const []);
  await TestProcess.start(executable, const []);
  await TestProcess.start('dart$suffix', const []);
  await Process.run('dart', ['format', '.']);
  await Process.start('dart', const []);
  await TestProcess.run('dart', const []);
  await startCli(['--version']);
}
''', path: 'test/snippet_test.dart');
      expect(findDartTestProcesses(source), isEmpty);
    });
  });
}

List<int> _lines(Iterable<ConventionViolation> violations) => [for (final v in violations) v.line];
