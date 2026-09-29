// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Detectors that find source-convention violations in Dart files.
///
/// Each detector reads a syntax tree built by the unresolved parser
/// (`parseString`). No analysis context or type resolution is involved, so a
/// detector sees only what is written in the file.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The fewest literal characters a string needs before [findSharedLiterals]
/// compares it.
///
/// Shorter strings repeat for good reasons, such as JSON keys that belong
/// to different models, flag names, and `'SKILL.md'`.
const int minSharedLiteralLength = 25;

const Set<String> _forbiddenOverrideNames = {'==', 'hashCode', 'toString'};

/// Reports string literals used as map keys or as indices.
List<Violation> findStringLiteralKeys(Source source) {
  final List<Violation> violations = [];
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

/// Reports string literals with at least [minSharedLiteralLength] literal
/// characters that appear in two or more of [sources].
///
/// Literals are compared on the source text between their quotes, so `'a'`
/// and `"a"` match, and `'Cause: $error'` matches only a literal that
/// interpolates the same expression. Interpolated expressions do not count
/// toward the length. Each piece of an adjacent-string concatenation is
/// compared on its own. Directives and annotation arguments are skipped.
List<Violation> findSharedLiterals(Iterable<Source> sources) {
  final Map<String, List<Violation>> byText = {};
  for (final source in sources) {
    for (final SingleStringLiteral literal in source.nodes.whereType<SingleStringLiteral>()) {
      if (_literalLength(literal) >= minSharedLiteralLength && !_isMetadata(literal)) {
        final String text = source.content.substring(literal.contentsOffset, literal.contentsEnd);
        byText.putIfAbsent(text, () => []).add(source.violationAt(literal.offset, 'repeats $text'));
      }
    }
  }
  final List<Violation> violations = [];
  for (final List<Violation> copies in byText.values) {
    if (copies.map((v) => v.path).toSet().length > 1) {
      violations.addAll(copies);
    }
  }
  return violations;
}

/// The number of characters in [literal] that are not interpolated.
int _literalLength(SingleStringLiteral literal) {
  switch (literal) {
    case SimpleStringLiteral(:final value):
      return value.length;
    case StringInterpolation(:final elements):
      var length = 0;
      for (final InterpolationString part in elements.whereType<InterpolationString>()) {
        length += part.value.length;
      }
      return length;
  }
}

/// Whether [node] is inside a directive or an annotation.
bool _isMetadata(AstNode node) =>
    node.thisOrAncestorOfType<Directive>() != null ||
    node.thisOrAncestorOfType<Annotation>() != null;

/// Reports declarations of `operator ==`, `hashCode`, and `toString` whose
/// name is not in [allowed].
List<Violation> findForbiddenOverrides(Source source, {Set<String> allowed = const {}}) {
  final List<Violation> violations = [];
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
List<Violation> findConstAliases(Iterable<Source> sources) {
  final Set<String> declared = {};
  for (final source in sources) {
    for (final VariableDeclaration constant in _constDeclarations(source)) {
      declared.add(_qualifiedName(constant, constant.name.lexeme));
    }
  }
  final List<Violation> violations = [];
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
Iterable<VariableDeclaration> _constDeclarations(Source source) =>
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
void expectNoViolations(Iterable<Violation> violations, {required String fix}) {
  if (violations.isEmpty) {
    return;
  }
  final String report = violations.map((v) => v.describe()).join('\n');
  fail('${violations.length} violation(s):\n$report\n\nFix: $fix');
}

/// Parses every Dart file under [directories], skipping generated
/// `*.g.dart` files.
List<Source> parseDirectories(List<String> directories) {
  final List<Source> sources = [];
  for (final directory in directories) {
    for (final File file in Directory(directory).listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart') && !file.path.endsWith('.g.dart')) {
        final String path = p.posix.joinAll(p.split(p.normalize(file.path)));
        sources.add(Source(path, file.readAsStringSync()));
      }
    }
  }
  sources.sort((a, b) => a.path.compareTo(b.path));
  return sources;
}

/// A parsed Dart file and every node in its syntax tree.
class Source {
  Source(this.path, this.content) : _parsed = parseString(content: content, path: path);

  /// Wraps an inline [content] snippet for the detector tests.
  Source.snippet(String content, {String path = 'lib/snippet.dart'}) : this(path, content);

  /// Package-relative path with `/` separators.
  final String path;
  final String content;
  final ParseStringResult _parsed;

  /// Every node of the syntax tree, in source order.
  late final List<AstNode> nodes = (_NodeCollector()..visitNode(_parsed.unit)).nodes;

  Violation violationAt(int offset, String problem) =>
      Violation(path, _parsed.lineInfo.getLocation(offset).lineNumber, problem);
}

/// One convention violation: where it is and what is wrong.
class Violation {
  Violation(this.path, this.line, this.problem);

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
