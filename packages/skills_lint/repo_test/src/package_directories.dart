// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// The package directories that repo tests read, in one place.
///
/// Paths are relative to the package root, with `/` separators. A check reads
/// [dartSourceDirectories] unless it names a subset below, and the subset's
/// doc says why.
library;

/// The test roots. CI runs `dart test` for `test` and `dart test repo_test`
/// for `repo_test`, so every test file must be under one of them.
const List<String> testDirectories = ['test', 'repo_test'];

/// The directories whose code ships in the published package.
///
/// Checks about published code, such as constant aliases, read only these.
const List<String> shippedDirectories = ['bin', 'lib'];

/// Every directory whose Dart files are checked by default, for example for
/// the copyright header and the source conventions.
///
/// `evals/test_data/` is left out because its Dart files are fixtures that
/// are written to fail review on purpose.
const List<String> dartSourceDirectories = [
  'benchmark',
  ...shippedDirectories,
  'example',
  ...testDirectories,
];
