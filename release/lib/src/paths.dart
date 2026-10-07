// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Directories that the release steps read from, found from the location of
/// this package so that the steps work from any working directory.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// The root directory of the `skills_lint_release` package: `release/` in
/// the repository.
final String releasePackageDir = p.dirname(
  p.fromUri(Isolate.resolvePackageUriSync(Uri.parse('package:skills_lint_release/'))),
);

/// The root directory of the repository.
final String repoRoot = p.dirname(releasePackageDir);

/// The root directory of the `skills_lint` package that the release ships.
final String skillsLintPackageDir = p.join(repoRoot, 'packages', 'skills_lint');

/// The directory that holds the licenses of the third-party code in the Dart
/// runtime. Its `README.md` gives the source of each file.
final String dartRuntimeLicensesDir = p.join(releasePackageDir, 'dart_runtime_licenses');

/// The root directory of the Dart SDK that runs this program.
final String dartSdkDir = p.dirname(p.dirname(Platform.resolvedExecutable));
