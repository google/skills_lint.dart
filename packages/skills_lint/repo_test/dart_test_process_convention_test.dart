// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'src/models/convention_violation.dart';
import 'src/models/source.dart';
import 'src/package_directories.dart';
import 'src/source_conventions.dart';
import 'src/test_processes.dart';

/// Checks that tests start the CLI through `startCli`, so `compiled_test/`
/// can run the same tests against the compiled binary.
///
/// `src/test_processes.dart` says why the rule exists, and
/// `checkers/test_processes_test.dart` pins which calls it reports.
void main() {
  test('no test outside the allowlist starts the Dart VM with TestProcess.start', () {
    final List<ConventionViolation> violations = [
      for (final Source source in parseDirectories(testDirectories))
        if (!_allowed.containsKey(source.path)) ...findDartTestProcesses(source),
    ];
    expectNoViolations(violations, fix: _fix);
  });
}

/// Files that may start the Dart VM with `TestProcess.start`, keyed by
/// package-relative path, each with its reason.
const Map<String, String> _allowed = {
  'test/test_utils.dart':
      'Defines startCli, which runs `dart bin/skills_lint.dart` unless '
      'compiled_test/ gives it a compiled binary.',
};

const String _fix =
    'Start the CLI with startCli from test/test_utils.dart instead. If the file '
    'is not yet run from compiled_test/cli_test.dart, call its CLI tests from '
    'there too, so they also run against the compiled binary.';
