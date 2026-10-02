// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Detectors for `skip:` and `testOn:` arguments that don't say why a test
/// is skipped.
///
/// A skipped test is a gap in coverage. With the reason next to it, a reader
/// can tell a platform limit from a bug that someone should fix, and can
/// check whether the reason still holds.
///
/// Change these rules if `package:test` gains a way to attach a reason to
/// `testOn:`, or if a reason needs a form that they reject.
library;

import 'package:analyzer/dart/ast/ast.dart';

import 'models/convention_violation.dart';
import 'models/source.dart';

/// Reports each `skip:` argument in [source] whose value is not a reason.
///
/// A reason is a non-empty string literal, or a conditional expression whose
/// branches are such strings or `null`, with at least one string. The test
/// runner prints that string next to the skipped test.
List<ConventionViolation> findSkipsWithoutReason(Source source) => [
  for (final NamedArgument argument in _namedArguments(source, 'skip'))
    if (!_isReason(argument.argumentExpression))
      source.violationAt(argument.offset, '${argument.toSource()} has no reason'),
];

/// Reports each `testOn:` argument in [source] that has no comment naming
/// one of its platforms inside the same argument list.
///
/// The platforms are the names in the selector string, so `'!windows'` needs
/// a comment containing "windows". The match ignores case and hyphens, so
/// "macOS" names `mac-os`. A selector that is not a string literal names no
/// platform and is always reported.
List<ConventionViolation> findTestOnWithoutComment(Source source) {
  final List<ConventionViolation> violations = [];
  for (final NamedArgument argument in _namedArguments(source, 'testOn')) {
    final Set<String> platforms = _platforms(argument.argumentExpression);
    final AstNode arguments = argument.parent!;
    final bool named = source.comments
        .where((comment) => comment.offset > arguments.offset && comment.end < arguments.end)
        .map((comment) => _normalize(comment.lexeme))
        .any((text) => platforms.any(text.contains));
    if (!named) {
      final problem = '${argument.toSource()} has no comment naming the platform';
      violations.add(source.violationAt(argument.offset, problem));
    }
  }
  return violations;
}

/// The named arguments called [name] in any argument list of [source].
Iterable<NamedArgument> _namedArguments(Source source, String name) =>
    source.nodes.whereType<NamedArgument>().where((argument) => argument.name.lexeme == name);

bool _isReason(Expression value) => switch (value) {
  ParenthesizedExpression(:final expression) => _isReason(expression),
  ConditionalExpression(:final thenExpression, :final elseExpression) =>
    _isReasonOrNull(thenExpression) &&
        _isReasonOrNull(elseExpression) &&
        (thenExpression is! NullLiteral || elseExpression is! NullLiteral),
  StringLiteral(:final stringValue) => stringValue == null || stringValue.trim().isNotEmpty,
  _ => false,
};

bool _isReasonOrNull(Expression value) => value is NullLiteral || _isReason(value);

/// The normalized platform names in a `testOn:` selector literal.
Set<String> _platforms(Expression selector) {
  final String? text = selector is StringLiteral ? selector.stringValue : null;
  if (text == null) {
    return const {};
  }
  return {
    for (final Match match in RegExp(r'[A-Za-z][\w-]*').allMatches(text)) _normalize(match[0]!),
  };
}

String _normalize(String text) => text.toLowerCase().replaceAll('-', '');
