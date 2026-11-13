// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/models/convention_violation.dart';
import '../src/models/source.dart';
import '../src/skip_reasons.dart';

/// Runs the skip-reason detectors over small inline snippets, which pins
/// what each one reports independently of the package's tests.
void main() {
  group('findSkipsWithoutReason', () {
    test('accepts a string and a conditional of string and null', () {
      final source = Source.snippet(r'''
void main() {
  test('a', () {}, skip: 'needs a network connection');
  test('b', () {}, skip: isWindows ? 'uses the POSIX chmod command' : null);
  test('c', () {}, skip: (isWindows ? null : 'runs only on Windows'));
  test('d', () {}, skip: 'needs $tool on the PATH');
}
''');
      expect(findSkipsWithoutReason(source), isEmpty);
    });

    test('reports a boolean, an empty string, and a conditional with no string', () {
      final source = Source.snippet('''
void main() {
  test('a', () {}, skip: true);
  test('b', () {}, skip: isWindows);
  test('c', () {}, skip: '');
  test('d', () {}, skip: isWindows ? null : null);
  test('e', () {}, skip: isWindows ? 'fine' : true);
}
''');
      final List<ConventionViolation> violations = findSkipsWithoutReason(source);
      expect(_lines(violations), [2, 3, 4, 5, 6]);
      expect(violations.first.problem, 'skip: true has no reason');
    });

    test('ignores a positional skip', () {
      final source = Source.snippet('final Iterable<int> rest = [1, 2].skip(1);');
      expect(findSkipsWithoutReason(source), isEmpty);
    });
  });

  group('findTestOnWithoutComment', () {
    test('accepts a comment inside the call that names the platform', () {
      final source = Source.snippet('''
void main() {
  test('a', () {
    // Skipped on Windows: the test uses the POSIX chmod command.
  }, testOn: '!windows');
}
''');
      expect(findTestOnWithoutComment(source), isEmpty);
    });

    test('accepts any one of the platforms in the selector', () {
      final source = Source.snippet('''
void main() {
  test('a', () {
    // Skipped on Windows: the test uses the POSIX chmod command.
  }, testOn: 'vm && !windows');
  test('b', () {
    // Runs only on macOS, where the keychain exists.
  }, testOn: 'mac-os');
}
''');
      expect(findTestOnWithoutComment(source), isEmpty);
    });

    test('reports a comment that does not name the platform', () {
      final source = Source.snippet('''
void main() {
  test('a', () {
    // The operating system refuses to stat this directory.
  }, testOn: '!windows');
}
''');
      final ConventionViolation violation = findTestOnWithoutComment(source).single;
      expect(violation.line, 4);
      expect(violation.problem, "testOn: '!windows' has no comment naming the platform");
    });

    test('reports a comment outside the call and a selector that is not a literal', () {
      final source = Source.snippet('''
// Skipped on Windows: the test uses the POSIX chmod command.
void main() {
  test('a', () {}, testOn: '!windows');
  test('b', () {
    // Skipped on Windows: the test uses the POSIX chmod command.
  }, testOn: selector);
}
''');
      expect(_lines(findTestOnWithoutComment(source)), [3, 6]);
    });
  });

  group('findTimeoutsWithoutComment', () {
    test('accepts a comment above the timeout: argument or at the end of its line', () {
      final source = Source.snippet('''
void main() {
  test(
    'a',
    () {},
    // Compiles the CLI, which takes over 30 seconds on CI.
    timeout: const Timeout(Duration(minutes: 2)),
  );
  group('b', () {}, timeout: const Timeout.factor(2)); // Each test starts a subprocess.
}
''');
      expect(findTimeoutsWithoutComment(source), isEmpty);
    });

    test('reports a timeout: argument whose only comment is in the test body', () {
      final source = Source.snippet('''
void main() {
  test('a', () {
    // Arrange.
    expect(1, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('b', () {
    // Arrange.
  }, timeout: const Timeout.factor(2));
}
''');
      final List<ConventionViolation> violations = findTimeoutsWithoutComment(source);
      expect(_lines(violations), [5, 8]);
      expect(
        violations.first.problem,
        'timeout: const Timeout(Duration(minutes: 2)) has no comment saying why',
      );
    });

    test('accepts an @Timeout annotation with a comment above it or at the end of its line', () {
      final source = Source.snippet('''
// Copyright header.

// Every test in this file compiles the CLI, which takes over 30 seconds on CI.
@Timeout(Duration(minutes: 2))
library;

@test.Timeout.factor(2) // Starts a subprocess.
void main() {}
''');
      expect(findTimeoutsWithoutComment(source), isEmpty);
    });

    test('reports an @Timeout annotation after a blank line or an ignore comment', () {
      final source = Source.snippet('''
// Copyright header.

@Timeout.factor(2)
library;

// ignore: unused_element
@Timeout.factor(2)
void main() {}
''');
      final List<ConventionViolation> violations = findTimeoutsWithoutComment(source);
      expect(_lines(violations), [3, 7]);
      expect(violations.first.problem, '@Timeout.factor(2) has no comment saying why');
    });

    test('ignores a .timeout() method call and other annotations', () {
      final source = Source.snippet('''
@TestOn('vm')
library;

Future<void> run(Future<void> work) => work.timeout(const Duration(seconds: 1));
''');
      expect(findTimeoutsWithoutComment(source), isEmpty);
    });
  });
}

List<int> _lines(Iterable<ConventionViolation> violations) => [for (final v in violations) v.line];
