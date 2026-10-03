// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Absolute paths to the package and repository roots for repo checks.
///
/// Both paths come from the `package:skills_lint` URI in the package config,
/// so they do not depend on the working directory or on where a test file
/// sits under `test/`.
library;

import 'dart:isolate';

import 'package:path/path.dart' as p;

/// The absolute path of the `skills_lint` package, the directory that holds
/// its `pubspec.yaml`.
final String packageRoot = _resolvePackageRoot();

/// The absolute path of the repository root, two levels above [packageRoot].
final String repoRoot = p.normalize(p.join(packageRoot, '..', '..'));

String _resolvePackageRoot() {
  final Uri? libUri = Isolate.resolvePackageUriSync(Uri.parse('package:skills_lint/'));
  if (libUri == null) {
    throw StateError('package:skills_lint is not in the package config. Run `dart pub get`.');
  }
  return p.normalize(p.join(p.fromUri(libUri), '..'));
}
