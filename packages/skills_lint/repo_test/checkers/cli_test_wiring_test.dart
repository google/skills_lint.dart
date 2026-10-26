// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/cli_test_wiring.dart';
import '../src/models/convention_violation.dart';
import '../src/models/source.dart';

/// Runs the detectors in `src/cli_test_wiring.dart` over inline snippets, so
/// the repo-wide scan in `cli_test_wiring_convention_test.dart` can trust what they
/// report and what they ignore.
void main() {
  group('findMainWithoutCliTests', () {
    test('reports a main that does not call defineCliTests()', () {
      final source = Source.snippet('''
void main() {
  test('unit', () {});
}

void defineCliTests() {}
''', path: 'test/a_test.dart');
      final List<ConventionViolation> violations = findMainWithoutCliTests(source);
      expect(_lines(violations), [1]);
      expect(violations.single.problem, contains('main does not call defineCliTests()'));
    });

    test('reports a file with defineCliTests() and no main', () {
      final source = Source.snippet('void defineCliTests() {}\n', path: 'test/a_test.dart');
      expect(findMainWithoutCliTests(source).single.problem, contains('has no main'));
    });

    test("reports a prefixed call, which runs some other file's tests", () {
      final source = Source.snippet('''
void main() {
  other.defineCliTests();
}

void defineCliTests() {}
''', path: 'test/a_test.dart');
      expect(_lines(findMainWithoutCliTests(source)), [1]);
    });

    test('ignores a file that calls it, and a file that does not declare it', () {
      final calls = Source.snippet('''
void main() {
  group('g', () {});
  defineCliTests();
}

void defineCliTests() {}
''', path: 'test/a_test.dart');
      final declaresNothing = Source.snippet('void main() {}\n', path: 'test/b_test.dart');
      expect(findMainWithoutCliTests(calls), isEmpty);
      expect(findMainWithoutCliTests(declaresNothing), isEmpty);
    });
  });

  group('findCompiledRunnerGaps', () {
    final declaresA = Source.snippet(
      'void main() {}\nvoid defineCliTests() {}\n',
      path: 'test/a_test.dart',
    );
    final declaresB = Source.snippet(
      'void main() {}\nvoid defineCliTests() {}\n',
      path: 'test/sub/b_test.dart',
    );
    final declaresNothing = Source.snippet('void main() {}\n', path: 'test/c_test.dart');
    final testSources = [declaresA, declaresB, declaresNothing];

    Source runner(String content) => Source.snippet(content, path: 'compiled_test/cli_test.dart');

    test('accepts a runner that imports and calls every declaring file', () {
      final Source source = runner('''
import '../test/a_test.dart' as a;
import '../test/sub/b_test.dart' as b;
import '../test/c_test.dart' as c;

void main() {
  group('compiled CLI', () {
    a.defineCliTests();
    b.defineCliTests();
    c.main();
  });
}
''');
      expect(findCompiledRunnerGaps(source, testSources), isEmpty);
    });

    test("counts only calls inside main's 'compiled CLI' group", () {
      final Source source = runner('''
import '../test/a_test.dart' as a;
import '../test/sub/b_test.dart' as b;

void main() {
  group('compiled CLI', () {
    a.defineCliTests();
  });
  b.defineCliTests();
}

void unused() {
  group('compiled CLI', () {
    b.defineCliTests();
  });
}
''');
      final List<ConventionViolation> violations = findCompiledRunnerGaps(source, testSources);
      expect(_lines(violations), [2]);
      expect(
        violations.single.problem,
        contains("add b.defineCliTests(); inside main's 'compiled CLI' group"),
      );
    });

    test('reports a declaring file that is imported but never called', () {
      final Source source = runner('''
import '../test/a_test.dart' as a;
import '../test/sub/b_test.dart' as b;

void main() {
  group('compiled CLI', () {
    a.defineCliTests();
  });
}
''');
      final List<ConventionViolation> violations = findCompiledRunnerGaps(source, testSources);
      expect(_lines(violations), [2]);
      expect(violations.single.problem, contains('add b.defineCliTests();'));
    });

    test('reports a declaring file that is not imported, or imported without a prefix', () {
      final Source source = runner('''
import 'package:test/test.dart';
import '../test/a_test.dart';

void main() {}
''');
      final List<ConventionViolation> violations = findCompiledRunnerGaps(source, testSources);
      expect(_lines(violations), [2, 1]);
      expect(violations.map((v) => v.problem), [
        "test/a_test.dart declares defineCliTests() but is imported without a prefix; use import '../test/a_test.dart' as <prefix>;",
        "test/sub/b_test.dart declares defineCliTests() but is not imported; add import '../test/sub/b_test.dart' as <prefix>;",
      ]);
    });

    test('reports a call whose file does not declare defineCliTests(), or is not imported', () {
      final Source source = runner('''
import 'package:test/test.dart' as pkg;
import '../test/a_test.dart' as a;
import '../test/sub/b_test.dart' as b;
import '../test/c_test.dart' as c;

void main() {
  group('compiled CLI', () {
    a.defineCliTests();
    b.defineCliTests();
    c.defineCliTests();
    pkg.defineCliTests();
    missing.defineCliTests();
  });
}
''');
      final List<ConventionViolation> violations = findCompiledRunnerGaps(source, testSources);
      expect(_lines(violations), [10, 11, 12]);
      expect(violations[0].problem, contains('names test/c_test.dart, which does not declare'));
      expect(
        violations[1].problem,
        contains('names package:test/test.dart, which does not declare'),
      );
      expect(violations[2].problem, contains('names no imported file'));
    });

    test('accepts a file imported twice under two prefixes', () {
      final Source source = runner('''
import '../test/a_test.dart' as a;
import '../test/a_test.dart' as a2;
import '../test/sub/b_test.dart' as b;

void main() {
  group('compiled CLI', () {
    a.defineCliTests();
    b.defineCliTests();
  });
}
''');
      expect(findCompiledRunnerGaps(source, testSources), isEmpty);
    });
  });
}

List<int> _lines(Iterable<ConventionViolation> violations) => [for (final v in violations) v.line];
