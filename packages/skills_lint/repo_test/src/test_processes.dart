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
List<ConventionViolation> findDartTestProcesses(Source source) => [
  for (final MethodInvocation call in source.nodes.whereType<MethodInvocation>())
    if (_isTestProcessStart(call) && _isDartExecutable(_executable(call)))
      source.violationAt(
        call.offset,
        'TestProcess.start(${_executable(call)!.toSource()}, …) starts the Dart VM '
        'instead of calling startCli',
      ),
];

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

bool _isDartExecutable(Expression? executable) => switch (executable) {
  SimpleStringLiteral(:final value) => value == 'dart',
  ParenthesizedExpression(:final expression) => _isDartExecutable(expression),
  BinaryExpression(:final leftOperand, :final rightOperand) =>
    _isDartExecutable(leftOperand) || _isDartExecutable(rightOperand),
  ConditionalExpression(:final thenExpression, :final elseExpression) =>
    _isDartExecutable(thenExpression) || _isDartExecutable(elseExpression),
  PrefixedIdentifier(:final prefix, :final identifier) =>
    prefix.name == 'Platform' && identifier.name == 'resolvedExecutable',
  _ => false,
};
