// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Reads the release targets that the Homebrew formula installs.
///
/// `releaseTargets` in `release/lib/src/archive.dart` is the one list of
/// targets. The `release` package is not a dependency of `skills_lint`, so
/// this runs its `homebrew-matrix` command, the same command that gives
/// `.github/workflows/homebrew.yaml` its install matrix.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'repo_paths.dart';

/// The prefix of the line that `release homebrew-matrix` prints.
const String _matrixPrefix = 'matrix=';

/// Returns the name of each target that the Homebrew formula installs, such
/// as `macos-arm64`, in the order of `releaseTargets`.
///
/// Throws a [StateError] if the command fails or prints something else.
Future<List<String>> readHomebrewTargets() async {
  final ProcessResult result = await Process.run(Platform.resolvedExecutable, [
    'run',
    'bin/release.dart',
    'homebrew-matrix',
  ], workingDirectory: p.join(repoRoot, 'release'));
  final output = result.stdout as String;
  if (result.exitCode != 0 || !output.startsWith(_matrixPrefix)) {
    throw StateError(
      '`dart run bin/release.dart homebrew-matrix` in release/ failed with exit code '
      '${result.exitCode}.\nstdout: $output\nstderr: ${result.stderr}',
    );
  }
  final String json = output.substring(_matrixPrefix.length).trim();
  final matrix = jsonDecode(json) as Map<String, Object?>;
  final List<String> targets = [];
  for (final entry in matrix['include']! as List<Object?>) {
    final target = (entry! as Map<String, Object?>)['target']! as String;
    targets.add(target);
  }
  return targets;
}
