// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Source conventions that reviewers used to enforce by hand.
///
/// Each check parses the package's Dart files with the unresolved parser
/// (`parseString`) and inspects the syntax tree. No analysis context or type
/// resolution is involved, so a check sees only what is written in the file.
///
/// The `repository` group runs every check over the package. The `detector`
/// group runs the same detectors over small inline snippets, which pins what
/// each detector reports independently of the package's contents.
void main() {
  group('repository', () {
    late List<_Source> sources;

    setUpAll(() {
      sources = _parseDirectories(_scannedDirectories);
    });

    Iterable<_Source> under(List<String> directories) =>
        sources.where((source) => directories.any((d) => source.path.startsWith('$d/')));

    test('map keys and indices under lib/src/models/ are not string literals', () {
      final List<_Violation> violations = [];
      for (final _Source source in under(const ['lib/src/models'])) {
        violations.addAll(_findStringLiteralKeys(source));
      }
      _expectNoViolations(violations, fix: _stringLiteralKeyFix);
    });

    test('no string literal of $_minSharedLiteralLength+ characters is repeated across lib/', () {
      _expectNoViolations(_findSharedLiterals(under(const ['lib'])), fix: _sharedLiteralFix);
    });

    test('no operator ==, hashCode, or toString overrides', () {
      final List<_Violation> violations = [];
      for (final source in sources) {
        final Set<String> allowed = _allowedOverrides[source.path] ?? const {};
        violations.addAll(_findForbiddenOverrides(source, allowed: allowed));
      }
      _expectNoViolations(violations, fix: _forbiddenOverrideFix);
    });

    test('no constant in bin/ or lib/ is declared as an alias of another constant', () {
      _expectNoViolations(_findConstAliases(under(const ['bin', 'lib'])), fix: _constAliasFix);
    });
  });

  group('detector', () {
    group('string literal keys', () {
      test('reports string literal map keys and indices', () {
        final source = _Source.snippet('''
Map<String, Object?> toJson(Map<String, Object?> json) => {
  'uri': json['uri'],
  'nested': {'text': 'value'},
};
''');
        expect(_lines(_findStringLiteralKeys(source)), [2, 2, 3, 3]);
      });

      test('ignores constant keys, interpolated keys, and string values', () {
        final source = _Source.snippet(r'''
const String keyUri = 'uri';
Map<String, Object?> toJson(Map<String, Object?> json, String id) => {
  keyUri: json[keyUri],
  '$id': 'a string value is fine',
};
''');
        expect(_findStringLiteralKeys(source), isEmpty);
      });
    });

    group('shared literals', () {
      const long = 'This message is long enough to count.';

      test('reports a long literal that appears in two files', () {
        final List<_Violation> violations = _findSharedLiterals([
          _Source.snippet("final a = '$long';", path: 'lib/a.dart'),
          _Source.snippet('final b = "$long";', path: 'lib/b.dart'),
        ]);
        expect(violations.map((v) => v.path), ['lib/a.dart', 'lib/b.dart']);
      });

      test('matches an interpolation only when the expression is the same', () {
        const message = r'Could not read the file. Cause: $error';
        final List<_Violation> violations = _findSharedLiterals([
          _Source.snippet("String a(Object error) => '$message';", path: 'lib/a.dart'),
          _Source.snippet("String b(Object error) => '$message';", path: 'lib/b.dart'),
          _Source.snippet(r"String c(Object e) => 'Could not read the file. Cause: $e';"),
        ]);
        expect(violations.map((v) => v.path), ['lib/a.dart', 'lib/b.dart']);
      });

      test('counts only literal characters toward the minimum length', () {
        // 23 literal characters; the interpolated name does not count.
        const fragment = r'* **Current value:** `$skillNameWithALongIdentifier`';
        final List<_Violation> violations = _findSharedLiterals([
          _Source.snippet(
            "String a(String skillNameWithALongIdentifier) => '$fragment';",
            path: 'lib/a.dart',
          ),
          _Source.snippet(
            "String b(String skillNameWithALongIdentifier) => '$fragment';",
            path: 'lib/b.dart',
          ),
        ]);
        expect(violations, isEmpty);
      });

      test('ignores repeats within one file, directives, and annotations', () {
        const uri = 'package:skills_lint/src/models/validation_result.dart';
        final List<_Violation> violations = _findSharedLiterals([
          _Source.snippet("final a = '$long';\nfinal b = '$long';", path: 'lib/a.dart'),
          _Source.snippet("import '$uri';\n@Deprecated('$long')\nvoid b() {}", path: 'lib/b.dart'),
          _Source.snippet("import '$uri';\n@Deprecated('$long')\nvoid c() {}", path: 'lib/c.dart'),
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
        expect(_lines(_findForbiddenOverrides(_Source.snippet(overrides))), [3, 6, 9]);
      });

      test('skips the names in allowed', () {
        final List<_Violation> violations = _findForbiddenOverrides(
          _Source.snippet(overrides),
          allowed: const {'toString'},
        );
        expect(_lines(violations), [3, 6]);
      });

      test('ignores other members and top-level functions', () {
        final source = _Source.snippet('''
String toString() => 'not a member';
class Point {
  String describe() => 'Point';
  int operator +(Point other) => 0;
}
''');
        expect(_findForbiddenOverrides(source), isEmpty);
      });
    });

    group('const aliases', () {
      test('reports a const initialized with another declared const', () {
        final source = _Source.snippet('''
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
        expect(_lines(_findConstAliases([source])), [2, 5, 6, 9]);
      });

      test('reports an alias of a const declared in another file', () {
        final List<_Violation> violations = _findConstAliases([
          _Source.snippet("class SkillContext { static const String fileName = 'SKILL.md'; }"),
          _Source.snippet('class Rule { static const String _fileName = SkillContext.fileName; }'),
        ]);
        expect(violations.single.problem, '_fileName aliases SkillContext.fileName');
      });

      test('ignores enum values, literals, expressions, and local consts', () {
        final source = _Source.snippet('''
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
        expect(_findConstAliases([source]), isEmpty);
      });
    });
  });
}

/// Directories whose Dart files the checks read.
///
/// `evals/test_data/` is left out because its Dart files are fixtures that
/// are written to fail review on purpose.
const List<String> _scannedDirectories = ['benchmark', 'bin', 'example', 'lib', 'test'];

/// The fewest literal characters a string needs before the shared-literal
/// check compares it.
///
/// Shorter strings repeat for good reasons, such as JSON keys that belong
/// to different models, flag names, and `'SKILL.md'`.
const int _minSharedLiteralLength = 25;

/// Overrides that are allowed, keyed by package-relative path.
///
/// `ConfigSerializer` wraps a `StringBuffer`, and its `toString()` returns
/// the buffer contents in the same way `StringBuffer.toString()` does.
const Map<String, Set<String>> _allowedOverrides = {
  'lib/src/config_serializer.dart': {'toString'},
};

const Set<String> _forbiddenOverrideNames = {'==', 'hashCode', 'toString'};

const String _stringLiteralKeyFix =
    'Declare the key as a `static const String` on the model class that owns '
    "it (for example `static const String keyStartLine = 'startLine';`) and "
    'use that constant wherever the key is read or written.';

const String _sharedLiteralFix =
    'Declare the text once, in the library that owns the message, and '
    'reference it from every file. If the text interpolates values, move it '
    'into a function that takes those values. Do not declare a second '
    'constant that aliases the first; the const-alias check rejects that.';

const String _forbiddenOverrideFix =
    'Remove the override. The only allowed override is `toString()` in '
    'lib/src/config_serializer.dart.';

const String _constAliasFix =
    'Delete the second constant and reference the original constant directly.';

/// Reports string literals used as map keys or as indices.
List<_Violation> _findStringLiteralKeys(_Source source) {
  final List<_Violation> violations = [];
  for (final AstNode node in source.nodes) {
    final Expression? key = switch (node) {
      MapLiteralEntry(:final key) => key,
      IndexExpression(:final index) => index,
      _ => null,
    };
    if (key is SimpleStringLiteral) {
      violations.add(source.violationAt(key.offset, 'string literal key ${key.toSource()}'));
    }
  }
  return violations;
}

/// Reports string literals with at least [_minSharedLiteralLength] literal
/// characters that appear in two or more of [sources].
///
/// Literals are compared on the source text between their quotes, so `'a'`
/// and `"a"` match, and `'Cause: $error'` matches only a literal that
/// interpolates the same expression. Interpolated expressions do not count
/// toward the length. Each piece of an adjacent-string concatenation is
/// compared on its own. Directives and annotation arguments are skipped.
List<_Violation> _findSharedLiterals(Iterable<_Source> sources) {
  final Map<String, List<_Violation>> byText = {};
  for (final source in sources) {
    for (final SingleStringLiteral literal in source.nodes.whereType<SingleStringLiteral>()) {
      if (_literalLength(literal) >= _minSharedLiteralLength && !_isMetadata(literal)) {
        final String text = source.content.substring(literal.contentsOffset, literal.contentsEnd);
        byText.putIfAbsent(text, () => []).add(source.violationAt(literal.offset, 'repeats $text'));
      }
    }
  }
  final List<_Violation> violations = [];
  for (final List<_Violation> copies in byText.values) {
    if (copies.map((v) => v.path).toSet().length > 1) {
      violations.addAll(copies);
    }
  }
  return violations;
}

/// The number of characters in [literal] that are not interpolated.
int _literalLength(SingleStringLiteral literal) => switch (literal) {
  SimpleStringLiteral(:final value) => value.length,
  StringInterpolation(:final elements) => elements.whereType<InterpolationString>().fold(
    0,
    (sum, part) => sum + part.value.length,
  ),
};

/// Whether [node] is inside a directive or an annotation.
bool _isMetadata(AstNode node) =>
    node.thisOrAncestorOfType<Directive>() != null ||
    node.thisOrAncestorOfType<Annotation>() != null;

/// Reports declarations of `operator ==`, `hashCode`, and `toString` whose
/// name is not in [allowed].
List<_Violation> _findForbiddenOverrides(_Source source, {Set<String> allowed = const {}}) {
  final List<_Violation> violations = [];
  for (final MethodDeclaration method in source.nodes.whereType<MethodDeclaration>()) {
    final String name = method.name.lexeme;
    if (_forbiddenOverrideNames.contains(name) && !allowed.contains(name)) {
      violations.add(source.violationAt(method.name.offset, 'overrides $name'));
    }
  }
  return violations;
}

/// Reports top-level and static constants whose initializer is only the name
/// of another constant declared in [sources].
///
/// Enum values are not constant declarations, so
/// `static const Severity defaultSeverity = Severity.error;` passes.
List<_Violation> _findConstAliases(Iterable<_Source> sources) {
  final Set<String> declared = {};
  for (final source in sources) {
    for (final VariableDeclaration constant in _constDeclarations(source)) {
      declared.add(_qualifiedName(constant, constant.name.lexeme));
    }
  }
  final List<_Violation> violations = [];
  for (final source in sources) {
    for (final VariableDeclaration constant in _constDeclarations(source)) {
      final String? target = _aliasTarget(constant, declared);
      if (target != null) {
        final problem = '${constant.name.lexeme} aliases $target';
        violations.add(source.violationAt(constant.name.offset, problem));
      }
    }
  }
  return violations;
}

/// The top-level and static `const` variables declared in [source].
Iterable<VariableDeclaration> _constDeclarations(_Source source) =>
    source.nodes.whereType<VariableDeclaration>().where((variable) {
      final AstNode? list = variable.parent;
      final AstNode? declaration = list?.parent;
      final bool isMember =
          declaration is TopLevelVariableDeclaration || declaration is FieldDeclaration;
      return isMember && list is VariableDeclarationList && list.isConst;
    });

/// The declared constant that [constant]'s initializer names, or null if
/// the initializer is anything other than such a name.
///
/// A bare name inside a type is looked up as a member of that type first,
/// then as a top-level constant.
String? _aliasTarget(VariableDeclaration constant, Set<String> declared) {
  final List<String> candidates = switch (constant.initializer) {
    PrefixedIdentifier(:final String name) => [name],
    SimpleIdentifier(:final String name) => [_qualifiedName(constant, name), name],
    _ => const [],
  };
  return candidates.where(declared.contains).firstOrNull;
}

/// Qualifies [name] with the class, enum, or mixin that encloses [node].
String _qualifiedName(AstNode node, String name) {
  final String? typeName = switch (node.thisOrAncestorOfType<CompilationUnitMember>()) {
    final ClassDeclaration type => type.namePart.typeName.lexeme,
    final EnumDeclaration type => type.namePart.typeName.lexeme,
    final MixinDeclaration type => type.name.lexeme,
    _ => null,
  };
  return typeName == null ? name : '$typeName.$name';
}

/// Fails with one line per violation, followed by how to fix it.
void _expectNoViolations(Iterable<_Violation> violations, {required String fix}) {
  if (violations.isEmpty) {
    return;
  }
  final String report = violations.map((v) => v.describe()).join('\n');
  fail('${violations.length} violation(s):\n$report\n\nFix: $fix');
}

List<int> _lines(Iterable<_Violation> violations) => [for (final v in violations) v.line];

/// Parses every Dart file under [directories], skipping generated
/// `*.g.dart` files.
List<_Source> _parseDirectories(List<String> directories) {
  final List<_Source> sources = [];
  for (final directory in directories) {
    for (final File file in Directory(directory).listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart') && !file.path.endsWith('.g.dart')) {
        final String path = p.posix.joinAll(p.split(p.normalize(file.path)));
        sources.add(_Source(path, file.readAsStringSync()));
      }
    }
  }
  sources.sort((a, b) => a.path.compareTo(b.path));
  return sources;
}

/// A parsed Dart file and every node in its syntax tree.
class _Source {
  _Source(this.path, this.content) : _parsed = parseString(content: content, path: path);

  /// Wraps an inline [content] snippet for the detector tests.
  _Source.snippet(String content, {String path = 'lib/snippet.dart'}) : this(path, content);

  /// Package-relative path with `/` separators.
  final String path;
  final String content;
  final ParseStringResult _parsed;

  /// Every node of the syntax tree, in source order.
  late final List<AstNode> nodes = (_NodeCollector()..visitNode(_parsed.unit)).nodes;

  _Violation violationAt(int offset, String problem) =>
      _Violation(path, _parsed.lineInfo.getLocation(offset).lineNumber, problem);
}

class _Violation {
  _Violation(this.path, this.line, this.problem);

  final String path;

  /// 1-based line of the offending code.
  final int line;
  final String problem;

  String describe() => '$path:$line: $problem';
}

/// Collects every node of a syntax tree in source order.
class _NodeCollector extends GeneralizingAstVisitor<void> {
  final List<AstNode> nodes = [];

  @override
  void visitNode(AstNode node) {
    nodes.add(node);
    super.visitNode(node);
  }
}
