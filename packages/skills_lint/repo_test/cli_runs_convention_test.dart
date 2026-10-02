// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'src/cli_runs.dart';
import 'src/models/convention_violation.dart';
import 'src/models/source.dart';
import 'src/source_conventions.dart';

/// Checks that every CLI run in `test/` reaches the compiled executable in
/// the `compiled_binary` CI job. See `src/cli_runs.dart` for why.
///
/// `checkers/cli_runs_test.dart` pins what each detector reports on small
/// snippets.
void main() {
  late List<Source> sources;

  setUpAll(() {
    sources = parseDirectories(const ['test']);
  });

  test('every test in test/ starts the CLI with startCli', () {
    final List<ConventionViolation> violations = [
      for (final Source source in sources)
        if (!_cliScriptPathAllowed.containsKey(source.path)) ...findCliScriptPaths(source),
    ];
    expectNoViolations(violations, fix: _cliScriptPathFix);
  });

  test('every test library in test/ that calls startCli is tagged $cliTag', () {
    final List<ConventionViolation> violations = [
      for (final Source source in sources) ...findUntaggedCliRuns(source),
    ];
    expectNoViolations(violations, fix: _untaggedCliRunFix);
  });
}

/// Files in test/ that may name the CLI script, keyed by package-relative
/// path, each with the reason.
const Map<String, String> _cliScriptPathAllowed = {
  'test/test_utils.dart': 'Defines startCli, which runs the script when no executable is set.',
  'test/benchmark/suite_test.dart':
      'Tests the benchmark harness, which times a command line. The CLI is only the command it '
      'times, and no assertion is about the CLI.',
};

const String _cliScriptPathFix =
    'Start the CLI with startCli from test/test_utils.dart, so the compiled_binary CI job also '
    "runs the test against the compiled executable. Tag the library with @Tags(['$cliTag']).";

const String _untaggedCliRunFix =
    "Add @Tags(['$cliTag']) before a `library;` directive at the top of the file. The "
    'compiled_binary CI job runs `dart test --tags=$cliTag` against the compiled executable, '
    'and an untagged file runs only against `dart bin/skills_lint.dart`.';
