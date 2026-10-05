// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Runs the CLI tests from `test/` against a binary built by
/// `dart compile exe`, the build that releases ship.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../test/benchmark/fixture_test.dart' as benchmark_fixture;
import '../test/cli_integration_test.dart' as cli_integration;
import '../test/config_file_test.dart' as config_file;
import '../test/description_length_limit_test.dart' as description_length_limit;
import '../test/example_fixtures_test.dart' as example_fixtures;
import '../test/test_utils.dart';

void main() {
  late Directory outputDir;

  // Compiling takes longer than the default 30 seconds on some CI runners,
  // so the group that compiles gets more time and the tests inside get the
  // default back.
  group('compiled CLI', timeout: const Timeout(Duration(minutes: 5)), () {
    setUpAll(() async {
      outputDir = await Directory.systemTemp.createTemp('compiled_cli.');
      final String executable = p.join(
        outputDir.path,
        Platform.isWindows ? 'skills_lint.exe' : 'skills_lint',
      );
      final ProcessResult result = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'exe',
        '--verbosity=error',
        p.join('bin', 'skills_lint.dart'),
        '-o',
        executable,
      ]);
      if (result.exitCode != 0) {
        fail(
          '`dart compile exe` exited ${result.exitCode}, so no compiled CLI '
          'exists to test. Fix the compile error below.\n'
          'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
        );
      }
      useCompiledCli(executable);
    });

    tearDownAll(() async {
      await outputDir.delete(recursive: true);
    });

    group('tests', timeout: const Timeout(Duration(seconds: 30)), () {
      cli_integration.main();
      example_fixtures.main();
      config_file.cliTests();
      description_length_limit.cliTests();
      benchmark_fixture.cliTests();
    });
  });
}
