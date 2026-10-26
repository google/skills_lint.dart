// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Detectors for CLI tests that are not wired to run in both passes.
///
/// A test file under `test/` that starts the CLI puts those tests in a
/// public top-level `void defineCliTests()`. Its `main` calls the function to
/// run the tests from source, and `compiled_test/cli_test.dart` imports the
/// file and calls the function to run the same tests against the binary built
/// by `dart compile exe`, the build that releases ship. If either call is
/// missing, one pass silently skips those tests. The analyzer does not warn,
/// because the function is public.
///
/// Change this rule if the CLI tests stop running against a compiled binary,
/// or if `compiled_test/` finds the CLI tests some other way.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import 'models/convention_violation.dart';
import 'models/source.dart';

/// The name of the function that holds a test file's CLI tests.
const String cliTestsFunction = 'defineCliTests';

/// Whether [source] declares a top-level function named [cliTestsFunction].
bool declaresCliTests(Source source) => _topLevelFunction(source, cliTestsFunction) != null;

/// Reports [source] if it declares [cliTestsFunction] but its top-level
/// `main` does not call it, so the tests never run from source.
///
/// An unprefixed call anywhere inside `main`, including inside a closure
/// such as a `group` body, counts.
List<ConventionViolation> findMainWithoutCliTests(Source source) {
  final FunctionDeclaration? declaration = _topLevelFunction(source, cliTestsFunction);
  if (declaration == null) {
    return const [];
  }
  final FunctionDeclaration? main = _topLevelFunction(source, 'main');
  final bool called =
      main != null &&
      _invocations(
        main,
      ).any((call) => call.target == null && call.methodName.name == cliTestsFunction);
  if (called) {
    return const [];
  }
  return [
    source.violationAt(
      (main ?? declaration).offset,
      main == null
          ? 'declares $cliTestsFunction() but has no main to call it'
          : 'main does not call $cliTestsFunction(), so these CLI tests never run from source',
    ),
  ];
}

/// Checks that [runner], `compiled_test/cli_test.dart`, runs the CLI tests
/// of every file in [testSources] that declares [cliTestsFunction], and that
/// each `<prefix>.defineCliTests()` call in [runner] names a file that
/// declares it.
///
/// Only calls inside [runner]'s top-level `main`, including inside closures
/// such as the `group` body, count. Import URIs in [runner] are resolved relative to its directory and
/// compared with each [Source.path].
List<ConventionViolation> findCompiledRunnerGaps(Source runner, Iterable<Source> testSources) {
  final Map<String, ImportDirective> importsByPath = {
    for (final ImportDirective import in runner.unit.directives.whereType<ImportDirective>())
      if (import.uri.stringValue case final String uri) _resolve(runner.path, uri): import,
  };
  final Map<String, MethodInvocation> callsByPrefix = _prefixedCallsInMain(runner);
  final Set<String> declaringPaths = {
    for (final Source source in testSources)
      if (declaresCliTests(source)) source.path,
  };
  final Map<String, String> pathsByPrefix = {
    for (final MapEntry(key: path, value: import) in importsByPath.entries)
      if (import.prefix?.name case final String prefix) prefix: path,
  };
  return [
    for (final String path in declaringPaths.toList()..sort())
      ?_uncalledDeclaration(runner, path, importsByPath[path], callsByPrefix.keys.toSet()),
    for (final MapEntry(key: prefix, value: call) in callsByPrefix.entries)
      if (pathsByPrefix[prefix] case final path when path == null || !declaringPaths.contains(path))
        runner.violationAt(
          call.offset,
          '$prefix.$cliTestsFunction() names ${path ?? 'no imported file'}, which does not '
          'declare $cliTestsFunction(); declare it there or remove this call',
        ),
  ];
}

/// Reports [path], which declares [cliTestsFunction], unless [import], its
/// import in [runner], has a prefix in [calledPrefixes].
ConventionViolation? _uncalledDeclaration(
  Source runner,
  String path,
  ImportDirective? import,
  Set<String> calledPrefixes,
) {
  final String? prefix = import?.prefix?.name;
  if (import == null || prefix == null) {
    // With no import to point at, report line 1 of the runner.
    return runner.violationAt(
      import?.offset ?? 0,
      '$path declares $cliTestsFunction() but is not imported with a prefix; add '
      "import '${p.posix.relative(path, from: p.posix.dirname(runner.path))}' as <prefix>;",
    );
  }
  if (calledPrefixes.contains(prefix)) {
    return null;
  }
  return runner.violationAt(
    import.offset,
    '$path declares $cliTestsFunction() but it is never called here, so these CLI tests '
    'never run against the compiled binary; add $prefix.$cliTestsFunction(); to main',
  );
}

/// Each `<prefix>.defineCliTests()` call inside [source]'s top-level `main`,
/// keyed by prefix.
Map<String, MethodInvocation> _prefixedCallsInMain(Source source) => {
  if (_topLevelFunction(source, 'main') case final FunctionDeclaration main)
    for (final MethodInvocation call in _invocations(main))
      if (call.target case SimpleIdentifier(
        :final name,
      ) when call.methodName.name == cliTestsFunction)
        name: call,
};

FunctionDeclaration? _topLevelFunction(Source source, String name) {
  for (final FunctionDeclaration function
      in source.unit.declarations.whereType<FunctionDeclaration>()) {
    if (function.name.lexeme == name) {
      return function;
    }
  }
  return null;
}

/// Every method invocation under [node], including nested ones.
Iterable<MethodInvocation> _invocations(AstNode node) sync* {
  for (final AstNode child in node.childEntities.whereType<AstNode>()) {
    if (child is MethodInvocation) {
      yield child;
    }
    yield* _invocations(child);
  }
}

/// The package-relative path that [uri], imported from [fromPath], names.
String _resolve(String fromPath, String uri) =>
    p.posix.normalize(p.posix.join(p.posix.dirname(fromPath), uri));
