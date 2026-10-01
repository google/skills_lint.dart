// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../src/models/convention_violation.dart';
import '../src/models/source.dart';
import '../src/source_conventions.dart';

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
      final List<ConventionViolation> violations = findForbiddenOverrides(
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
      final List<ConventionViolation> violations = findConstAliases([
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

List<int> _lines(Iterable<ConventionViolation> violations) => [for (final v in violations) v.line];
