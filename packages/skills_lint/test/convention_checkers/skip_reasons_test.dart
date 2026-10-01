// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'src/models/convention_violation.dart';
import 'src/models/source.dart';
import 'src/skip_reasons.dart';

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
}

List<int> _lines(Iterable<ConventionViolation> violations) => [for (final v in violations) v.line];
