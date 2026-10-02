// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// CI runs one step per entry in [testDirectories]. A `*_test.dart` file
/// anywhere else in the package would run in no CI step.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/package_directories.dart';
import 'src/repo_paths.dart';

void main() {
  test('every test file is under a test directory that CI runs', () {
    final List<String> outside = [
      for (final String path in _testFilesInPackage())
        if (!testDirectories.any((dir) => path.startsWith('$dir/'))) path,
    ]..sort();
    expect(
      outside,
      isEmpty,
      reason:
          'Move each file under one of ${testDirectories.join(', ')}. See '
          '"Where tests go" in CONTRIBUTING.md.',
    );
  });
}

/// Returns every `*_test.dart` file in the package, relative to the package
/// root with `/` separators.
///
/// Skips hidden directories such as `.dart_tool/`, and `evals/test_data/`,
/// whose Dart files are fixtures.
List<String> _testFilesInPackage() =>
    [
          for (final File file in Directory(
            packageRoot,
          ).listSync(recursive: true).whereType<File>())
            if (file.path.endsWith('_test.dart'))
              p.split(p.relative(file.path, from: packageRoot)).join('/'),
        ]
        .where(
          (path) =>
              !path.split('/').any((s) => s.startsWith('.')) &&
              !path.startsWith('evals/test_data/'),
        )
        .toList();
