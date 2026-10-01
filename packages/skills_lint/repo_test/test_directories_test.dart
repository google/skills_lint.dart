// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// CI selects tests by directory, one step per entry in [testCategories]. A
/// test file outside every one of those directories would run under a plain
/// `dart test` but in no CI step.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'src/repo_paths.dart';
import 'src/test_categories.dart';

void main() {
  test('every test file is in a test directory that CI runs', () {
    final List<String> orphans = [
      for (final File file in Directory(
        p.join(packageRoot, 'test'),
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('_test.dart'))
          p.split(p.relative(file.path, from: packageRoot)).join('/'),
    ].where((path) => !testCategories.any((dir) => path.startsWith('$dir/'))).toList()..sort();
    expect(
      orphans,
      isEmpty,
      reason:
          'Move each file into one of ${testCategories.join(', ')}. See '
          '"Where tests go" in CONTRIBUTING.md.',
    );
  });
}
