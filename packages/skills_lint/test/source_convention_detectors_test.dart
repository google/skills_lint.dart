// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'src/models/source.dart';
import 'src/models/violation.dart';
import 'src/source_conventions.dart';

/// Runs each source-convention detector over small inline snippets, which
/// pins what the detector reports independently of the package's contents.
void main() {
  group('string literal keys', () {
    test('reports string literal map keys and indices', () {
      final source = Source.snippet('''
Map<String, Object?> toJson(Map<String, Object?> json) => {
  'uri': json['uri'],
  'nested': {'text': 'value'},
};
''');
      expect(_lines(findStringLiteralKeys(source)), [2, 2, 3, 3]);
    });

    test('ignores constant keys, interpolated keys, and string values', () {
      final source = Source.snippet(r'''
const String keyUri = 'uri';
Map<String, Object?> toJson(Map<String, Object?> json, String id) => {
  keyUri: json[keyUri],
  '$id': 'a string value is fine',
};
''');
      expect(findStringLiteralKeys(source), isEmpty);
    });
  });

  group('shared literals', () {
    const long = 'This message is long enough to count.';

    test('reports a long literal that appears in two files', () {
      final List<Violation> violations = findSharedLiterals([
        Source.snippet("final a = '$long';", path: 'lib/a.dart'),
        Source.snippet('final b = "$long";', path: 'lib/b.dart'),
      ]);
      expect(violations.map((v) => v.path), ['lib/a.dart', 'lib/b.dart']);
    });

    test('matches an interpolation only when the expression is the same', () {
      const message = r'Could not read the file. Cause: $error';
      final List<Violation> violations = findSharedLiterals([
        Source.snippet("String a(Object error) => '$message';", path: 'lib/a.dart'),
        Source.snippet("String b(Object error) => '$message';", path: 'lib/b.dart'),
        Source.snippet(r"String c(Object e) => 'Could not read the file. Cause: $e';"),
      ]);
      expect(violations.map((v) => v.path), ['lib/a.dart', 'lib/b.dart']);
    });

    test('counts only literal characters toward the minimum length', () {
      // 17 literal characters; the interpolated name does not count.
      const fragment = r'Current value: `$skillNameWithALongIdentifier`';
      final List<Violation> violations = findSharedLiterals([
        Source.snippet(
          "String a(String skillNameWithALongIdentifier) => '$fragment';",
          path: 'lib/a.dart',
        ),
        Source.snippet(
          "String b(String skillNameWithALongIdentifier) => '$fragment';",
          path: 'lib/b.dart',
        ),
      ]);
      expect(violations, isEmpty);
    });

    test('ignores repeats within one file, directives, and annotations', () {
      const uri = 'package:skills_lint/src/models/validation_result.dart';
      final List<Violation> violations = findSharedLiterals([
        Source.snippet("final a = '$long';\nfinal b = '$long';", path: 'lib/a.dart'),
        Source.snippet("import '$uri';\n@Deprecated('$long')\nvoid b() {}", path: 'lib/b.dart'),
        Source.snippet("import '$uri';\n@Deprecated('$long')\nvoid c() {}", path: 'lib/c.dart'),
      ]);
      expect(violations, isEmpty);
    });
  });

  group('forbidden overrides', () {
    const overrides = '''
class Point {
  @override
  bool operator ==(Object other) => other is Point;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'Point';
}
''';

    test('reports operator ==, hashCode, and toString', () {
      expect(_lines(findForbiddenOverrides(Source.snippet(overrides))), [3, 6, 9]);
    });

    test('skips the names in allowed', () {
      final List<Violation> violations = findForbiddenOverrides(
        Source.snippet(overrides),
        allowed: const {'toString'},
      );
      expect(_lines(violations), [3, 6]);
    });

    test('ignores other members and top-level functions', () {
      final source = Source.snippet('''
String toString() => 'not a member';
class Point {
  String describe() => 'Point';
  int operator +(Point other) => 0;
}
''');
      expect(findForbiddenOverrides(source), isEmpty);
    });
  });

  group('const aliases', () {
    test('reports a const initialized with another declared const', () {
      final source = Source.snippet('''
const int topLevel = 1;
const int topLevelAlias = topLevel;
class Limits {
  static const int max = 1024;
  static const int defaultMax = max;
  static const int maxAlias = Limits.max;
}
class Other {
  static const int copied = Limits.max;
}
''');
      expect(_lines(findConstAliases([source])), [2, 5, 6, 9]);
    });

    test('reports an alias of a const declared in another file', () {
      final List<Violation> violations = findConstAliases([
        Source.snippet("class SkillContext { static const String fileName = 'SKILL.md'; }"),
        Source.snippet('class Rule { static const String _fileName = SkillContext.fileName; }'),
      ]);
      expect(violations.single.problem, '_fileName aliases SkillContext.fileName');
    });

    test('ignores enum values, literals, expressions, and local consts', () {
      final source = Source.snippet('''
enum Severity { error }
class Rule {
  static const int max = 1024;
  static const Severity defaultSeverity = Severity.error;
  static const int twice = max * 2;
  static const String name = 'rule';
  void run() {
    const int local = max;
  }
}
''');
      expect(findConstAliases([source]), isEmpty);
    });
  });
}

List<int> _lines(Iterable<Violation> violations) => [for (final v in violations) v.line];
