// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/repo_paths.dart';

/// Checks `Formula/skills_lint.rb` against its template and the release.
void main() {
  test('matches its template, and its version follows the release rules', () async {
    // The release package generates the formula and is not a dependency of
    // skills_lint, so this runs its check.
    final ProcessResult result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/release.dart',
      'homebrew-formula',
      '--check',
    ], workingDirectory: p.join(repoRoot, 'release'));
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });
}
