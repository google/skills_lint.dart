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

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'models/source.dart';
import 'models/violation.dart';

/// The fewest literal characters a string needs before [findSharedLiterals]
/// compares it.
///
/// 20 is the lowest value at which `lib/` passes without extracting markdown
/// fragments such as `'**How to fix:**\n'`; short identifiers and JSON keys
/// are caught by [findStringLiteralKeys] and [findConstAliases] instead of by
/// length.
const int minSharedLiteralLength = 20;

const Set<String> _forbiddenOverrideNames = {'==', 'hashCode', 'toString'};

/// Reports string literals used as map keys or as indices.
///
/// A key typed as a literal can be misspelled in one place and still
/// compile, so a model that reads and writes the same key can drift apart.
/// A named constant makes every use refer to one spelling.
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
///
/// A message copied into several files gets edited in one and not the
/// others, so the tool says different things for the same situation.
/// Declaring it once gives it a single owner.
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
///
/// These overrides change equality and printing for every caller, and a
/// hand-written `==` and `hashCode` pair silently breaks when a field is
/// added and only one of them is updated.
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
/// An alias gives one value two names, so readers must check that both
/// still mean the same thing, and a search for one name misses the other.
List<Violation> findConstAliases(Iterable<Source> sources) {
  // Enum values are not constant declarations, so
  // `static const Severity defaultSeverity = Severity.error;` passes.
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

/// Returns a [Source] for every Dart file under [directories], sorted by
/// path, skipping generated `*.g.dart` files.
List<Source> parseDirectories(List<String> directories) {
  final skippedSourceFile = RegExp(r'\.g\.dart$');
  final List<Source> sources = [];
  for (final directory in directories) {
    for (final File file in Directory(directory).listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.dart') && !skippedSourceFile.hasMatch(file.path)) {
        final String path = p.posix.joinAll(p.split(p.normalize(file.path)));
        sources.add(Source(path, file.readAsStringSync()));
      }
    }
  }
  sources.sort((a, b) => a.path.compareTo(b.path));
  return sources;
}
