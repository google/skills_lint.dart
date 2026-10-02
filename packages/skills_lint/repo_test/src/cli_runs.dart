// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Detectors that keep every CLI run in the package tests reachable by the
/// `compiled_binary` CI job.
///
/// That job compiles the CLI with `dart compile exe` and runs
/// `dart test --tags=cli` with `SKILLS_LINT_EXECUTABLE` naming the
/// executable. A test reaches the executable only if it starts the CLI with
/// `startCli` from `test/test_utils.dart` and its library is tagged
/// [cliTag]. A test that names `bin/skills_lint.dart` itself, or that lacks
/// the tag, tests only the Dart script, and nothing reports the gap.
///
/// Change these rules if the CLI tests stop running against a compiled
/// executable, or if `startCli` moves or is renamed.
library;

import 'package:analyzer/dart/ast/ast.dart';

import 'models/convention_violation.dart';
import 'models/source.dart';

/// The `package:test` tag of test libraries that start the CLI.
const String cliTag = 'cli';

/// The script that `dart` runs when a test starts the CLI from source.
const String _cliScript = 'skills_lint.dart';

/// Reports each string literal in [source] that names the CLI script:
/// `skills_lint.dart` alone, as in `p.join('bin', 'skills_lint.dart')`, or a
/// path ending in `bin/skills_lint.dart`.
///
/// Import URIs are not reported.
List<ConventionViolation> findCliScriptPaths(Source source) => [
  for (final SingleStringLiteral literal in source.nodes.whereType<SingleStringLiteral>())
    if (literal.parent is! UriBasedDirective && _namesCliScript(literal))
      source.violationAt(literal.offset, '${literal.toSource()} names the CLI script'),
];

/// Reports the first call of `startCli` in [source] when the library is not
/// tagged [cliTag] with `@Tags`.
List<ConventionViolation> findUntaggedCliRuns(Source source) {
  final MethodInvocation? firstCall = source.nodes
      .whereType<MethodInvocation>()
      .where((call) => call.target == null && call.methodName.name == 'startCli')
      .firstOrNull;
  if (firstCall == null || _tags(source).contains(cliTag)) {
    return const [];
  }
  return [
    source.violationAt(
      firstCall.offset,
      "calls startCli but the library has no @Tags(['$cliTag'])",
    ),
  ];
}

/// Whether [literal] is the CLI script name or ends with its path. An
/// interpolated string is judged by its text after the last interpolation.
bool _namesCliScript(SingleStringLiteral literal) {
  final String text = switch (literal) {
    SimpleStringLiteral(:final value) => value,
    StringInterpolation(:final elements) => (elements.last as InterpolationString).value,
  };
  return text == _cliScript || text.endsWith('bin/$_cliScript');
}

/// The string tags in the `@Tags` annotation of the library directive.
Set<String> _tags(Source source) => {
  for (final SimpleStringLiteral literal in source.nodes.whereType<SimpleStringLiteral>())
    if (_isLibraryTagsAnnotation(literal.thisOrAncestorOfType<Annotation>())) literal.value,
};

bool _isLibraryTagsAnnotation(Annotation? annotation) =>
    annotation != null && annotation.parent is LibraryDirective && annotation.name.name == 'Tags';
