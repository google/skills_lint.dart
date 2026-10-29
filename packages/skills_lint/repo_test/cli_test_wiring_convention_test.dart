// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'src/cli_test_wiring.dart';
import 'src/models/convention_violation.dart';
import 'src/models/source.dart';
import 'src/source_conventions.dart';

/// Checks that every `defineCliTests()` in `test/` runs in both passes: from
/// its own file's `main`, and from `compiled_test/cli_test.dart` against the
/// compiled binary. Also checks that every `defineCliTests()` call in
/// `compiled_test/cli_test.dart` names a file that declares it.
///
/// `src/cli_test_wiring.dart` says why the rule exists, and
/// `checkers/cli_test_wiring_test.dart` pins what it reports.
void main() {
  final List<Source> testSources = parseDirectories(['test']);

  test('every test file that declares defineCliTests() calls it from main', () {
    final List<ConventionViolation> violations = [
      for (final Source source in testSources) ...findMainWithoutCliTests(source),
    ];
    expectNoViolations(violations, fix: "Call defineCliTests(); from the file's main.");
  });

  test('compiled_test/cli_test.dart calls every defineCliTests() and no other', () {
    final Source runner = parseDirectories([
      'compiled_test',
    ]).singleWhere((source) => source.path == 'compiled_test/cli_test.dart');
    expect(
      testSources.where(declaresCliTests),
      isNotEmpty,
      reason: 'No file declares defineCliTests().',
    );
    expectNoViolations(
      findCompiledRunnerGaps(runner, testSources),
      fix:
          'In compiled_test/cli_test.dart, import each test file that declares '
          'defineCliTests() with a prefix and call <prefix>.defineCliTests() from '
          "main, inside the 'compiled CLI' group, which sets up the compiled binary.",
    );
  });
}
