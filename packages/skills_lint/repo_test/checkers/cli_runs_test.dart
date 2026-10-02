// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/cli_runs.dart';
import '../src/models/convention_violation.dart';
import '../src/models/source.dart';

/// Runs the CLI-run detectors over small inline snippets, which pins what
/// each one reports independently of the package's tests.
void main() {
  group('findCliScriptPaths', () {
    test('reports the script path in one string or split across arguments', () {
      final source = Source.snippet(r'''
void main() {
  run('dart', ['bin/skills_lint.dart']);
  run('dart', [p.absolute('bin/skills_lint.dart')]);
  run('dart', [p.absolute('bin', 'skills_lint.dart')]);
  run('dart', ['$root/bin/skills_lint.dart']);
}
''', path: 'test/snippet_test.dart');
      final List<ConventionViolation> violations = findCliScriptPaths(source);
      expect(_lines(violations), [2, 3, 4, 5]);
      expect(violations.first.problem, "'bin/skills_lint.dart' names the CLI script");
    });

    test('ignores imports, URLs, comments, and other file names', () {
      final source = Source.snippet('''
import 'package:skills_lint/skills_lint.dart';

// Runs bin/skills_lint.dart.
const repository = 'https://github.com/google/skills_lint.dart';
const fixture = 'example/skills_lint.yaml';
''', path: 'test/snippet_test.dart');
      expect(findCliScriptPaths(source), isEmpty);
    });
  });

  group('findUntaggedCliRuns', () {
    test('reports the first startCli call in a library without the cli tag', () {
      final source = Source.snippet('''
void main() {
  test('a', () async {
    await startCli(['--help']);
    await startCli(['--version']);
  });
}
''', path: 'test/snippet_test.dart');
      final List<ConventionViolation> violations = findUntaggedCliRuns(source);
      expect(_lines(violations), [3]);
      expect(violations.single.problem, "calls startCli but the library has no @Tags(['cli'])");
    });

    test('reports a library tagged with other tags only', () {
      final source = Source.snippet('''
@Tags(['slow'])
library;

void main() {
  test('a', () => startCli(['--help']));
}
''', path: 'test/snippet_test.dart');
      expect(_lines(findUntaggedCliRuns(source)), [5]);
    });

    test('accepts a library tagged cli, alone or with other tags', () {
      for (final tags in ["['cli']", "['slow', 'cli']"]) {
        final source = Source.snippet('''
@Tags($tags)
library;

void main() {
  test('a', () => startCli(['--help']));
}
''', path: 'test/snippet_test.dart');
        expect(findUntaggedCliRuns(source), isEmpty, reason: '@Tags($tags)');
      }
    });

    test('ignores a library that only declares startCli', () {
      final source = Source.snippet('''
Future<TestProcess> startCli(List<String> arguments) => TestProcess.start('dart', arguments);
''', path: 'test/test_utils.dart');
      expect(findUntaggedCliRuns(source), isEmpty);
    });
  });
}

List<int> _lines(Iterable<ConventionViolation> violations) => [for (final v in violations) v.line];
