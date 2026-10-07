// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A detector for tests that start the Dart VM with `TestProcess.start`
/// instead of calling `startCli` from `test/test_utils.dart`.
///
/// `compiled_test/` runs the CLI tests a second time against a binary built
/// by `dart compile exe`, the build that releases ship. It can only swap in
/// that binary through `startCli`. A test that starts `dart` itself runs the
/// CLI from source in both passes, so the compiled binary goes untested.
///
/// Change this rule if the CLI tests stop running against a compiled binary,
/// or if a test needs to start the Dart VM for something other than the CLI.
library;

import 'package:analyzer/dart/ast/ast.dart';

import 'models/convention_violation.dart';
import 'models/source.dart';

/// Reports each `TestProcess.start` call in [source] whose executable can
/// be the string literal `'dart'` or `Platform.resolvedExecutable`, either
/// directly or as an operand of `??` or `?:`.
///
/// Calls with any other executable, such as a shell script, are ignored, as
/// are `Process.run` and `Process.start`, which tests use for helper tools
/// rather than for the CLI under test.
List<ConventionViolation> findDartTestProcesses(Source source) {
  final List<ConventionViolation> violations = [];
  for (final MethodInvocation call in source.nodes.whereType<MethodInvocation>()) {
    if (!_isTestProcessStart(call)) {
      continue;
    }
    final Expression? executable = _executable(call);
    if (executable == null || !_canBeDart(executable)) {
      continue;
    }
    violations.add(
      source.violationAt(
        call.offset,
        'TestProcess.start(${executable.toSource()}, …) starts the Dart VM '
        'instead of calling startCli',
      ),
    );
  }
  return violations;
}

bool _isTestProcessStart(MethodInvocation call) =>
    call.methodName.name == 'start' &&
    switch (call.target) {
      SimpleIdentifier(name: 'TestProcess') => true,
      PrefixedIdentifier(identifier: SimpleIdentifier(name: 'TestProcess')) => true,
      _ => false,
    };

/// The first positional argument of [call], which `TestProcess.start` takes
/// as the executable.
Expression? _executable(MethodInvocation call) {
  for (final Argument argument in call.argumentList.arguments) {
    if (argument is! NamedArgument) {
      return argument.argumentExpression;
    }
  }
  return null;
}

/// Whether [executable] can evaluate to `'dart'` or
/// `Platform.resolvedExecutable`.
///
/// `compiled ?? 'dart'` and `compiled != null ? compiled : 'dart'` both can,
/// so each branch of `??` and `?:` is checked.
bool _canBeDart(Expression executable) {
  final Expression expression = executable.unParenthesized;
  if (_isDartLiteral(expression) || _isResolvedExecutable(expression)) {
    return true;
  }
  return _branches(expression).any(_canBeDart);
}

/// `'dart'` or `"dart"`.
bool _isDartLiteral(Expression expression) =>
    expression is SimpleStringLiteral && expression.value == 'dart';

/// `Platform.resolvedExecutable`, the path of the running Dart VM.
bool _isResolvedExecutable(Expression expression) =>
    expression is PrefixedIdentifier &&
    expression.prefix.name == 'Platform' &&
    expression.identifier.name == 'resolvedExecutable';

/// The parts of [expression] that [_canBeDart] also checks: both operands of
/// a binary expression such as `a ?? b`, both results of `c ? a : b`, and
/// none for any other expression.
List<Expression> _branches(Expression expression) => switch (expression) {
  BinaryExpression(:final leftOperand, :final rightOperand) => [leftOperand, rightOperand],
  ConditionalExpression(:final thenExpression, :final elseExpression) => [
    thenExpression,
    elseExpression,
  ],
  _ => const [],
};
